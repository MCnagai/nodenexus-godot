#!/usr/bin/env python3
"""Align a pre-created Direct Upload project with this repository's master branch."""
import json
import os
import re
import urllib.error
import urllib.request


def main():
    account = os.environ["CF_ACCOUNT_ID"]
    project = os.environ["CF_PROJECT"]
    token = os.environ["CF_API_TOKEN"]
    if not re.fullmatch(r"[a-fA-F0-9]{32}", account) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", project):
        raise ValueError("Invalid Cloudflare account ID or Pages project name")
    url = f"https://api.cloudflare.com/client/v4/accounts/{account}/pages/projects/{project}"

    def request(method="GET", data=None):
        req = urllib.request.Request(url, method=method, data=None if data is None else json.dumps(data).encode(), headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Cloudflare Pages API returned HTTP {error.code}; check the account, project, and token permissions") from None
        if not result.get("success") or not isinstance(result.get("result"), dict):
            raise RuntimeError("Cloudflare Pages API did not confirm project configuration")
        return result["result"]

    current = request()
    if current.get("source"):
        raise RuntimeError("Use a Direct Upload Pages project; this project has a Git integration")
    if current.get("production_branch") != "master":
        request("PATCH", {"production_branch": "master"})
        if request().get("production_branch") != "master":
            raise RuntimeError("Pages production branch was not updated to master")
    print("PAGES_PROJECT_CONFIGURED: Direct Upload, production branch master")


if __name__ == "__main__":
    main()
