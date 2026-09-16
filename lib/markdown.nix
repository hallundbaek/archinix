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
          ++ map (l: "- [${l.label}](./${l.href})") related
      )
      ++ [ "" ]
    );

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
