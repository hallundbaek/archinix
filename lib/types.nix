{
  lib,
  mermaid,
  components,
}:
let
  inherit (mermaid)
    kindEnum
    validColor
    isString
    reservedWords
    ;
  inherit (components) flatten;

  # Type ids may contain hyphens (they are only used as rule names / sequence
  # actor ids, never as flowchart node ids).
  validTypeId =
    name:
    isString name
    && builtins.match "[A-Za-z_][A-Za-z0-9_-]*" name != null
    && !(lib.elem name reservedWords);

  isKnown = types: id: lib.isString id && types ? ${id};

  distinctKinds =
    types: leaf:
    lib.unique (
      lib.filter (k: k != null) (
        map (t: if isKnown types t then types.${t}.kind or null else null) leaf.componentTypes
      )
    );

  distinctColors =
    types: leaf:
    lib.unique (
      lib.filter (c: c != null) (
        map (t: if isKnown types t then types.${t}.color or null else null) leaf.componentTypes
      )
    );

  # Effective visual kind: explicit wins; otherwise the single kind defined by
  # the component's types; otherwise null.
  resolveKind =
    types: leaf:
    if leaf.kind != null then
      leaf.kind
    else
      let
        ks = distinctKinds types leaf;
      in
      if lib.length ks == 1 then lib.head ks else null;

  # Effective colour: explicit wins; otherwise the single colour from the types.
  resolveColor =
    types: leaf:
    if leaf.color != null then
      leaf.color
    else
      let
        cs = distinctColors types leaf;
      in
      if lib.length cs == 1 then lib.head cs else null;
in
rec {
  inherit
    distinctKinds
    distinctColors
    resolveKind
    resolveColor
    ;

  # type id -> component leaf ids that carry that type.
  members =
    comps: types:
    let
      flat = flatten comps;
    in
    lib.listToAttrs (
      map (
        t: lib.nameValuePair t (lib.filter (id: lib.elem t flat.leaves.${id}.componentTypes) flat.leafOrder)
      ) (builtins.attrNames types)
    );

  # Structural validation of the registry itself.
  validateRegistry =
    types:
    lib.concatLists (
      lib.mapAttrsToList (
        name: spec:
        lib.optional (!(validTypeId name))
          "type `${toString name}`: invalid type id (must match [A-Za-z_][A-Za-z0-9_-]*, not a reserved word)"
        ++ lib.optional (!(spec ? label) || !(isString spec.label)) "type `${name}`: missing string `label`"
        ++
          lib.optional (spec ? kind && !(lib.elem spec.kind kindEnum))
            "type `${name}`: invalid `kind` `${toString (spec.kind or null)}`; expected one of: ${lib.concatStringsSep ", " kindEnum}`"
        ++ lib.optional (
          spec ? color && !(validColor spec.color)
        ) "type `${name}`: invalid `color` `${toString (spec.color or null)}`"
        ++ lib.optional (
          spec ? id && (!(isString spec.id) || spec.id != name)
        ) "type `${name}`: `id` `${toString (spec.id or null)}` does not match its key"
      ) types
    );

  # Cross-validation between the registry and the component tree.
  validateUsage =
    { types, comps }:
    let
      flat = flatten comps;
      typeNames = builtins.attrNames types;
      leafNames = flat.leafOrder;

      collisions = lib.filter (n: lib.elem n typeNames) leafNames;

      leafErrors = lib.concatLists (
        lib.mapAttrsToList (
          id: leaf:
          let
            unknown = lib.filter (t: !(isKnown types t)) leaf.componentTypes;
            ks = distinctKinds types leaf;
            cs = distinctColors types leaf;
          in
          map (t: "component `${id}`: unknown type `${toString t}`") unknown
          ++ lib.optional (
            leaf.kind == null && lib.length ks > 1
          ) "component `${id}`: its types define conflicting `kind`s; set an explicit `kind`"
          ++ lib.optional (
            leaf.kind == null && lib.length ks == 0
          ) "component `${id}`: no `kind` given and its types define none"
          ++ lib.optional (
            leaf.color == null && lib.length cs > 1
          ) "component `${id}`: its types define conflicting `color`s; set an explicit `color`"
        ) flat.leaves
      );
    in
    lib.optional (
      collisions != [ ]
    ) "type ids collide with component ids: ${lib.concatStringsSep ", " collisions}"
    ++ leafErrors;
}
