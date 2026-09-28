{ lib }:
let
  strings = lib.strings;
in
rec {
  # A page with an embedded Mermaid diagram and a "Related" link list.
  page =
    {
      title,
      description ? null,
      code,
      related ? [ ],
    }:
    strings.concatStringsSep "\n" (
      [
        "# ${title}"
        ""
      ]
      ++ lib.optional (description != null) (strings.removeSuffix "\n" description)
      ++ lib.optional (description != null) ""
      ++ [
        "```mermaid"
        code
        "```"
      ]
      ++ (
        if related == [ ] then
          [ ]
        else
          [
            ""
            "## Related"
            ""
          ]
          ++ map (l: "- [${l.label}](${l.href})") related
      )
      ++ [ "" ]
    );

  # Relative path from one directory to another file (both relative to the docs
  # root, "" for the root directory).
  relPath =
    fromDir: to:
    let
      splitP = s: lib.filter (x: x != "") (lib.splitString "/" s);
      f = splitP fromDir;
      t = splitP to;
      maxN = lib.min (lib.length f) (lib.length t);
      idxs = lib.range 0 (maxN - 1);
      common = lib.foldl' (
        acc: i: if acc == i && lib.elemAt f i == lib.elemAt t i then i + 1 else acc
      ) 0 idxs;
      ups = lib.genList (_: "..") (lib.length f - common);
      downs = lib.drop common t;
      segs = ups ++ downs;
    in
    if segs == [ ] then "." else lib.concatStringsSep "/" segs;

  # Index page grouping links into titled sections.
  index =
    {
      title,
      intro ? null,
      sections,
    }:
    strings.concatStringsSep "\n" (
      [
        "# ${title}"
        ""
      ]
      ++ lib.optional (intro != null) intro
      ++ lib.optional (intro != null) ""
      ++ lib.concatMap (
        s:
        [
          "## ${s.title}"
          ""
        ]
        ++ map (l: "- [${l.label}](./${l.href})") s.pages
        ++ [ "" ]
      ) sections
    );

  slug =
    s:
    let
      allowed = strings.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789";
      lower = strings.toLower s;
      mapped = map (c: if lib.elem c allowed then c else "-") (strings.stringToCharacters lower);
      collapsed = lib.foldl' (
        acc: c: if c == "-" && (acc == "" || strings.hasSuffix "-" acc) then acc else acc + c
      ) "" mapped;
    in
    strings.removeSuffix "-" (strings.removePrefix "-" collapsed);
}
