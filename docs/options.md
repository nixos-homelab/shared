## homelab\.cert-manager\.acme-production-issuer\.webhook-config

LibDNS webhook configuration for the ACME production issuer



*Type:*
submodule

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.acme-production-issuer\.webhook-config\.provider



Name of the DNS provider



*Type:*
string

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.acme-production-issuer\.webhook-config\.secretName



Name of the DNS provider credentials secret in the cert-manager namespace



*Type:*
string

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.acme-staging-issuer\.webhook-config



LibDNS webhook configuration for the ACME staging issuer



*Type:*
submodule

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.acme-staging-issuer\.webhook-config\.provider



Name of the DNS provider



*Type:*
string

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.acme-staging-issuer\.webhook-config\.secretName



Name of the DNS provider credentials secret in the cert-manager namespace



*Type:*
string

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cert-manager\.debug



Whether to enable debug mode\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/cert-manager/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cert-manager/default.nix)



## homelab\.cluster\.enable



Whether to enable the homelab cluster\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.enableIPv4



IPv4 support



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.enableIPv6



Whether to enable IPv6 support\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.acmeProvider



The ACME provider that Ingresses should use for obtaining TLS certs



*Type:*
string

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.backup\.hostPaths



List of paths on the host that *should* be backed up, this option does not configure a backup, it is only meant for aggregation



*Type:*
list of string



*Default:*
` [ ] `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.backup\.volumes



A map of namespace -> PV claim name -> paths that *should* be backed up, this option does not configure a backup, it is only meant for aggregation



*Type:*
attribute set of attribute set of list of string



*Default:*
` { } `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.dataDir



Location of the k3s data directory



*Type:*
string

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.debugTools



Tools to embed in container images when debugging is enabled



*Type:*
list of package



*Default:*
` "bash, coreutils, netcat, curl, jq, dig, ping, ip, tcpdump" `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.domain



Domain name of the cluster



*Type:*
string

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.podCidr4



IPv4 CIDR for the pods



*Type:*
string



*Default:*
` "10.42.0.0/16" `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.podCidr6



IPv6 CIDR for the pods



*Type:*
string

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.svcCidr4



IPv4 CIDR for the services



*Type:*
string



*Default:*
` "10.43.0.0/16" `

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.cluster\.svcCidr6



IPv6 CIDR for the services



*Type:*
string

*Declared by:*
 - [nix/modules/cluster/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/cluster/default.nix)



## homelab\.homepage\.enable



Whether to enable homepage\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.allowEgress



Which services homepage should be allowed access to



*Type:*
list of string

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.debug



Whether to enable debug mode\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.envByName



Additional environment options to add to the homepage container



*Type:*
attribute set of anything



*Default:*
` { } `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.envFrom



Additional environment options to add to the homepage container



*Type:*
list of attribute set of anything



*Default:*
` { } `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.services



Services to add to homepage



*Type:*
attribute set of attribute set of (signed integer or attribute set of anything)



*Default:*
` { } `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.homepage\.widgets



Widgets to add to homepage



*Type:*
attribute set of anything



*Default:*
` { } `

*Declared by:*
 - [nix/modules/homepage/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/homepage/default.nix)



## homelab\.k8sss\.enable



Whether to enable k8sss\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/k8sss/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/k8sss/default.nix)



## homelab\.nfs-provisioner\.enable



Whether to enable the NFS volume provisioner\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.backupPaths



List of paths that should be backed up according to ` config.homelab.cluster.backup.volumes `\.
The paths are constructed using ` cfg.path ` and ` cfg.pathPattern `\.
Only ` .PVC.namespace ` and ` .PVC.name ` placeholders are replaced in the pattern\.



*Type:*
list of absolute path



*Default:*
` "" `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.mountpointOwnership\.gid



GID ownership of the mountpoint



*Type:*
signed integer



*Default:*
` 0 `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.mountpointOwnership\.mode



Filesystem mode to create the mountpoint with



*Type:*
string



*Default:*
` "777" `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.mountpointOwnership\.uid



UID ownership of the mountpoint



*Type:*
signed integer



*Default:*
` 0 `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.path



Export on the NFS server to use as the root



*Type:*
string

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.pathPattern



Naming scheme for volumes on the NFS server



*Type:*
string



*Default:*
` "\${.PVC.namespace}-\${.PVC.name}" `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.nfs-provisioner\.server



NFS server to use as persistent data store



*Type:*
string



*Default:*
` "\${config.networking.hostName}.\${config.homelab.cluster.domain}" `

*Declared by:*
 - [nix/modules/nfs-provisioner/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/nfs-provisioner/default.nix)



## homelab\.postgresql\.enable



Whether to enable PostgreSQL\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases



Databases to create and backup, indexed by serviceName



*Type:*
attribute set of (submodule)

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.backup\.enable



Whether to enable backup of the database\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.backup\.schedule



Cronjob notation of when the database should be dumped



*Type:*
null or string



*Default:*
` "10 3 * * *" `



*Example:*
` "10 3 * * *" `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.dbName



Name of the database



*Type:*
null or string



*Default:*
`` "`<serviceName>`" ``

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.password



Password for the user



*Type:*
null or string



*Default:*
`` "`username`" ``

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.setupCommands



Commands to run as a superuser in the database right after it has been created



*Type:*
list of string



*Default:*
` [ ] `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.databases\.\<name>\.username



Database username



*Type:*
null or string



*Default:*
`` "`<dbName>`" ``

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.debug



Whether to enable debug mode\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.dumpsVolume



Volume source (as specificed on the pod spec) to place database dumps in



*Type:*
attribute set of anything

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.extraSettings



Additional postgresql\.conf settings



*Type:*
strings concatenated with “\\n”



*Default:*
` [ ] `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.image\.package



The postgresql_18 package to use\.



*Type:*
package



*Default:*
` pkgs.postgresql_18 `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.image\.entrypoint



The docker-entrypoint to install



*Type:*
package



*Default:*
` "The entrypoint from the official image" `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.postgresql\.image\.extensions



List of postgresql extensions to include in the image



*Type:*
list of string



*Default:*
` [ ] `

*Declared by:*
 - [nix/modules/postgresql/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/postgresql/default.nix)



## homelab\.redis\.enable



Whether to enable Redis\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/redis/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/redis/default.nix)



## homelab\.redis\.databases



A map of symbolic names to redis db indices\. Overlaps will cause an assertion failure\.



*Type:*
attribute set of string

*Declared by:*
 - [nix/modules/redis/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/redis/default.nix)



## kubetree\.workloadMacros\.enable



Whether to enable service macro transformers\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.acmeProvider



The ACME provider that Ingresses should use for obtaining TLS certs



*Type:*
string

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.containerUtils



Image ref for container-utils



*Type:*
string



*Default:*
` homelab-shared.packages.container-utils `

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.domain



Domain name to suffix hostnames with



*Type:*
string



*Default:*
` config.networking.domain `

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.gatewayClassName



Name of the Gateway class that should set on all gateways generated through the “GatewayMacro” macro



*Type:*
string

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.securityContext\.runAsGroup



GID for pods to run with, also sets securityContext\.fsGroup



*Type:*
signed integer



*Default:*
` 1000 `

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.securityContext\.runAsUser



UID for pods to run as



*Type:*
signed integer



*Default:*
` 1000 `

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)



## kubetree\.workloadMacros\.securityContext\.supplementalGroups



Additional GIDs to apply to the pods



*Type:*
list of signed integer



*Default:*

```
[
  100
]
```

*Declared by:*
 - [nix/modules/workload-macros/default\.nix](https://github.com/nixos-homelab/shared/blob/main/nix/modules/workload-macros/default.nix)


