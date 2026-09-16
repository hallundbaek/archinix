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
        inherit (node) label kind;
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

  # Resolve a component reference: either a plain id string or a handle created
  # by `component.define` (an attrset carrying `id`).
  resolveId =
    x:
    if lib.isString x then
      x
    else if lib.isAttrs x && x ? id then
      x.id
    else
      throw "expected a component id (string) or a handle from component.define; got ${builtins.typeOf x}";
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
        ++ (lib.optional (!(node ? kind) || !(lib.elem node.kind kindEnum))
          "${here}: component has invalid `kind` `${toString (node.kind or null)}`; expected one of: ${lib.concatStringsSep ", " kindEnum}`"
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
  inherit resolveId;
}
