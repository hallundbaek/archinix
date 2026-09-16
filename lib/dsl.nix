{
  lib,
  mermaid,
  components,
}:
let
  inherit (mermaid) arrowTokens kindEnum;
  inherit (components) resolveId;
  inherit (builtins) isAttrs;

  # message.<arrow> from to label
  # message.<arrow> from to { label; central; activateTarget; deactivateSource; ... }
  mkMessage =
    arrow: from: to: arg:
    let
      spec = if isAttrs arg then arg else { label = arg; };
    in
    {
      message = {
        from = resolveId from;
        to = resolveId to;
        arrow = arrow;
      }
      // spec;
    };

  # message.make { from; to; label ? ""; arrow ? "solidArrow"; ...extra }
  mkMessageMake =
    {
      from,
      to,
      label ? "",
      arrow ? "solidArrow",
      ...
    }@args:
    {
      message =
        (builtins.removeAttrs args [
          "from"
          "to"
          "label"
          "arrow"
        ])
        // {
          from = resolveId from;
          to = resolveId to;
          inherit label arrow;
        };
    };

  # component.<kind> label
  # component.<kind> { label; links; ... }
  mkLeaf =
    kind: arg:
    let
      spec = if isAttrs arg then arg else { label = arg; };
    in
    { inherit kind; } // spec;

  # boundary label children
  # boundary { label; color; } children
  mkBoundary =
    arg: children:
    let
      spec = if isAttrs arg then arg else { label = arg; };
      withoutNullColor =
        if (spec.color or null) == null then builtins.removeAttrs spec [ "color" ] else spec;
    in
    withoutNullColor // { components = children; };
in
{
  message = lib.mapAttrs (name: _: mkMessage name) arrowTokens // {
    make = mkMessageMake;
  };

  # Component tree helpers. `component.<kind>` builds a leaf, `boundary` builds a
  # boundary node containing `children`, and `link` builds an actor-menu entry.
  component = lib.mapAttrs (kind: _: mkLeaf kind) (lib.genAttrs kindEnum (_: null)) // {
    make =
      {
        kind,
        label ? "",
        ...
      }@args:
      {
        inherit kind label;
      }
      // builtins.removeAttrs args [
        "kind"
        "label"
      ];
    # `component.define { user = component.actor "End User"; ... }` attaches the
    # attribute name as `id`, producing handles usable wherever an id is accepted.
    define = attrs: lib.mapAttrs (name: node: node // { id = name; }) attrs;
  };

  boundary = mkBoundary;
  link = label: url: { inherit label url; };

  note = {
    make = args: {
      note = args // lib.optionalAttrs (args ? actors) { actors = map resolveId args.actors; };
    };
    over = actor: text: {
      note = {
        position = "over";
        actors = [ (resolveId actor) ];
        inherit text;
      };
    };
    overTwo = a: b: text: {
      note = {
        position = "over";
        actors = [
          (resolveId a)
          (resolveId b)
        ];
        inherit text;
      };
    };
    leftOf = actor: text: {
      note = {
        position = "left";
        actors = [ (resolveId actor) ];
        inherit text;
      };
    };
    rightOf = actor: text: {
      note = {
        position = "right";
        actors = [ (resolveId actor) ];
        inherit text;
      };
    };
  };

  comment = text: { comment = text; };
  activate = id: { activate = resolveId id; };
  deactivate = id: { deactivate = resolveId id; };
  create = id: { create = resolveId id; };
  destroy = id: { destroy = resolveId id; };

  loop = label: steps: { loop = { inherit label steps; }; };
  opt = label: steps: { opt = { inherit label steps; }; };
  # Named `breakBlock` because `break` is a builtin that `with` cannot shadow.
  breakBlock = label: steps: { break = { inherit label steps; }; };
  rect = color: steps: { rect = { inherit color steps; }; };

  # A labelled branch used by alt/par/parOver/critical. For alt/par/critical the
  # first branch's label is the block header (the `else`/`and`/`option` keywords
  # are generated for the rest).
  branch = label: steps: { inherit label steps; };

  alt = branches: { alt = { inherit branches; }; };
  par = branches: { par = { inherit branches; }; };
  parOver = branches: { parOver = { inherit branches; }; };
  critical = branches: { critical = { inherit branches; }; };

  properties = args: {
    properties = args // {
      actor = resolveId args.actor;
    };
  };
  details = args: {
    details = args // {
      actor = resolveId args.actor;
    };
  };
}
