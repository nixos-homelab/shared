{ lib }:
let
  inherit (lib) mkOption types;
  # What the types are made of
  handled = [
    "type"
    "description"
    "properties"
    "required"
    "additionalProperties"
    "items"
    "enum"
    "nullable"
    "x-kubernetes-int-or-string"
    "x-kubernetes-preserve-unknown-fields"
    "x-kubernetes-list-type"
    "x-kubernetes-list-map-keys"
  ];
  # What the types leave to the API server: value validations (a structural schema allows only those under anyOf and
  # oneOf), defaults it fills in, and how server-side apply merges maps. Only what the pinned CRDs use, so a new one
  # gets looked at
  ignored = [
    "anyOf"
    "oneOf"
    "default"
    "format"
    "pattern"
    "minLength"
    "maxLength"
    "minimum"
    "maximum"
    "minItems"
    "maxItems"
    "minProperties"
    "maxProperties"
    "x-kubernetes-validations"
    "x-kubernetes-map-type"
  ];
  scalars = {
    string = types.str;
    integer = types.int;
    number = types.number;
    boolean = types.bool;
  };
  # Every construct outside those lists, as `<path>: <construct>`
  unknown =
    path: schema:
    map (k: "${path}: ${k}") (lib.subtractLists (handled ++ ignored) (lib.attrNames schema))
    ++ lib.optional (
      !(
        schema.x-kubernetes-int-or-string or false || schema.x-kubernetes-preserve-unknown-fields or false
      )
      && !lib.elem (schema.type or null) (
        [
          "object"
          "array"
        ]
        ++ lib.attrNames scalars
      )
    ) "${path}: type ${toString (schema.type or "missing")}"
    ++ lib.concatLists (lib.mapAttrsToList (n: unknown "${path}.${n}") (schema.properties or { }))
    ++ lib.optionals (schema ? items) (unknown "${path}[]" schema.items)
    ++ lib.optionals (lib.isAttrs (schema.additionalProperties or null)) (
      unknown "${path}.*" schema.additionalProperties
    );
  typeOf =
    schema:
    let
      type =
        if schema.x-kubernetes-int-or-string or false then
          types.either types.int types.str
        else if schema ? enum then
          types.enum (lib.filter (v: v != null) schema.enum)
        else if schema.type or null == "object" && schema ? properties then
          types.submodule (
            {
              options = optionsOf schema;
            }
            // lib.optionalAttrs (schema.x-kubernetes-preserve-unknown-fields or false) {
              freeformType = types.attrsOf types.anything;
            }
          )
        else if schema.type or null == "object" && lib.isAttrs (schema.additionalProperties or null) then
          types.attrsOf (typeOf schema.additionalProperties)
        else if schema.type or null == "object" then
          types.attrsOf types.anything
        else if schema.type or null == "array" then
          types.listOf (typeOf schema.items)
        else
          scalars.${schema.type or ""} or types.anything;
    in
    if schema.nullable or false then types.nullOr type else type;
  # The key of a list of objects the API server merges by one field, as kubenix keys the lists of its core types
  keyOf =
    schema:
    let
      keys = schema.x-kubernetes-list-map-keys or [ ];
    in
    if
      schema.x-kubernetes-list-type or null == "map"
      && lib.length keys == 1
      && (schema.items.properties or { }) ? ${lib.head keys}
    then
      lib.head keys
    else
      null;
  # Such a list as an attribute set by that key, which takes lists too: their items keep their order, ahead of the
  # rest. Back to a list on the way out
  keyedOf =
    key: items:
    types.coercedTo (types.listOf types.attrs)
      (
        list:
        lib.listToAttrs (
          lib.imap0 (
            i: item:
            lib.nameValuePair (toString
              item.${key} or (throw "crd2types: a list item without its key ${key}")
            ) (item // { _priority = i; })
          ) list
        )
      )
      (
        types.attrsOf (
          types.submodule (
            { name, ... }:
            lib.optionalAttrs (items.x-kubernetes-preserve-unknown-fields or false) {
              freeformType = types.attrsOf types.anything;
            }
            // {
              options = optionsOf items // {
                _priority = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  internal = true;
                };
              };
              config.${key} = lib.mkOverride 1002 (
                if items.properties.${key}.type or null == "integer" then lib.toInt name else name
              );
            }
          )
        )
      );
  toList =
    attrs:
    map (item: removeAttrs item [ "_priority" ]) (
      lib.sort (a: b: a._priority != null && (b._priority == null || a._priority < b._priority)) (
        lib.attrValues attrs
      )
    );
  optionsOf =
    schema:
    lib.mapAttrs (
      name: property:
      let
        key = keyOf property;
        type = if key == null then typeOf property else keyedOf key property.items;
        apply = lib.optionalAttrs (key != null) { apply = lib.mapNullable toList; };
      in
      if lib.elem name (schema.required or [ ]) then
        mkOption (
          {
            description = property.description or "";
            inherit type;
          }
          // apply
        )
      else
        mkOption (
          {
            description = property.description or "";
            type = types.nullOr type;
            default = null;
          }
          // apply
        )
    ) (schema.properties or { });
  # kubenix's attribute names of resource types: the plural, cased like the kind (cSIDrivers)
  attrName =
    plural: kind:
    lib.concatStrings (
      lib.imap0 (
        i: c:
        let
          k = lib.substring i 1 kind;
        in
        if i > 0 && lib.toLower k == c then k else c
      ) (lib.stringToCharacters plural)
    );
in
{
  /**
    The kubenix `kubernetes.customTypes` of a CustomResourceDefinition, one
    per served version, for `kubernetes.customTypesModuleDefinesCRDSpec =
    false`: each module types the fields of the resource besides
    `apiVersion`, `kind` and `metadata`, which kubenix types itself.
    Optional fields default to null, which kubenix leaves out. A list the
    API server merges by one key (`x-kubernetes-list-type: map`) is an
    attribute set by that key, as kubenix has it for its core types; a
    list still works there. Value validations and defaults stay with the
    API server. Throws on any other schema construct, naming where it is, so a
    CRD that starts using one fails evaluation.

    # Arguments

    `crd` (`AttrSet`): the CustomResourceDefinition
  */
  customTypes =
    crd:
    let
      inherit (crd.spec) group names;
      versions = lib.filter (v: v.served) crd.spec.versions;
      errors = lib.concatMap (
        v: unknown "${crd.metadata.name}/${v.name}" v.schema.openAPIV3Schema
      ) versions;
    in
    if errors != [ ] then
      throw "crd2types: schema constructs it doesn't handle:\n${lib.concatLines errors}"
    else
      map (
        v:
        let
          schema = v.schema.openAPIV3Schema;
        in
        {
          inherit group;
          inherit (names) kind;
          version = v.name;
          name = names.plural;
          attrName = attrName names.plural names.kind;
          description = schema.description or "";
          module.options = optionsOf (
            schema
            // {
              properties = removeAttrs (schema.properties or { }) [
                "apiVersion"
                "kind"
                "metadata"
              ];
            }
          );
        }
      ) versions;
}
