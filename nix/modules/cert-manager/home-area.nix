# The cert-manager module's namespace (it runs wherever it is imported) in the `platform` area of the Home dashboard, whose CPU, memory and traffic graphs
# sum the containers by area. Added only where homelab-monitoring's Grafana options are declared, without importing
# its module: the flakes' modules import each other, and a module that imports it here would recurse
_:
{
  config,
  lib,
  options,
  ...
}:
{
  config = lib.optionalAttrs (options ? homelab && options.homelab ? grafana) {
    homelab.grafana.home.areas.platform = {
      color = "#c4a483";
      namespaces = [ "cert-manager" ];
    };
  };
}
