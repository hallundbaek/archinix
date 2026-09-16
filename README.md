# architecture

Architecture as code. Define your system **once** in Nix — a component tree and
Mermaid sequence diagrams — and generate a set of interlinked Markdown pages
with embedded Mermaid diagrams.

The key idea: **the sequence diagrams are the source of truth**. The architecture
flowcharts are *derived* from the messages exchanged in the sequences, so a
change to a flow automatically propagates to every architecture view. No more
hand-maintaining parallel diagrams.

- Architecture diagrams → Mermaid `flowchart`
- Sequence diagrams → native Mermaid `sequenceDiagram`
- Output → Markdown files with fenced Mermaid blocks and relative cross-links

## Quick start

Instantiate the project (library + example model + generated docs) and render it:

```console
$ nix flake init -t github:OWNER/architecture
$ nix run .#render          # writes ./docs
$ ls docs
architecture.md  login-flow.md  login-flow-architecture.md  README.md  ...
```

If you already cloned this repository, initialise from the local path instead:

```console
$ nix flake init -t .
```

The generated pages are meant to be committed to your repository; GitHub, GitLab
and Forgejo render the fenced `mermaid` blocks natively.

Then edit `model/default.nix` to describe your own system and re-run
`nix run .#render`.

## Project layout

```
.
├── flake.nix              # apps, packages and checks
├── lib/                   # the renderer library (pure nixpkgs.lib)
│   ├── mermaid.nix        # low-level Mermaid primitives
│   ├── components.nix     # component tree + validation
│   ├── sequence.nix       # sequence diagrams
│   ├── architecture.nix   # derives architecture from sequences
│   ├── markdown.nix       # page assembly and cross-links
│   └── default.nix        # public API
├── model/default.nix      # YOUR architecture lives here
└── docs/                  # generated, committed
```

## Commands

| Command | Description |
| --- | --- |
| `nix run .#render` | Regenerate `./docs` from `model/`. |
| `nix run .#render -- docs --check` | Fail if `./docs` is out of date (for CI). |
| `nix build .#docs` | Build the generated Markdown as a derivation. |
| `nix run .#check-mermaid` | Render every diagram with `mermaid-cli` to catch invalid output. |
| `nix flake check` | Runs the `docs-up-to-date` check (pure Nix, no browser). |
| `nix develop` | Dev shell with `nixfmt`, `nixd`, `mermaid-cli`. |

## Defining components

`components` is a recursive tree. A node with a `components` attribute is a
**boundary**; a node without one is a **component leaf**. Leaves are what
sequences reference.

```nix
components = {
  internet = {
    label = "Internet";
    components = {
      user = { label = "End User"; kind = "actor"; };
    };
  };

  edge = {
    label = "Edge / DMZ";
    color = "#2d333b";
    components = {
      web = { label = "Web App"; kind = "boundary"; };
    };
  };

  core = {
    label = "Core Services";
    color = "rgb(45, 55, 72)";
    components = {
      gateway = { label = "API Gateway"; kind = "control"; };
      db = {
        label = "PostgreSQL";
        kind = "database";
        links = [ { label = "Metrics"; url = "https://grafana.example/db"; } ];
      };
      workers = {
        label = "Worker Pool";
        components = {
          queue = { label = "Job Queue"; kind = "queue"; };
        };
      };
    };
  };
};
```

Boundaries nest arbitrarily and render as nested `subgraph`s (architecture) and
as `box` groups (sequence diagrams, top level only). Leaves are grouped into the
sequence boxes by their top-level boundary.

### Component kinds

`kind` selects both the Mermaid participant stereotype and the architecture node
shape:

| `kind` | sequence stereotype | architecture shape |
| --- | --- | --- |
| `participant` | rectangle | rectangle |
| `actor` | actor figure | stadium |
| `boundary` | boundary | hexagon |
| `control` | control | circle |
| `entity` | entity | rectangle |
| `database` | database | cylinder |
| `collections` | collections | subroutine |
| `queue` | queue | parallelogram |

`links` adds a Mermaid actor menu entry (`link <id>: <label> @ <url>`).

## Defining sequences

```nix
sequences.login-flow = {
  title = "Login Flow";
  diagramTitle = "Login";
  accessibility = {
    title = "Login sequence";
    description = "Credentials are checked against PostgreSQL.";
  };
  autonumber = { start = 10; increment = 5; };   # or true | false | "off"
  config = { theme = "redux-color"; look = "neo"; sequence = { mirrorActors = true; }; };
  participants = [ "user" "web" "gateway" "auth" "db" ];
  steps = [ /* ... */ ];
};
```

`config` is emitted verbatim as an `%%{init: ...}%%` directive — the form that
works on both GitLab and Forgejo.

### Step reference

Every step is a single-attribute attrset:

| Step | Renders |
| --- | --- |
| `{ comment = "text"; }` | `%% text` |
| `{ message = { from; to; label; arrow; central; activateTarget; deactivateSource; }; }` | a message |
| `{ note = { position; actors; text; }; }` | `Note over/left of/right of` |
| `{ activate = "id"; }` / `{ deactivate = "id"; }` | activation bar |
| `{ create = "id"; }` / `{ destroy = "id"; }` | participant creation/destruction |
| `{ loop = { label; steps; }; }` | `loop ... end` |
| `{ opt = { label; steps; }; }` | `opt ... end` |
| `{ break = { label; steps; }; }` | `break ... end` |
| `{ rect = { color; steps; }; }` | background `rect ... end` |
| `{ alt = { label?; branches = [ { label; steps; } ... ]; }; }` | `alt` / `else` |
| `{ par = { label?; branches = [ ... ]; }; }` | `par` / `and` |
| `{ parOver = { label?; branches = [ ... ]; }; }` | `par_over` / `and` |
| `{ critical = { label?; branches = [ ... ]; }; }` | `critical` / `option` |
| `{ properties = { actor; text; }; }` | `properties <actor>: ...` |
| `{ details = { actor; text; }; }` | `details <actor>: ...` |

Notes: `position = "over"` accepts one or two actors; `"left"`/`"right"` accept
exactly one. Messages may set `activateTarget = true` (`+` shortcut) or
`deactivateSource = true` (`-` shortcut), and `central = "target" | "source" |
"both"` for central lifeline connections.

### Arrow types

`message.arrow` accepts any of the names below (default `solidArrow`). The text
on the right is the token that gets emitted:

```text
solidOpen                ->
dottedOpen               -->
solidArrow               ->>
dottedArrow              -->>
bidirSolid               <<->>
bidirDotted              <<-->>
solidCross               -x
dottedCross              --x
solidPoint               -)
dottedPoint              --)
solidTopHalf             -|\
dottedTopHalf            --|\
solidBottomHalf          -|/
dottedBottomHalf         --|/
revSolidTopHalf          /|-
revDottedTopHalf         /|--
revSolidBottomHalf       \|-
revDottedBottomHalf      \|--
solidTopStick            -\
dottedTopStick           --\
solidBottomStick         -//
dottedBottomStick        --//
revSolidTopStick         //-
revDottedTopStick        //--
revSolidBottomStick      \\-
revDottedBottomStick     \\--
```


## Architecture configuration

```nix
architecture = {
  title = "Acme Platform";
  direction = "TD";                # TD | LR | BT | RL
  labelMode = "explicit";          # explicit | derived | count | none
  sequenceOrder = [ "login-flow" "token-refresh" "job-processing" ];
  edgeLabels = {
    "web->gateway" = "HTTPS";      # only labels for edges actually produced
  };
  config = { look = "neo"; };      # -> %%{init}%% on architecture diagrams
};
```

Nodes and edges are computed from the sequences:

- **Nodes** are every declared participant, created participant and message
  endpoint, in first-appearance order.
- **Edges** are the distinct `from->to` pairs across all messages (including
  inside blocks); self-messages are dropped from the overview.
- `labelMode = "explicit"` shows a label only when `edgeLabels` provides one;
  `derived` joins the message texts, `count` shows the message count.

Per-sequence "component interaction" views are generated automatically from the
same rules, restricted to a single sequence.

## Generated docs and cross-linking

For sequences `login-flow` and `token-refresh`, `render` produces:

```
docs/
├── README.md                          # index, grouped by type
├── architecture.md                    # global derived flowchart
├── login-flow.md                      # sequence diagram
├── login-flow-architecture.md         # derived per-sequence flowchart
├── token-refresh.md
└── token-refresh-architecture.md
```

Every page gets a **Related** section with relative links, so the pages form a
navigable set. The architecture page links to each sequence, and each sequence
links back to the architecture and to its own component view.

## Validation

`nix run .#render` (and anything using the library) fails evaluation with a
readable error for: unknown component ids, invalid `kind`/`arrow`/`position`/
`central` values, malformed notes, dangling `create`/`destroy`/`activate`
targets, created participants that are also declared, `edgeLabels` keys that no
message produces, and duplicate sequence slugs.

## Caveats

- **Actor menus under `securityLevel: 'strict'`** (Forgejo/Gitea) may not render;
  GitLab renders them. The model still expresses them.
- **mermaid-cli bug:** rendering the actor-menu popup crashes for some
  stereotypes. `nix run .#check-mermaid` recognises this specific crash and skips
  it, while still failing on real errors.
- **`destroy` quirk:** in Mermaid, a `destroy` must be the last statement
  involving that participant (the next statement must reference it). Keep
  `destroy` at the end of a sequence.
- **`participants` vs `create`:** a participant declared with `create` must not
  also appear in `participants`.
