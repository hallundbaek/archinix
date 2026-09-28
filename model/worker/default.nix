{ archinix, parent }:
with archinix;
let
  c = component.define {
    queue = component.queue "Inbound Queue";
    # A nested sub-architecture (see model/worker/runner/).
    runner = component.sub ./runner "Job Runner";
  };
in
{
  title = "Worker Fleet";
  description = ''
    Sub-architecture of the `fleet` component. It pulls jobs from the platform
    queue and writes results back to the **platform database**, which it reaches
    through `parent`.
  '';

  components = {
    fleet = boundary "Worker Fleet" { inherit (c) queue runner; };
  };

  sequences = {
    process = {
      title = "Process Job";
      participants = [
        c.queue
        c.runner
        parent.db
      ];
      steps = [
        (message.dottedArrow c.queue c.runner "deliver")
        (message.solidArrow c.runner parent.db "write result")
      ];
    };
  };

  architecture = {
    title = "Worker Fleet";
    labelMode = "derived";
  };
}
