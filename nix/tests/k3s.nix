# k3s on one node with k3s' bundled network (the homelab cluster runs networking's Cilium instead): the shared modules
# on the checks' fixture, booted under the NixOS test driver. What k3s does on its own, without a CNI module: the
# bundled metrics-server, pruning manifests a deploy or a boot no longer has, draining at shutdown, importing images
# once
{
  self,
  pkgs,
  lib,
}:
pkgs.testers.runNixOSTest {
  name = "k3s";
  nodes.node =
    { lib, ... }:
    {
      imports = lib.attrValues self.nixosModules ++ [ self.lib.checks.fixture ];
      networking.hostName = lib.mkForce "node";
      homelab.k3s = {
        bundledNetworking = true;
        # The fixture's path is where the module links the data directory from
        dataDir = lib.mkForce "/var/lib/k3s";
      };
      # On a real machine the data directory is a filesystem of its own, which exists before k3s starts
      systemd.tmpfiles.rules = [ "d /var/lib/k3s 0700 root root -" ];
      # k3s waits for a default route; the test network has none
      networking.defaultGateway = {
        address = "192.168.1.254";
        interface = "eth1";
      };
      virtualisation = {
        memorySize = 4096;
        cores = 2;
        diskSize = 8192;
      };
      # Manifests the test links in by hand, as a generation that has them would. The name of this one sorts after
      # rolebindings.yaml of k3s (see the test)
      environment.etc."k3s-prune-test/takeover.yaml".text = ''
        apiVersion: v1
        kind: ConfigMap
        metadata: {name: takeover, namespace: default}
        ---
        # One of k3s' own objects (rolebindings.yaml), which a manifest may take over
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata: {name: kube-apiserver-kubelet-admin}
        roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: "system:kubelet-api-admin"}
        subjects: [{apiGroup: rbac.authorization.k8s.io, kind: User, name: kube-apiserver}]
      '';
      environment.etc."k3s-prune-test/prune-test-boot.yaml".text = ''
        apiVersion: v1
        kind: ConfigMap
        metadata: {name: prune-test-boot, namespace: default}
      '';
    };
  testScript = builtins.readFile ./k3s.py;
}
