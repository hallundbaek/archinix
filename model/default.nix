{ archinix }:
with archinix;
let
  # Semantic types. `label` is required; `kind` and `color` are optional.
  ty = types.define {
    deployed-service = {
      label = "Deployed Service";
      color = "#3182ce";
    };
    queue-consumer = {
      label = "Queue Consumer";
      kind = "queue";
      color = "#38a169";
    };
    database = {
      label = "Database";
      kind = "database";
      color = "#805ad5";
    };
  };

  # `component.define` turns the attribute names into component ids and returns
  # handles: use `c.user` wherever a component is referenced.
  c = component.define {
    user = component.actor "End User";
    web = component.boundary "Web App";
    gateway = component.control [ ty.deployed-service ] "API Gateway";
    auth = component.participant [ ty.deployed-service ] "Auth Service" // {
      # Actor-menu links render for participant/database/collections/queue,
      # but Mermaid crashes on actor/boundary/control/entity (see README).
      links = [ (link "Runbook" "https://wiki.example/auth") ];
    };
    orders = component.participant [ ty.deployed-service ] "Orders API";
    db = component.database [ ty.database ] "PostgreSQL" // {
      links = [ (link "Metrics" "https://grafana.example/db") ];
    };
    queue = component.of [ ty.queue-consumer ] "Job Queue";
    worker =
      component.collections
        [
          ty.deployed-service
          ty.queue-consumer
        ]
        {
          label = "Worker";
          # The two types imply different colours; an explicit colour silences it.
          color = "#38a169";
        };
    idp = component.entity "Identity Provider";
  };
in
{
  title = "Acme Platform Architecture";
  description = ''
    Single source of truth for Acme's platform. Every diagram on these pages is
    generated from the `model/` directory in Nix: the architecture overviews are
    derived from the messages exchanged in the sequence diagrams.
  '';

  # Recursive tree: `boundary` nodes contain `components`; leaves are
  # `component.<kind>` nodes. Ids are the attribute names.
  components = {
    internet = boundary "Internet" { inherit (c) user; };

    edge = boundary {
      label = "Edge / DMZ";
      color = "#2d333b";
    } { inherit (c) web; };

    core =
      boundary
        {
          label = "Core Services";
          color = "rgb(45, 55, 72)";
        }
        {
          inherit (c)
            gateway
            auth
            orders
            db
            ;
          workers = boundary "Worker Pool" { inherit (c) queue worker; };
        };

    # A root-level leaf (not inside any boundary): rendered without a box and
    # outside every architecture subgraph.
    inherit (c) idp;
  };

  # The semantic type registry (consumed by validation and rendering).
  types = ty;

  sequences = {
    login-flow = {
      title = "Login Flow";
      diagramTitle = "Login";
      description = ''
        End-user credentials are verified against PostgreSQL, with an optional
        OIDC lookup at the identity provider.

        - Invalid credentials return **401**.
        - An unreachable identity provider returns **503**.
      '';
      steps = [
        (comment "Happy path with an invalid-credentials branch")
        (message.solidArrow c.user c.web "enter credentials")
        (activate c.web)
        (message.solidArrow c.web c.gateway {
          label = "POST /login";
          activateTarget = true;
        })
        (message.solidArrow c.gateway c.auth "verify(credentials)")
        (activate c.auth)
        (message.solidArrow c.auth c.db "SELECT user")
        (note.over c.auth "constant-time\nhash compare")
        (message.solidArrow c.auth c.idp "OIDC userinfo")
        (message.dottedArrow c.idp c.auth "profile")
        (alt [
          (branch "valid" [
            (message.dottedArrow c.auth c.gateway "OK")
            (message.dottedArrow c.gateway c.web "200")
          ])
          (branch "invalid" [
            (message.solidCross c.auth c.gateway "401")
            (message.solidCross c.gateway c.web "401")
          ])
          (branch "identity provider timeout" [
            (message.dottedCross c.idp c.auth "timeout")
            (message.dottedCross c.auth c.gateway "503")
          ])
        ])
        (deactivate c.auth)
        (note.overTwo c.user c.web "session established")
        (rect "rgba(0, 128, 255, 0.1)" [
          (message.dottedArrow c.web c.user "show dashboard")
        ])
        (message.solidOpen c.web c.gateway {
          label = "close";
          deactivateSource = true;
        })
        (properties {
          actor = c.auth;
          text = "owner: identity-team";
        })
        (details {
          actor = c.gateway;
          text = "tier: edge";
        })
      ];
    };

    token-refresh = {
      title = "Token Refresh";
      autonumber = {
        start = 10;
        increment = 5;
      };
      config = {
        theme = "redux-color";
        look = "neo";
        sequence = {
          mirrorActors = true;
        };
      };
      steps = [
        (message.solidArrow c.user c.web "reload")
        (loop "until fresh" [
          (message.dottedArrow c.web c.gateway "GET /resource")
          (opt "expired" [
            (message.solidArrow c.gateway c.auth "refresh")
            (message.solidArrow c.auth c.db "rotate token")
          ])
        ])
        (message.dottedArrow c.auth c.gateway "new token")
        (par [
          (branch "audit" [ (message.solidArrow c.gateway c.db "write audit") ])
          (branch "notify" [ (message.dottedArrow c.gateway c.web "refresh done") ])
        ])
        (parOver [
          (branch "a" [ (message.solidArrow c.web c.gateway "ping") ])
          (branch "b" [ (message.dottedArrow c.gateway c.web "pong") ])
        ])
        (critical [
          # First branch label is the critical section header.
          (branch "commit rotation" [ (message.solidArrow c.auth c.db "COMMIT") ])
          (branch "conflict" [ (message.solidCross c.db c.auth "ROLLBACK") ])
        ])
        (breakBlock "database unavailable" [
          (message.solidCross c.db c.gateway "error")
        ])
        (message.solidTopHalf c.gateway c.db "sync")
        (message.revSolidBottomHalf c.db c.gateway "ack")
        (message.bidirSolid c.auth c.gateway "bidir")
        (message.dottedPoint c.web c.gateway "keepalive")
        (message.bidirDotted c.auth c.gateway "session sync")
      ];
    };

    job-processing = {
      title = "Job Processing";
      steps = [
        (message.solidArrow c.gateway c.queue "enqueue(job)")
        (create c.worker)
        (message.solidPoint c.queue c.worker "deliver")
        (note.rightOf c.worker "spin up")
        (message.solidArrow c.worker c.db "write result")
        (message.solidArrow c.worker c.gateway {
          label = "status";
          central = "target";
        })
        (message.dottedArrow c.db c.queue {
          label = "poll";
          central = "source";
        })
        (message.dottedArrow c.gateway c.db {
          label = "trace";
          central = "both";
        })
        (note.leftOf c.gateway "circuit breaker")
        (activate c.db)
        (message.solidArrow c.db c.worker {
          label = "ack";
          deactivateSource = true;
        })
        (message.dottedArrow c.queue c.gateway "drained")
        (destroy c.worker)
      ];
    };

    # A type-level interaction template: actors are types, not components. The
    # architecture expands each type endpoint to every component of that type.
    service-calls-db = {
      title = "Service → Database";
      description = ''
        Every deployed service queries the database.

        This sequence is written once against the types; the architecture shows
        the resulting **orders → db**, **auth → db** and **gateway → db** edges
        without a sequence per service.
      '';
      participants = [
        ty.deployed-service
        ty.database
      ];
      steps = [
        (message.solidArrow ty.deployed-service ty.database "query")
      ];
    };
  };

  architecture = {
    title = "Acme Platform";
    direction = "TD";
    labelMode = "explicit";
    sequenceOrder = [
      "login-flow"
      "token-refresh"
      "job-processing"
      "service-calls-db"
    ];
    edgeLabels = {
      "web->gateway" = "HTTPS";
      "gateway->auth" = "gRPC";
      "auth->db" = "SQL";
      "auth->idp" = "OIDC";
      "gateway->queue" = "AMQP";
      "worker->db" = "SQL";
      "deployed-service->database" = "SQL";
    };
    config = {
      look = "neo";
    };
  };
}
