"""MkDocs hook: open external links in a new tab.

Rewrites every rendered ``<a href="...">`` whose target host is outside the
documentation's own ``site_url`` to include ``target="_blank"`` and
``rel="noopener noreferrer"``.

Internal links (relative URLs, fragments, and links that point at the
configured ``site_url`` host) are left alone so in-site navigation keeps its
single-tab behaviour.
"""
from __future__ import annotations

import re
from urllib.parse import urlparse


_ANCHOR_RE = re.compile(r"<a\b([^>]*?)href=\"([^\"]+)\"([^>]*)>", re.IGNORECASE)


def _is_external(href: str, site_host: str) -> bool:
    if not href:
        return False
    if href.startswith(("#", "/", "mailto:", "tel:", "javascript:")):
        return False
    parsed = urlparse(href)
    if not parsed.scheme or not parsed.netloc:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    if site_host and parsed.netloc.lower() == site_host.lower():
        return False
    return True


def _rewrite(match: "re.Match[str]", site_host: str) -> str:
    pre, href, post = match.group(1), match.group(2), match.group(3)
    attrs = f"{pre}{post}"
    if not _is_external(href, site_host):
        return match.group(0)
    if re.search(r"\btarget\s*=", attrs, flags=re.IGNORECASE):
        return match.group(0)
    return (
        f'<a{pre}href="{href}"{post} target="_blank" rel="noopener noreferrer">'
    )


def on_page_content(html: str, page, config, files):  # noqa: D401, ARG001
    site_url = config.get("site_url") or ""
    site_host = urlparse(site_url).netloc if site_url else ""
    return _ANCHOR_RE.sub(lambda m: _rewrite(m, site_host), html)
