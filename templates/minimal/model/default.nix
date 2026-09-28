{ archinix }:
with archinix;
let
  c = component.define {
    user = component.actor "User";
    app = component.participant "App";
  };
in
{
  title = "My Architecture";
  description = ''
    A minimal Archinix model. Edit this file, then run `nix run .#render`.
  '';

  components = {
    users = boundary "Users" { inherit (c) user; };
    system = boundary "System" { inherit (c) app; };
  };

  sequences = {
    basic = {
      title = "Basic Flow";
      steps = [
        (message.solidArrow c.user c.app "request")
        (message.dottedArrow c.app c.user "response")
      ];
    };
  };

  architecture = {
    title = "My Architecture";
    labelMode = "derived";
  };
}
