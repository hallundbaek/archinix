{ lib }:
let
  inherit (builtins)
    elem
    elemAt
    match
    substring
    toString
    ;

  strings = lib.strings;

  # Escape a single line of text for use inside Mermaid labels / messages.
  specialChars = {
    "\"" = "#quot;";
    "#" = "#35;";
    ";" = "#59;";
    "<" = "#lt;";
    ">" = "#gt;";
    "&" = "#amp;";
  };

  escapeLine =
    s: strings.concatStringsSep "" (map (c: specialChars.${c} or c) (strings.stringToCharacters s));

  # Escape text; explicit newlines become <br/> line breaks.
  escape =
    s: strings.concatStringsSep "<br/>" (map escapeLine (strings.splitString "\n" (toString s)));

  # Identifiers that would collide with Mermaid keywords / break the parser.
  reservedWords = [
    "end"
    "box"
    "participant"
    "actor"
    "create"
    "destroy"
    "loop"
    "rect"
    "opt"
    "alt"
    "else"
    "par"
    "par_over"
    "and"
    "critical"
    "option"
    "break"
    "left"
    "right"
    "of"
    "over"
    "note"
    "activate"
    "deactivate"
    "title"
    "autonumber"
    "off"
    "link"
    "links"
    "properties"
    "details"
    "sequenceDiagram"
    "as"
    "wrap"
    "nowrap"
  ];

  validId = id: isString id && match "[A-Za-z_][A-Za-z0-9_]*" id != null && !(elem id reservedWords);

  isString = x: builtins.isString x;

  # ---------------------------------------------------------------------------
  # Arrow tokens (authoritative, from the Mermaid sequenceDiagram jison lexer).
  # ---------------------------------------------------------------------------
  arrowTokens = {
    solidOpen = "->";
    dottedOpen = "-->";
    solidArrow = "->>";
    dottedArrow = "-->>";
    bidirSolid = "<<->>";
    bidirDotted = "<<-->>";
    solidCross = "-x";
    dottedCross = "--x";
    solidPoint = "-)";
    dottedPoint = "--)";
    solidTopHalf = "-|\\";
    dottedTopHalf = "--|\\";
    solidBottomHalf = "-|/";
    dottedBottomHalf = "--|/";
    revSolidTopHalf = "/|-";
    revDottedTopHalf = "/|--";
    revSolidBottomHalf = "\\|-";
    revDottedBottomHalf = "\\|--";
    solidTopStick = "-\\";
    dottedTopStick = "--\\";
    solidBottomStick = "-//";
    dottedBottomStick = "--//";
    revSolidTopStick = "//-";
    revDottedTopStick = "//--";
    revSolidBottomStick = "\\\\-";
    revDottedBottomStick = "\\\\--";
  };

  arrowEnum = builtins.attrNames arrowTokens;

  # ---------------------------------------------------------------------------
  # Participant stereotypes / architecture shapes.
  # ---------------------------------------------------------------------------
  kindEnum = [
    "participant"
    "actor"
    "boundary"
    "control"
    "entity"
    "database"
    "collections"
    "queue"
  ];

  # Flowchart node shape for a given kind and quoted label.
  shape =
    kind: quoted:
    if kind == "participant" then
      "[${quoted}]"
    else if kind == "actor" then
      "([${quoted}])"
    else if kind == "boundary" then
      "{{${quoted}}}"
    else if kind == "control" then
      "((${quoted}))"
    else if kind == "database" then
      "[(${quoted})]"
    else if kind == "collections" then
      "[[${quoted}]]"
    else if kind == "queue" then
      "[/${quoted}/]"
    else
      "[${quoted}]";

  # Flowchart classDef styling shared by all architecture diagrams.
  classDefs = [
    "classDef actor fill:#eef0ff,stroke:#5a67d8,color:#1a202c"
    "classDef participant fill:#eaf5ff,stroke:#3182ce,color:#1a202c"
    "classDef boundary fill:#edf2f7,stroke:#4a5568,color:#1a202c"
    "classDef control fill:#e6fffa,stroke:#319795,color:#1a202c"
    "classDef entity fill:#fffaf0,stroke:#dd6b20,color:#1a202c"
    "classDef database fill:#faf5ff,stroke:#805ad5,color:#1a202c"
    "classDef collections fill:#f0fff4,stroke:#38a169,color:#1a202c"
    "classDef queue fill:#fff5f5,stroke:#e53e3e,color:#1a202c"
  ];

  # ---------------------------------------------------------------------------
  # Color handling (hex is invalid in Mermaid sequence boxes).
  # ---------------------------------------------------------------------------
  hexDigits = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "A" = 10;
    "B" = 11;
    "C" = 12;
    "D" = 13;
    "E" = 14;
    "F" = 15;
  };

  hexVal = c: hexDigits.${strings.toUpper c} or null;

  parseHex2 = s: hexVal (substring 0 1 s) * 16 + hexVal (substring 1 1 s);

  hexToRgb =
    c:
    let
      m = match "#([0-9a-fA-F]{6})" c;
    in
    if m == null then
      null
    else
      "rgb(${toString (parseHex2 (substring 0 2 (elemAt m 0)) + 0)},"
      + "${toString (parseHex2 (substring 2 2 (elemAt m 0)))},"
      + "${toString (parseHex2 (substring 4 2 (elemAt m 0)))})";

  validColor =
    c:
    isString c
    && (
      match "#[0-9a-fA-F]{3}" c != null
      || match "#[0-9a-fA-F]{6}" c != null
      || match "rgba?\\([^)]*\\)" c != null
      || match "hsla?\\([^)]*\\)" c != null
      || match "[A-Za-z][A-Za-z0-9 _-]*" c != null
    );

  # Color usable inside a `box` or flowchart `style` (hex normalized to rgb(),
  # whitespace inside functional notation removed).
  stripSpaces =
    s: strings.concatStringsSep "" (lib.filter (c: c != " ") (strings.stringToCharacters s));

  boxColor =
    c:
    if match "#[0-9a-fA-F]{6}" c != null then
      hexToRgb c
    else if match "#[0-9a-fA-F]{3}" c != null then
      hexToRgb (
        "#"
        + substring 0 1 c
        + substring 0 1 c
        + substring 1 1 c
        + substring 1 1 c
        + substring 2 1 c
        + substring 2 1 c
      )
    else if match "(rgba?|hsla?)\\([^)]*\\)" c != null then
      stripSpaces c
    else
      c;

  hexByte =
    n:
    let
      d = "0123456789ABCDEF";
      hi = n / 16;
      lo = n - hi * 16;
    in
    (substring hi 1 d) + (substring lo 1 d);

  # Flowchart `style` accepts hex and named colors, but not rgb()/hsl() with
  # commas. Convert rgb()/rgba() to hex; return null for anything unsupported.
  rgbMatch = match "rgba?\\(([0-9]+)[, ]+([0-9]+)[, ]+([0-9]+)([, ]+[0-9]*\\.?[0-9]+)?\\)";

  styleColor =
    c:
    let
      m = rgbMatch c;
    in
    if match "#[0-9a-fA-F]{6}" c != null then
      c
    else if match "#[0-9a-fA-F]{3}" c != null then
      "#"
      + substring 0 1 c
      + substring 0 1 c
      + substring 1 1 c
      + substring 1 1 c
      + substring 2 1 c
      + substring 2 1 c
    else if m != null then
      "#"
      + hexByte (builtins.fromJSON (elemAt m 0))
      + hexByte (builtins.fromJSON (elemAt m 1))
      + hexByte (builtins.fromJSON (elemAt m 2))
    else if match "[A-Za-z][A-Za-z0-9 _-]*" c != null then
      c
    else
      null;

  # ---------------------------------------------------------------------------
  # Small helpers.
  # ---------------------------------------------------------------------------
  lines = xs: strings.concatStringsSep "\n" (builtins.filter (x: x != "") xs);

  quote = s: "\"${escape s}\"";
in
{
  inherit
    escape
    escapeLine
    reservedWords
    validId
    isString
    ;
  inherit arrowTokens arrowEnum;
  inherit
    kindEnum
    shape
    classDefs
    ;
  inherit
    hexToRgb
    validColor
    boxColor
    styleColor
    ;
  inherit lines quote;
}
