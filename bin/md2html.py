#!/usr/bin/env python3
"""Tiny dependency-free Markdown -> self-contained HTML renderer for our deliverables.
   md2html.py file.md [more.md ...]   writes file.html next to each input.
Supports: # headings, paragraphs, **bold**, *italic*, `code`, [links](..), ![img](x.svg) (SVGs are inlined),
fenced ``` code blocks, pipe tables, > quotes, - / 1. lists (two levels), --- rules.
Links to .md files are rewritten to the rendered .html. Light and dark themes via prefers-color-scheme."""
import html, os, re, sys

CSS = """
:root{--bg:#ffffff;--fg:#1d2330;--muted:#5b6475;--line:#d9dee7;--soft:#f5f7fa;--accent:#2f6fd6;--code:#f1f3f7}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#14171d;--fg:#e6e9ef;--muted:#9aa3b5;--line:#2e3441;--soft:#1b1f27;--accent:#6aa0f5;--code:#1f2430}}
:root[data-theme="dark"]{--bg:#14171d;--fg:#e6e9ef;--muted:#9aa3b5;--line:#2e3441;--soft:#1b1f27;--accent:#6aa0f5;--code:#1f2430}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:980px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:2rem;line-height:1.2;margin:.2em 0 .6em} h2{font-size:1.45rem;margin:1.8em 0 .5em;padding-top:.4em;border-top:1px solid var(--line)}
h3{font-size:1.15rem;margin:1.4em 0 .4em} h4{font-size:1rem;margin:1.2em 0 .3em}
a{color:var(--accent)} p{margin:.6em 0} ul,ol{padding-left:1.4em} li{margin:.2em 0}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.88em;background:var(--code);padding:.1em .35em;border-radius:4px}
pre{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:12px 14px;overflow-x:auto;line-height:1.45}
pre code{background:none;padding:0;font-size:.85em}
.table{overflow-x:auto;margin:1em 0} table{border-collapse:collapse;width:100%;font-size:.93em}
th,td{border:1px solid var(--line);padding:6px 9px;text-align:left;vertical-align:top} th{background:var(--soft)}
blockquote{margin:1em 0;padding:.4em 1em;border-left:4px solid var(--accent);background:var(--soft);border-radius:0 6px 6px 0}
hr{border:0;border-top:1px solid var(--line);margin:2em 0}
figure{margin:1.2em 0} figure svg,figure img{width:100%;height:auto;border:1px solid var(--line);border-radius:10px}
figcaption{color:var(--muted);font-size:.9em;margin-top:.3em}
@media print{body{background:#fff;color:#000} main{max-width:none;padding:0} h2{break-before:auto} pre,table,figure{break-inside:avoid}}
"""


def inline(s):
    s = html.escape(s, quote=False)
    codes = []
    s = re.sub(r"`([^`]+)`", lambda m: codes.append(m.group(1)) or f"\x00{len(codes) - 1}\x00", s)
    s = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", r'<img alt="\1" src="\2">', s)
    s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{md_link(m.group(2))}">{m.group(1)}</a>', s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{codes[int(m.group(1))]}</code>", s)
    return s


def md_link(url):
    if re.match(r"^[a-z]+://", url) or url.startswith("#"):
        return url
    return re.sub(r"\.md(#.*)?$", lambda m: ".html" + (m.group(1) or ""), url)


def render(md, base):
    lines = md.split("\n")
    out, i, title = [], 0, None
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            j = i + 1
            buf = []
            while j < len(lines) and not lines[j].startswith("```"):
                buf.append(lines[j]); j += 1
            out.append("<pre><code>" + html.escape("\n".join(buf)) + "</code></pre>")
            i = j + 1; continue
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if m:
            lvl, txt = len(m.group(1)), m.group(2).strip()
            title = title or re.sub(r"[`*]", "", txt)
            anchor = re.sub(r"[^a-z0-9]+", "-", txt.lower()).strip("-")
            out.append(f'<h{lvl} id="{anchor}">{inline(txt)}</h{lvl}>'); i += 1; continue
        m = re.match(r"^!\[([^\]]*)\]\(([^)\s]+)\)\s*$", ln)
        if m:
            alt, src = m.groups()
            path = os.path.join(base, src)
            if src.endswith(".svg") and os.path.exists(path):
                svg = open(path).read()
                svg = re.sub(r"<\?xml[^>]*>", "", svg)
                out.append(f"<figure>{svg}<figcaption>{html.escape(alt)}</figcaption></figure>")
            else:
                out.append(f'<figure><img alt="{html.escape(alt)}" src="{src}"><figcaption>{html.escape(alt)}</figcaption></figure>')
            i += 1; continue
        if ln.strip() in ("---", "***"):
            out.append("<hr>"); i += 1; continue
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|?\s*:?-{2,}", lines[i + 1]):
            def cells(r):
                r = r.strip()
                r = r[1:] if r.startswith("|") else r
                r = r[:-1] if r.endswith("|") else r
                return [c.strip() for c in re.split(r"(?<!\\)\|", r)]
            head = cells(ln); rows = []
            j = i + 2
            while j < len(lines) and lines[j].startswith("|"):
                rows.append(cells(lines[j])); j += 1
            t = ["<div class=\"table\"><table><thead><tr>"] + [f"<th>{inline(c)}</th>" for c in head] + ["</tr></thead><tbody>"]
            for r in rows:
                t.append("<tr>" + "".join(f"<td>{inline(c.replace(chr(92) + '|', '|'))}</td>" for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t)); i = j; continue
        if ln.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].startswith(">"):
                buf.append(lines[i].lstrip(">").strip()); i += 1
            out.append("<blockquote><p>" + inline(" ".join(buf)) + "</p></blockquote>"); continue
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", ln)
        if m:
            html_list, stack = [], []
            while i < len(lines):
                m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", lines[i])
                if not m:
                    if lines[i].startswith("  ") and lines[i].strip() and html_list:   # continuation line
                        html_list[-1] = html_list[-1][:-5] + " " + inline(lines[i].strip()) + "</li>"; i += 1; continue
                    break
                depth = min(len(m.group(1)) // 2, 3)
                tag = "ol" if m.group(2)[0].isdigit() else "ul"
                while len(stack) < depth + 1:
                    html_list.append(f"<{tag}>"); stack.append(tag)
                while len(stack) > depth + 1:
                    html_list.append(f"</{stack.pop()}>")
                html_list.append(f"<li>{inline(m.group(3))}</li>"); i += 1
            while stack:
                html_list.append(f"</{stack.pop()}>")
            out.append("".join(html_list)); continue
        if not ln.strip():
            i += 1; continue
        buf = []
        while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,6}\s|```|\||>|\s*([-*]|\d+\.)\s|!\[)", lines[i]):
            buf.append(lines[i].strip()); i += 1
        if not buf:
            buf.append(lines[i].strip()); i += 1
        out.append("<p>" + inline(" ".join(buf)) + "</p>")
    return title or "document", "\n".join(out)


def main():
    for path in sys.argv[1:]:
        md = open(path).read()
        title, body = render(md, os.path.dirname(os.path.abspath(path)))
        doc = (f'<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
               f'<meta name="viewport" content="width=device-width, initial-scale=1">'
               f"<title>{html.escape(title)}</title><style>{CSS}</style></head>\n<body><main>\n{body}\n</main></body></html>\n")
        outp = os.path.splitext(path)[0] + ".html"
        open(outp, "w").write(doc)
        print("wrote", outp)


if __name__ == "__main__":
    main()
