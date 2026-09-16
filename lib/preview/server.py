#!/usr/bin/env python3
"""Archinix preview server.

Serves a directory of generated Markdown as rendered HTML with client-side
Mermaid, and reloads the browser whenever the underlying files change. Only the
Python standard library plus `markdown` are required.
"""

import argparse
import html
import mimetypes
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

import markdown

MERMAID_JS = os.environ.get("ARCHINIX_MERMAID_JS", "")
CDN_FALLBACK = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<script src="{mermaid_src}"></script>
<style>
  :root {{
    color-scheme: light dark;
    --bg: #ffffff;
    --fg: #1f2328;
    --code-bg: #f6f8fa;
    --border: #d0d7de;
    --link: #0969da;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme]) {{
      --bg: #0d1117;
      --fg: #e6edf3;
      --code-bg: #161b22;
      --border: #30363d;
      --link: #4493f8;
    }}
  }}
  :root[data-theme="dark"] {{
    --bg: #0d1117;
    --fg: #e6edf3;
    --code-bg: #161b22;
    --border: #30363d;
    --link: #4493f8;
  }}
  body {{
    margin: 0 auto; max-width: 60rem; padding: 2rem 1.25rem 6rem;
    background: var(--bg); color: var(--fg);
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }}
  code, pre {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
  pre {{ padding: .8rem 1rem; overflow: auto; border-radius: 6px; background: var(--code-bg); border: 1px solid var(--border); }}
  code {{ padding: .1rem .3rem; border-radius: 4px; background: var(--code-bg); }}
  pre code {{ padding: 0; background: none; }}
  table {{ border-collapse: collapse; }}
  th, td {{ border: 1px solid var(--border); padding: .3rem .6rem; }}
  img, svg {{ max-width: 100%; }}
  .mermaid {{ text-align: center; margin: 1.5rem 0; }}
  a {{ color: var(--link); }}
</style>
</head>
<body>
<main>
{content}
</main>
<script>
  const mermaidLib = window.mermaid;
  if (mermaidLib) {{
    const forced = new URLSearchParams(location.search).get("theme");
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)");
    const dark = forced ? forced === "dark" : prefersDark.matches;
    document.documentElement.dataset.theme = dark ? "dark" : "light";
    mermaidLib.initialize({{
      startOnLoad: false,
      securityLevel: "loose",
      theme: dark ? "dark" : "default",
    }});
    if (!forced) prefersDark.addEventListener("change", () => location.reload());
    const NL = String.fromCharCode(10);
    const nodes = Array.from(document.querySelectorAll("pre > code.language-mermaid")).map((code) => {{
      const div = document.createElement("div");
      div.className = "mermaid";
      div.dataset.mermaidSrc = code.textContent;
      div.textContent = code.textContent;
      code.parentElement.replaceWith(div);
      return div;
    }});
    (async () => {{
      for (const node of nodes) {{
        try {{
          await mermaidLib.run({{ nodes: [node] }});
        }} catch (err) {{
          // Mermaid crashes drawing actor-menu popups for actor/boundary/
          // control/entity participants. Retry without `link` lines so the
          // rest of the diagram still renders.
          console.warn("mermaid render failed, retrying without link menus", err);
          node.removeAttribute("data-processed");
          node.textContent = (node.dataset.mermaidSrc || "")
            .split(NL)
            .filter((line) => !line.trimStart().startsWith("link "))
            .join(NL);
          try {{ await mermaidLib.run({{ nodes: [node] }}); }}
          catch (err2) {{ console.error("mermaid render failed", err2); }}
        }}
      }}
    }})();
  }}

  let seen = null;
  async function poll() {{
    try {{
      const res = await fetch("/__version", {{ cache: "no-store" }});
      const v = await res.text();
      if (seen === null) seen = v;
      else if (v !== seen) location.reload();
    }} catch (e) {{ /* server restarting; keep trying */ }}
  }}
  setInterval(poll, 1000);
  poll();
</script>
</body>
</html>
"""


def first_heading(text, fallback):
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else fallback


class Handler(BaseHTTPRequestHandler):
    server_version = "ArchinixPreview/1.0"

    def __init__(self, *args, root=None, **kwargs):
        self.root = root
        super().__init__(*args, **kwargs)

    # -- helpers -----------------------------------------------------------
    def _send(self, body, content_type, status=200, cache="no-store"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _error(self, status, message):
        self._send(
            f"<!doctype html><h1>{status}</h1><p>{html.escape(message)}</p>",
            "text/html; charset=utf-8",
            status,
        )

    def _version(self):
        latest = 0.0
        for dirpath, _dirs, files in os.walk(self.root):
            for name in files:
                try:
                    latest = max(latest, os.path.getmtime(os.path.join(dirpath, name)))
                except OSError:
                    pass
        return str(latest)

    def _resolve(self, url_path):
        path = url_path.strip("/")
        if path == "":
            path = "README.md"
        target = os.path.normpath(os.path.join(self.root, path))
        if not target.startswith(os.path.abspath(self.root) + os.sep) and target != os.path.abspath(self.root):
            return None
        if os.path.isdir(target):
            target = os.path.join(target, "README.md")
        return target

    def _render_markdown(self, target):
        with open(target, "r", encoding="utf-8") as handle:
            text = handle.read()
        content = markdown.markdown(
            text,
            extensions=["fenced_code", "tables", "sane_lists", "attr_list"],
        )
        title = first_heading(text, os.path.basename(target))
        mermaid_src = "/__assets/mermaid.min.js"
        if not MERMAID_JS or not os.path.exists(MERMAID_JS):
            mermaid_src = CDN_FALLBACK
        return PAGE.format(title=html.escape(title), content=content, mermaid_src=mermaid_src)

    # -- HTTP --------------------------------------------------------------
    def do_GET(self):
        self._serve()

    def do_HEAD(self):
        self._serve()

    def _serve(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path == "/__version":
            self._send(self._version(), "text/plain; charset=utf-8")
            return

        if path == "/__assets/mermaid.min.js":
            if MERMAID_JS and os.path.exists(MERMAID_JS):
                with open(MERMAID_JS, "rb") as handle:
                    self._send(
                        handle.read(),
                        "text/javascript; charset=utf-8",
                        cache="public, max-age=31536000, immutable",
                    )
            else:
                self._error(404, "mermaid bundle not available")
            return

        target = self._resolve(path)
        if target is None or not os.path.isfile(target):
            self._error(404, f"not found: {path}")
            return

        if target.endswith(".md"):
            self._send(self._render_markdown(target), "text/html; charset=utf-8")
        else:
            ctype, _ = mimetypes.guess_type(target)
            with open(target, "rb") as handle:
                self._send(handle.read(), ctype or "application/octet-stream")

    def log_message(self, fmt, *args):
        if "/__version" in (fmt % args):
            return
        sys.stderr.write("[archinix] %s\n" % (fmt % args))


def main():
    parser = argparse.ArgumentParser(description="Archinix preview server")
    parser.add_argument("--root", required=True, help="directory of generated markdown")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    if not os.path.isdir(args.root):
        parser.error(f"root directory does not exist: {args.root}")

    root = os.path.abspath(args.root)
    handler = lambda *a, **kw: Handler(*a, root=root, **kw)  # noqa: E731
    httpd = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[archinix] serving {root} on http://{args.host}:{args.port}/", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
