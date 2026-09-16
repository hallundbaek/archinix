{
  title = "Acme Platform Architecture";
  description = ''
    Single source of truth for Acme's platform. Every diagram on these pages is
    generated from the `model/` directory in Nix: the architecture overviews are
    derived from the messages exchanged in the sequence diagrams.
  '';

  # Recursive tree: nodes with `components` are boundaries, leaves are components.
  components = {
    internet = {
      label = "Internet";
      components = {
        user = {
          label = "End User";
          kind = "actor";
        };
      };
    };

    edge = {
      label = "Edge / DMZ";
      color = "#2d333b";
      components = {
        web = {
          label = "Web App";
          kind = "boundary";
          links = [
            {
              label = "Dashboard";
              url = "https://grafana.example/web";
            }
          ];
        };
      };
    };

    core = {
      label = "Core Services";
      color = "rgb(45, 55, 72)";
      components = {
        gateway = {
          label = "API Gateway";
          kind = "control";
        };
        auth = {
          label = "Auth Service";
          kind = "participant";
        };
        db = {
          label = "PostgreSQL";
          kind = "database";
          links = [
            {
              label = "Metrics";
              url = "https://grafana.example/db";
            }
          ];
        };
        workers = {
          label = "Worker Pool";
          components = {
            queue = {
              label = "Job Queue";
              kind = "queue";
            };
            worker = {
              label = "Worker";
              kind = "collections";
            };
          };
        };
      };
    };

    # A root-level leaf (not inside any boundary): rendered without a box and
    # outside every architecture subgraph.
    idp = {
      label = "Identity Provider";
      kind = "entity";
    };
  };

  sequences = {
    login-flow = {
      title = "Login Flow";
      diagramTitle = "Login";
      accessibility = {
        title = "Login sequence";
        description = ''
          End user credentials are verified against PostgreSQL.
          Invalid credentials short-circuit with a 401.
        '';
      };
      participants = [
        "user"
        "web"
        "gateway"
        "auth"
        "db"
        "idp"
      ];

      steps = [
        { comment = "Happy path with an invalid-credentials branch"; }
        {
          message = {
            from = "user";
            to = "web";
            label = "enter credentials";
          };
        }
        { activate = "web"; }
        {
          message = {
            from = "web";
            to = "gateway";
            label = "POST /login";
            arrow = "solidArrow";
            activateTarget = true;
          };
        }
        {
          message = {
            from = "gateway";
            to = "auth";
            label = "verify(credentials)";
            arrow = "solidArrow";
          };
        }
        { activate = "auth"; }
        {
          message = {
            from = "auth";
            to = "db";
            label = "SELECT user";
            arrow = "solidArrow";
          };
        }
        {
          note = {
            position = "over";
            actors = [ "auth" ];
            text = "constant-time\nhash compare";
          };
        }
        {
          message = {
            from = "auth";
            to = "idp";
            label = "OIDC userinfo";
            arrow = "solidArrow";
          };
        }
        {
          message = {
            from = "idp";
            to = "auth";
            label = "profile";
            arrow = "dottedArrow";
          };
        }
        {
          alt = {
            branches = [
              {
                label = "valid";
                steps = [
                  {
                    message = {
                      from = "auth";
                      to = "gateway";
                      label = "OK";
                      arrow = "dottedArrow";
                    };
                  }
                  {
                    message = {
                      from = "gateway";
                      to = "web";
                      label = "200";
                      arrow = "dottedArrow";
                    };
                  }
                ];
              }
              {
                label = "invalid";
                steps = [
                  {
                    message = {
                      from = "auth";
                      to = "gateway";
                      label = "401";
                      arrow = "solidCross";
                    };
                  }
                  {
                    message = {
                      from = "gateway";
                      to = "web";
                      label = "401";
                      arrow = "solidCross";
                    };
                  }
                ];
              }
              {
                label = "identity provider timeout";
                steps = [
                  {
                    message = {
                      from = "idp";
                      to = "auth";
                      label = "timeout";
                      arrow = "dottedCross";
                    };
                  }
                  {
                    message = {
                      from = "auth";
                      to = "gateway";
                      label = "503";
                      arrow = "dottedCross";
                    };
                  }
                ];
              }
            ];
          };
        }
        { deactivate = "auth"; }
        {
          note = {
            position = "over";
            actors = [
              "user"
              "web"
            ];
            text = "session established";
          };
        }
        {
          rect = {
            color = "rgba(0, 128, 255, 0.1)";
            steps = [
              {
                message = {
                  from = "web";
                  to = "user";
                  label = "show dashboard";
                  arrow = "dottedArrow";
                };
              }
            ];
          };
        }
        {
          message = {
            from = "web";
            to = "gateway";
            label = "close";
            arrow = "solidOpen";
            deactivateSource = true;
          };
        }
        {
          properties = {
            actor = "auth";
            text = "owner: identity-team";
          };
        }
        {
          details = {
            actor = "gateway";
            text = "tier: edge";
          };
        }
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
      participants = [
        "user"
        "web"
        "gateway"
        "auth"
        "db"
      ];

      steps = [
        {
          message = {
            from = "user";
            to = "web";
            label = "reload";
            arrow = "solidArrow";
          };
        }
        {
          loop = {
            label = "until fresh";
            steps = [
              {
                message = {
                  from = "web";
                  to = "gateway";
                  label = "GET /resource";
                  arrow = "dottedArrow";
                };
              }
              {
                opt = {
                  label = "expired";
                  steps = [
                    {
                      message = {
                        from = "gateway";
                        to = "auth";
                        label = "refresh";
                        arrow = "solidArrow";
                      };
                    }
                    {
                      message = {
                        from = "auth";
                        to = "db";
                        label = "rotate token";
                        arrow = "solidArrow";
                      };
                    }
                  ];
                };
              }
            ];
          };
        }
        {
          message = {
            from = "auth";
            to = "gateway";
            label = "new token";
            arrow = "dottedArrow";
          };
        }
        {
          par = {
            branches = [
              {
                label = "audit";
                steps = [
                  {
                    message = {
                      from = "gateway";
                      to = "db";
                      label = "write audit";
                      arrow = "solidArrow";
                    };
                  }
                ];
              }
              {
                label = "notify";
                steps = [
                  {
                    message = {
                      from = "gateway";
                      to = "web";
                      label = "refresh done";
                      arrow = "dottedArrow";
                    };
                  }
                ];
              }
            ];
          };
        }
        {
          parOver = {
            branches = [
              {
                label = "a";
                steps = [
                  {
                    message = {
                      from = "web";
                      to = "gateway";
                      label = "ping";
                      arrow = "solidArrow";
                    };
                  }
                ];
              }
              {
                label = "b";
                steps = [
                  {
                    message = {
                      from = "gateway";
                      to = "web";
                      label = "pong";
                      arrow = "dottedArrow";
                    };
                  }
                ];
              }
            ];
          };
        }
        {
          critical = {
            label = "commit rotation";
            branches = [
              {
                label = "ok";
                steps = [
                  {
                    message = {
                      from = "auth";
                      to = "db";
                      label = "COMMIT";
                      arrow = "solidArrow";
                    };
                  }
                ];
              }
              {
                label = "conflict";
                steps = [
                  {
                    message = {
                      from = "db";
                      to = "auth";
                      label = "ROLLBACK";
                      arrow = "solidCross";
                    };
                  }
                ];
              }
            ];
          };
        }
        {
          break = {
            label = "database unavailable";
            steps = [
              {
                message = {
                  from = "db";
                  to = "gateway";
                  label = "error";
                  arrow = "solidCross";
                };
              }
            ];
          };
        }
        {
          message = {
            from = "gateway";
            to = "db";
            label = "sync";
            arrow = "solidTopHalf";
          };
        }
        {
          message = {
            from = "db";
            to = "gateway";
            label = "ack";
            arrow = "revSolidBottomHalf";
          };
        }
        {
          message = {
            from = "auth";
            to = "gateway";
            label = "bidir";
            arrow = "bidirSolid";
          };
        }
        {
          message = {
            from = "web";
            to = "gateway";
            label = "keepalive";
            arrow = "dottedPoint";
          };
        }
        {
          message = {
            from = "auth";
            to = "gateway";
            label = "session sync";
            arrow = "bidirDotted";
          };
        }
      ];
    };

    job-processing = {
      title = "Job Processing";
      participants = [
        "gateway"
        "queue"
        "db"
      ];

      steps = [
        {
          message = {
            from = "gateway";
            to = "queue";
            label = "enqueue(job)";
            arrow = "solidArrow";
          };
        }
        { create = "worker"; }
        {
          message = {
            from = "queue";
            to = "worker";
            label = "deliver";
            arrow = "solidPoint";
          };
        }
        {
          note = {
            position = "right";
            actors = [ "worker" ];
            text = "spin up";
          };
        }
        {
          message = {
            from = "worker";
            to = "db";
            label = "write result";
            arrow = "solidArrow";
          };
        }
        {
          message = {
            from = "worker";
            to = "gateway";
            label = "status";
            arrow = "solidArrow";
            central = "target";
          };
        }
        {
          message = {
            from = "db";
            to = "queue";
            label = "poll";
            arrow = "dottedArrow";
            central = "source";
          };
        }
        {
          message = {
            from = "gateway";
            to = "db";
            label = "trace";
            arrow = "dottedArrow";
            central = "both";
          };
        }
        {
          note = {
            position = "left";
            actors = [ "gateway" ];
            text = "circuit breaker";
          };
        }
        { activate = "db"; }
        {
          message = {
            from = "db";
            to = "worker";
            label = "ack";
            arrow = "solidArrow";
            deactivateSource = true;
          };
        }
        {
          message = {
            from = "queue";
            to = "gateway";
            label = "drained";
            arrow = "dottedArrow";
          };
        }
        { destroy = "worker"; }
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
    ];
    edgeLabels = {
      "web->gateway" = "HTTPS";
      "gateway->auth" = "gRPC";
      "auth->db" = "SQL";
      "auth->idp" = "OIDC";
      "gateway->queue" = "AMQP";
      "worker->db" = "SQL";
    };
    config = {
      look = "neo";
    };
  };
}
