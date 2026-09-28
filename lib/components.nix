{ lib, mermaid }:
let
  inherit (mermaid)
    kindEnum
    validId
    validColor
    isString
    ;
  strings = lib.strings;

  pathId = path: "b_" + lib.concatStringsSep "_" path;

  # Ancestor references are encoded as "@<up>:<id>" (component ids cannot
  # contain "@" or ":").
  refMatch = builtins.match "@([0-9]+):(.+)";
  isRef = s: lib.isString s && refMatch s != null;
  refDepth = s: builtins.fromJSON (builtins.elemAt (refMatch s) 0);
  refName = s: builtins.elemAt (refMatch s) 1;
  refNodeId = s: "anc_${toString (refDepth s)}_${refName s}";

  # Resolve a reference without throwing, so structural validation can report
  # bad values instead of crashing. Values that cannot be resolved are kept.
  safeResolveId =
    x:
    if lib.isString x then
      x
    else if lib.isAttrs x && x ? id then
      (if (x.up or 0) > 0 then "@${toString x.up}:${x.id}" else x.id)
    else
      x;

  # Resolve a component reference: an id string or a handle (local or ancestor).
  resolveId =
    x:
    if lib.isString x then
      x
    else if lib.isAttrs x && x ? id then
      (if (x.up or 0) > 0 then "@${toString x.up}:${x.id}" else x.id)
    else
      throw "expected a component id (string) or a handle; got ${builtins.typeOf x}";

  # A component's semantic types, from `types` (list), a bare `types` value, or
  # the `type` alias.
  componentTypes =
    node:
    let
      raw = node.types or node.type or [ ];
      list = if lib.isList raw then raw else [ raw ];
    in
    lib.unique (map safeResolveId list);

  # Normalize one raw node into a boundary or leaf node.
  mkNode =
    path: name: node:
    if node ? components then
      {
        type = "boundary";
        inherit name path;
        id = pathId path;
        label = node.label;
        color = node.color or null;
        children = lib.mapAttrsToList (n: c: mkNode (path ++ [ n ]) n c) node.components;
      }
    else
      {
        type = "leaf";
        inherit name path;
        label = node.label;
        kind = node.kind or null;
        color = node.color or null;
        componentTypes = componentTypes node;
        child = node.child or null;
        hasChild = (node.child or null) != null;
        links = node.links or [ ];
        boundaryPath = lib.lists.init path;
        topBoundary = if path == [ ] then null else lib.head path;
      };

  tree = components: lib.mapAttrsToList (n: c: mkNode [ n ] n c) components;

  # Pre-order fold over a normalized tree.
  foldTree =
    f: init: nodes:
    lib.foldl' (
      acc: node: if node.type == "boundary" then foldTree f (f acc node) node.children else f acc node
    ) init nodes;

  emptyAcc = {
    leaves = { };
    leafOrder = [ ];
    boundaries = [ ];
    entries = [ ];
  };
in
rec {
  mkTree = components: tree components;

  flatten =
    components:
    foldTree (
      acc: node:
      if node.type == "boundary" then
        {
          inherit (acc) leaves leafOrder;
          boundaries = acc.boundaries ++ [
            {
              inherit (node)
                name
                path
                label
                color
                id
                ;
            }
          ];
          entries = acc.entries ++ [
            {
              type = "boundary";
              inherit node;
            }
          ];
        }
      else
        {
          leaves = acc.leaves // {
            ${node.name} = node;
          };
          leafOrder = acc.leafOrder ++ [ node.name ];
          inherit (acc) boundaries;
          entries = acc.entries ++ [
            {
              type = "leaf";
              inherit node;
            }
          ];
        }
    ) emptyAcc (tree components);

  leafIds = components: (flatten components).leafOrder;

  # Lookup boundary metadata by slash-joined path ("" for top level unused).
  boundaryByPath =
    components:
    lib.listToAttrs (
      map (b: lib.nameValuePair (lib.concatStringsSep "/" b.path) b) (flatten components).boundaries
    );

  # ---------------------------------------------------------------------------
  # Validation (operates on the raw tree so structural mistakes are caught).
  # ---------------------------------------------------------------------------
  rawErrors =
    path: name: node:
    let
      here = lib.concatStringsSep "." (path ++ [ name ]);
      idErrors = lib.optional (
        node ? id && (!(isString node.id) || node.id != name)
      ) "${here}: `id` `${toString (node.id or null)}` does not match its key `${name}`";
    in
    idErrors
    ++ (
      if node ? components then
        (lib.optional (
          !(node ? label) || !(isString node.label)
        ) "${here}: boundary is missing a string `label`")
        ++ (lib.optional (
          node ? kind
        ) "${here}: boundary must not define `kind` (only leaves are components)")
        ++ (lib.optional (
          node ? types || node ? type
        ) "${here}: boundary must not define `types` (only leaves are components)")
        ++ (lib.optional (
          node ? child
        ) "${here}: boundary must not define `child` (only leaves can own a sub-architecture)")
        ++ (lib.optional (
          node ? color && !(validColor node.color)
        ) "${here}: invalid boundary color `#${toString (node.color or null)}`")
        ++ lib.concatLists (lib.mapAttrsToList (n: c: rawErrors (path ++ [ name ]) n c) node.components)
      else
        (lib.optional (!(isString name) || !(validId name))
          "${here}: invalid component id `${toString name}` (must match [A-Za-z_][A-Za-z0-9_]*, not a reserved word)"
        )
        ++ (lib.optional (
          !(node ? label) || !(isString node.label)
        ) "${here}: component is missing a string `label`")
        ++ (lib.optional (node ? kind && !(lib.elem node.kind kindEnum))
          "${here}: component has invalid `kind` `${toString (node.kind or null)}`; expected one of: ${lib.concatStringsSep ", " kindEnum}`"
        )
        ++ (lib.optional (
          node ? color && !(validColor node.color)
        ) "${here}: invalid component color `${toString (node.color or null)}`")
        ++ (lib.optional (node ? types && node ? type) "${here}: use either `types` or `type`, not both")
        ++ (lib.optional (
          node ? child && !(lib.isPath node.child || isString node.child)
        ) "${here}: `child` must be a path to a child model")
        ++ (
          if node ? types || node ? type then
            let
              raw = node.types or node.type;
              entries = if lib.isList raw then raw else [ raw ];
            in
            lib.concatLists (
              lib.imap0 (
                i: t:
                lib.optional (
                  !(isString t) && !(lib.isAttrs t && t ? id)
                ) "${here}.types[${toString i}]: expected a type id or a type handle"
              ) entries
            )
          else
            [ ]
        )
        ++ lib.concatLists (
          lib.imap0 (
            i: l:
            let
              where = "${here}.links[${toString i}]";
            in
            lib.optional (!(l ? label) || !(isString l.label)) "${where}: missing string `label`"
            ++ lib.optional (!(l ? url) || !(isString l.url)) "${where}: missing string `url`"
          ) (node.links or [ ])
        )
    );

  validate =
    components:
    let
      errs = lib.concatLists (lib.mapAttrsToList (n: c: rawErrors [ ] n c) components);
      names = leafIds components;
      dupes = lib.unique (lib.filter (n: lib.length (lib.filter (m: m == n) names) > 1) names);
    in
    errs ++ lib.optional (dupes != [ ]) "duplicate component ids: ${lib.concatStringsSep ", " dupes}";
}
// {
  inherit
    resolveId
    safeResolveId
    isRef
    refDepth
    refName
    refNodeId
    ;
}
