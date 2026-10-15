#!/usr/bin/env python3
"""Fail before upload unless unauthenticated requests go to the expected Access login."""
import argparse
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(base: str, team: str, attempts: int = 4, assets=()) -> None:
    if not re.fullmatch(r"[a-z0-9-]+\.cloudflareaccess\.com", team):
        raise ValueError("CLOUDFLARE_ACCESS_TEAM_DOMAIN must be <team>.cloudflareaccess.com (no scheme)")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.path not in ("", "/") or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Expected an HTTPS deployment origin")
    opener = urllib.request.build_opener(NoRedirect)
    paths = ("/", "/index.pck", "/build-info.json", *assets) if assets else ("/", "/index.wasm", "/index.pck", "/build-info.json")
    for path in paths:
        for attempt in range(attempts):
            if attempt:
                time.sleep((2, 5, 10)[min(attempt - 1, 2)])
            request = urllib.request.Request(base.rstrip("/") + path, headers={"Cache-Control": "no-cache", "Accept": "text/html,application/xhtml+xml", "User-Agent": "Mozilla/5.0 NodeNexus-Access-Check/1.0"})
            try:
                response = opener.open(request, timeout=20)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                location = urllib.parse.urlsplit(response.headers.get("Location", ""))
                passed = response.code in (302, 303, 307) and location.scheme == "https" and location.hostname == team and location.path.startswith("/cdn-cgi/access/login")
                if passed:
                    break
                title = ""
                if hasattr(response, "read"):
                    match = re.search(r"<title[^>]*>([^<]*)", response.read(4096).decode("utf-8", "replace"), re.I)
                    title = " ".join(match.group(1).split())[:160] if match else ""
                failure = f"Access protection not confirmed for {parsed.hostname}{path} (HTTP {response.code}, title={title}, mitigation={response.headers.get('cf-mitigated', '')}); upload blocked"
        else:
            raise RuntimeError(failure)
        print(f"ACCESS_LOGIN_REQUIRED: {parsed.hostname}{path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--manifest")
    args = parser.parse_args()
    assets = []
    if args.manifest:
        with open(args.manifest) as source:
            metadata = json.load(source)
        for key in ("wasm", "engine", "loader"):
            asset = metadata[key]
            if not re.fullmatch(r"assets/(engine|loader)\.[a-f0-9]{16}\.(js|wasm\.gz)", asset):
                raise ValueError("Unexpected runtime asset path in build manifest")
            assets.append("/" + asset)
    check(args.url, args.team, assets=assets)
