#!/usr/bin/env python3
"""Fail before upload unless unauthenticated requests go to the expected Access login."""
import argparse
import re
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(base: str, team: str) -> None:
    if not re.fullmatch(r"[a-z0-9-]+\.cloudflareaccess\.com", team):
        raise ValueError("CLOUDFLARE_ACCESS_TEAM_DOMAIN must be <team>.cloudflareaccess.com (no scheme)")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.path not in ("", "/") or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Expected an HTTPS deployment origin")
    opener = urllib.request.build_opener(NoRedirect)
    for path in ("/", "/index.wasm", "/index.pck", "/build-info.json"):
        request = urllib.request.Request(base.rstrip("/") + path, headers={"Cache-Control": "no-cache"})
        try:
            response = opener.open(request, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            location = urllib.parse.urlsplit(response.headers.get("Location", ""))
            if response.code not in (302, 303, 307) or location.scheme != "https" or location.hostname != team or not location.path.startswith("/cdn-cgi/access/login"):
                raise RuntimeError(f"Access protection not confirmed for {parsed.hostname}{path} (HTTP {response.code}); upload blocked")
        print(f"ACCESS_LOGIN_REQUIRED: {parsed.hostname}{path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--team", required=True)
    args = parser.parse_args()
    check(args.url, args.team)
