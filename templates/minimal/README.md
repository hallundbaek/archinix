# My Architecture (Archinix)

A minimal [Archinix](https://github.com/hallundbaek/archinix) project. It imports
Archinix as a flake input, so this repository only needs `flake.nix` and the
`model/` directory.

## Usage

```console
$ nix run .#render            # write ./docs
$ nix run .#render -- docs --check
$ nix run .#watch             # live preview while editing model/
$ nix run .#check-mermaid     # validate the generated diagrams
$ nix flake check
```

Edit `model/default.nix` and re-run `nix run .#render`. Commit `./docs` to
publish the diagrams; add `docsPath = ./docs;` to `flake.nix` to enable the
`docs-up-to-date` check.

See the Archinix README for the model reference (components, boundaries,
semantic types, sequences and nested architectures).
