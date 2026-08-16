# setup-secrets 


## `lib.setup-secrets.mkScript` 

Build an executable shell script from `script`, with `getKubeSecret`
and `setKubeSecret` helper functions available to it, and `kubectl`
already pointed at the cluster via `KUBECONFIG`.

`getKubeSecret <namespace> <name> <field>` prints the base64-decoded
value of a field in a Kubernetes secret. `setKubeSecret <namespace>
<name> <field> <value> [<field> <value> ...]` creates or updates a
secret with the given field/value pairs.

### Arguments

`pkgs`: nixpkgs

`script` (`String`): Shell script appended after the helpers are
defined

### Example

```nix
setup-secrets = {
  sources.UNIFI_PASSWORD = {
    description = "Unifi password";
    cmd = setup-secrets.mkScript pkgs "getKubeSecret unifi unifi-credentials password";
  };
  destinations = [
    {
      logPrefix = "Unifi credentials";
      requires = [ "UNIFI_PASSWORD" ];
      cmd = setup-secrets.mkScript pkgs ''
        setKubeSecret unifi unifi-credentials password "''${UNIFI_PASSWORD:?}"
      '';
    }
  ];
};
```


