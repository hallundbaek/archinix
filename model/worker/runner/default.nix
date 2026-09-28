{ archinix, parent }:
with archinix;
let
  c = component.define {
    proc = component.participant "Process";
  };
in
{
  title = "Job Runner";
  description = ''
    Sub-architecture of the `runner` component. It reads the next job directly
    from the platform database (two levels up, via `parent.parent`).
  '';

  components = {
    runner = boundary "Runner" { inherit (c) proc; };
  };

  sequences = {
    tick = {
      title = "Runner Tick";
      participants = [
        c.proc
        parent.parent.db
      ];
      steps = [
        (message.dottedArrow c.proc parent.parent.db "SELECT next")
        (message.solidArrow parent.parent.db c.proc "row")
      ];
    };
  };

  architecture = {
    title = "Job Runner";
    labelMode = "derived";
  };
}
