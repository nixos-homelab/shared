{ lib, ... }:
{
  sectionOption = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "this section";
      sort = lib.mkOption {
        description = "Sorting key of the section";
        type = lib.types.int;
        default = 100;
      };
      layout = {
        header = lib.mkOption {
          description = "Whether to enable the header text";
          type = lib.types.bool;
          default = true;
        };
        iconsOnly = lib.mkEnableOption "icons only";
        style = lib.mkOption {
          description = "The layout style";
          type = lib.types.enum [
            "row"
            "columns"
          ];
          default = "columns";
        };
        columns = lib.mkOption {
          description = "The number of columns per row";
          type = lib.types.int;
          default = 3;
        };
        rows = lib.mkOption {
          description = "The number of rows per column";
          type = lib.types.int;
          default = 3;
        };
        additionalSettings = lib.mkOption {
          description = "Additional keys to merge into the layout";
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      };
    };
  };
}
