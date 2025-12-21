#!/usr/bin/env python3
"""Minimal Google Drive file downloader (no external deps).

Usage:
  python3 scripts/download_gdrive_file.py <FILE_ID> <OUTPUT_PATH>

Notes:
- Handles the common "virus scan too large" confirmation interstitial by
  extracting the confirm token and retrying.
"""

from __future__ import annotations

import html
import os
import re
import sys
import urllib.parse
import urllib.request


def _die(msg: str, code: int = 2) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def _read_text(resp: urllib.response.addinfourl) -> str:
    charset = resp.headers.get_content_charset() or "utf-8"
    return resp.read().decode(charset, errors="replace")


def _extract_confirm_token(page_html: str) -> str | None:
    # Common patterns:
    #  - confirm=t
    #  - name="confirm" value="t"
    #  - href="/uc?export=download&confirm=t&id=..."
    patterns = [
        r"confirm=([0-9A-Za-z_\-]+)",
        r"name=\"confirm\"\s+value=\"([0-9A-Za-z_\-]+)\"",
    ]
    for pat in patterns:
        m = re.search(pat, page_html)
        if m:
            return m.group(1)
    return None


def download_gdrive_file(file_id: str, output_path: str) -> None:
    url = f"https://drive.google.com/uc?export=download&id={urllib.parse.quote(file_id)}"

    # Cookie jar stored in-memory by opener.
    cj = urllib.request.HTTPCookieProcessor()
    opener = urllib.request.build_opener(cj)

    # First request: may return the file directly, or a confirmation HTML page.
    with opener.open(url) as resp:
        ctype = resp.headers.get("Content-Type", "")
        if "text/html" not in ctype.lower():
            data = resp.read()
            os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(data)
            return

        page = _read_text(resp)

    token = _extract_confirm_token(page)
    if not token:
        # Some files are served through HTML with a direct "download" link.
        # If we can't find a token, fail loudly.
        snippet = html.unescape(page[:400]).replace("\n", " ")
        _die(f"Unable to extract Google Drive confirm token. HTML starts with: {snippet!r}")

    url2 = (
        "https://drive.google.com/uc?export=download"
        f"&confirm={urllib.parse.quote(token)}"
        f"&id={urllib.parse.quote(file_id)}"
    )

    with opener.open(url2) as resp2:
        data = resp2.read()

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(data)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip())
        return 2

    file_id = argv[1].strip()
    out = argv[2].strip()
    if not file_id:
        _die("FILE_ID is empty")
    if not out:
        _die("OUTPUT_PATH is empty")

    download_gdrive_file(file_id, out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
