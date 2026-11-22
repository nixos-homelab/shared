import json

manifests = "/var/lib/k3s/server/manifests"
kubectl = "k3s kubectl"

node.start()
node.wait_for_unit("k3s.service")

with subtest("k3s: the node comes up Ready on k3s' bundled network"):
    node.wait_until_succeeds(f"{kubectl} wait node node --for=condition=Ready --timeout=10s", timeout=600)
    node.wait_until_succeeds(f"{kubectl} -n kube-system rollout status deploy/coredns --timeout=10s", timeout=600)

with subtest("k3s: its bundled metrics-server answers the metrics API"):
    node.succeed(
        f"{kubectl} -n kube-system get deploy metrics-server -o jsonpath='{{.spec.template.spec.containers[0].image}}'"
        " | grep -q rancher/mirrored-metrics-server"
    )
    try:
        node.wait_until_succeeds(f"{kubectl} -n kube-system rollout status deploy/metrics-server --timeout=10s", timeout=300)
        node.wait_until_succeeds(f"{kubectl} top node", timeout=300)
    except Exception:
        node.execute(f"{kubectl} get pods -A -o wide >&2; {kubectl} get apiservice v1beta1.metrics.k8s.io -o yaml >&2")
        node.execute(f"{kubectl} -n kube-system logs deploy/metrics-server --tail=40 >&2")
        raise
    node.wait_until_succeeds(f"{kubectl} top pod -n kube-system", timeout=120)

with subtest("k3s: a deploy removes the manifests it no longer has, with their Addons and objects, none of k3s' own"):
    addons = f"{kubectl} -n kube-system get addon -o jsonpath='{{.items[*].metadata.name}}'"
    before = set(node.succeed(addons).split())
    node.succeed(f"ln -s $(readlink -f /etc/k3s-prune-test/takeover.yaml) {manifests}/takeover.yaml")
    configmap = f"{kubectl} -n default get configmap takeover"
    node.wait_until_succeeds(configmap, timeout=120)
    # Applied after k3s' rolebindings.yaml, it took the binding over. Until a pass over the manifests goes through
    # without an error (cert-manager.yaml fails while the webhook of cert-manager is down), k3s applies all of them
    # again 15 s after each pass, by name, so the manifest sorts after rolebindings.yaml to stay last
    binding = f"{kubectl} get clusterrolebinding kube-apiserver-kubelet-admin"
    owner = f"{binding} -o jsonpath='{{.metadata.annotations.objectset\\.rio\\.cattle\\.io/owner-name}}'"
    node.wait_until_succeeds(f"test \"$({owner})\" = takeover", timeout=60)
    # What switch-to-configuration does when the links change: both units changed, so it restarts them
    node.succeed("systemctl restart k3s-prune-links.service k3s-prune-addons.service")
    node.fail(f"test -L {manifests}/takeover.yaml")
    node.fail(f"{kubectl} -n kube-system get addon takeover")
    node.wait_until_fails(configmap, timeout=60)
    node.succeed(binding)
    assert set(node.succeed(addons).split()) == before, (before, node.succeed(addons))
    node.succeed(f"test -f {manifests}/coredns.yaml && test -f {manifests}/metrics-server/metrics-server-deployment.yaml")
    node.succeed(f"{kubectl} -n kube-system rollout status deploy/coredns --timeout=60s")
    node.succeed(f"{kubectl} -n kube-system rollout status deploy/metrics-server --timeout=60s")
    # One left behind by a generation switched to at the boot below
    node.succeed(f"ln -s $(readlink -f /etc/k3s-prune-test/prune-test-boot.yaml) {manifests}/prune-test-boot.yaml")
    node.wait_until_succeeds(f"{kubectl} -n default get configmap prune-test-boot", timeout=120)

with subtest("k3s: the prune of the Addons starts while k3s is stopped, starting k3s rather than failing"):
    # As switch-to-configuration does: k3s stopped, then a start job for each unit on its own, in no fixed order. The
    # prune's start may come first, before any start of k3s is queued
    node.succeed("systemctl stop k3s-prune-addons.service k3s.service")
    node.succeed("systemctl start k3s-prune-addons.service")
    node.succeed("systemctl is-active k3s.service k3s-prune-addons.service")
    node.wait_until_succeeds(f"{kubectl} get --raw /readyz", timeout=300)

with subtest("shutdown: a reboot drains the node first, leaving no Failed pods and no cordon"):
    # Through logind, which sends PrepareForShutdown; the driver's reboot() presses Ctrl+Alt+Del, which doesn't. The
    # driver runs QEMU with -no-reboot, so the reboot ends the VM, and the test starts it again
    node.execute("systemctl reboot >/dev/null 2>&1 &")
    node.wait_for_shutdown()
    node.start()
    node.wait_for_unit("multi-user.target")
    jsonpath = f"{kubectl} get node node -o jsonpath"
    node.wait_until_succeeds(
        f"test \"$({jsonpath}='{{.spec.unschedulable}},{{.metadata.annotations.cluster\\.local/drained-for-shutdown}}')\" = ,",
        timeout=600,
    )
    node.fail(
        f"{kubectl} get pods -A -o jsonpath='{{range .items[*]}}{{.status.reason}}{{\"\\n\"}}{{end}}'"
        " | grep -x 'NodeShutdown\\|Terminated'"
    )
    node.succeed("journalctl -b -1 -u k3s-drain | grep -q 'drained'")

with subtest("k3s: the boot removes a manifest left behind before k3s starts, then its Addon and objects"):
    node.succeed("journalctl -b -u k3s-prune-links | grep -q 'Removed .*/prune-test-boot.yaml'")
    node.succeed(
        "test $(systemctl show -p ExecMainExitTimestampMonotonic --value k3s-prune-links)"
        " -lt $(systemctl show -p ExecMainStartTimestampMonotonic --value k3s)"
    )
    node.fail(f"test -L {manifests}/prune-test-boot.yaml")
    node.wait_until_succeeds("systemctl is-active k3s-prune-addons.service", timeout=600)
    node.fail(f"{kubectl} -n kube-system get addon prune-test-boot")
    node.wait_until_fails(f"{kubectl} -n default get configmap prune-test-boot", timeout=60)

with subtest("k3s: the boot imports no image again, containerd keeps every image k3s skipped"):
    node.succeed("journalctl -b -1 -u k3s | grep -q 'Imported [0-9]* images from'")
    node.fail("journalctl -b -u k3s | grep -q 'Importing images from'")
    cache = json.loads(node.succeed("cat /var/lib/k3s/agent/images/.cache.json"))
    images = json.loads(node.succeed("k3s crictl images -o json"))["images"]
    tags = {tag for image in images for tag in image.get("repoTags") or []}
    missing = {name for entry in cache.values() for name in entry["images"]} - tags
    assert not missing, sorted(missing)

with subtest("setup-secrets: the cluster group stores after k3s, runs again when k3s restarts, skipping the unchanged"):
    def count(line):
        return int(node.succeed(f"journalctl -b -o cat -u setup-secrets@cluster | grep -c '^{line}$' || true").strip())
    password = f"{kubectl} -n default get secret setup-secrets-test -o jsonpath='{{.data.password}}'"
    node.wait_until_succeeds(password, timeout=300)
    value, unchanged = node.succeed(password), count("Test Secret: Unchanged")
    node.succeed("systemctl restart k3s.service")
    # The Secret's resourceVersion is what it was after the store, so the destination is skipped
    # The count runs in the shell, at every try
    node.wait_until_succeeds(
        f"test $(journalctl -b -o cat -u setup-secrets@cluster | grep -c '^Test Secret: Unchanged$') -gt {unchanged}",
        timeout=300,
    )
    node.wait_until_succeeds("systemctl is-active setup-secrets@cluster.service", timeout=300)
    assert node.succeed(password) == value, "the restart replaced the stored value"

with subtest("setup-secrets: a deleted Secret is stored again, restarting the workloads of its destination"):
    node.wait_until_succeeds(f"{kubectl} get --raw /readyz", timeout=300)
    stores = count("Test Secret: Storing")
    # Only the pod template matters, so an image that never pulls will do
    node.succeed(f"{kubectl} -n default create deployment restart-test --image=registry.invalid/none")
    restarted = f"{kubectl} -n default get deployment restart-test -o jsonpath='{{.spec.template.metadata.annotations.kubectl\\.kubernetes\\.io/restartedAt}}'"
    assert node.succeed(restarted) == "", "restarted before the Secret changed"
    node.succeed(f"{kubectl} -n default delete secret setup-secrets-test")
    node.succeed("systemctl restart setup-secrets@cluster.service")
    node.wait_until_succeeds(password, timeout=120)
    assert count("Test Secret: Storing") > stores, node.succeed("journalctl -b -o cat -u setup-secrets@cluster")
    assert node.succeed(restarted) != "", "the store didn't restart the Deployment"
