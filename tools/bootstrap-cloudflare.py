#!/usr/bin/env python3
"""Provision the project's Pages and Access configuration from GitHub Secrets."""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


class APIError(RuntimeError):
    def __init__(self, status, codes, context="", message=""):
        self.status = status
        self.codes = codes
        self.api_message = message
        super().__init__(f"Cloudflare HTTP {status}, error codes {codes}, {context}. {message} No game upload was attempted.")


class Cloudflare:
    def __init__(self, account, token):
        self.base = f"https://api.cloudflare.com/client/v4/accounts/{account}"
        self.token = token

    def request(self, method, path, data=None):
        req = urllib.request.Request(self.base + path, method=method, data=None if data is None else json.dumps(data).encode(), headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json", "User-Agent": "NodeNexus-Setup/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            try:
                errors = json.load(error).get("errors", [])
                codes = [item.get("code") for item in errors]
                message = " ".join(str(item.get("message", "")) for item in errors)
                message = message.replace(self.token, "[redacted]")
                message = re.sub(r"[^\s@]+@[^\s@]+", "[email]", message)
                message = " ".join(message.split())[:300]
            except (ValueError, AttributeError):
                codes = []
                message = ""
            raise APIError(error.code, codes, f"{method} {path}", message) from None
        if not payload.get("success"):
            raise APIError(200, [item.get("code") for item in payload.get("errors", [])], f"{method} {path}")
        return payload.get("result")

    def list(self, path):
        result = []
        for page in range(1, 201):
            batch = self.request("GET", f"{path}?per_page=50&page={page}")
            if not isinstance(batch, list):
                raise RuntimeError("Unexpected Cloudflare list response")
            result.extend(batch)
            if len(batch) < 50:
                return result
        raise RuntimeError("Cloudflare pagination limit reached; setup stopped")


def provision(api, project, email):
    # Validate before making any account changes. Never log the supplied email/token.
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", project) or len(project) > 58:
        raise ValueError("Invalid Pages project name")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise ValueError("Set CLOUDFLARE_ACCESS_EMAIL to the single email allowed to sign in")
    email = email.lower()
    path = f"/pages/projects/{project}"
    try:
        current = api.request("GET", path)
    except APIError as error:
        if error.status != 404:
            raise
        current = api.request("POST", "/pages/projects", {"name": project, "production_branch": "master"})
    if current.get("source"):
        raise RuntimeError("The selected Pages project has Git integration; use Direct Upload")

    try:
        organization = api.request("GET", "/access/organizations")
    except APIError as error:
        disabled = error.status == 403 and 9999 in error.codes and "access.api.error.not_enabled" in error.api_message
        if error.status != 404 and not disabled:
            raise
        organization = None
    if not organization:
        # No billing/subscription APIs are called. Cloudflare may require owner enrollment.
        organization = api.request("POST", "/access/organizations", {"name": "NodeNexus"})
    team = organization.get("auth_domain", "")
    if not re.fullmatch(r"[a-z0-9-]+\.cloudflareaccess\.com", team):
        raise RuntimeError("Cloudflare did not return a valid Access team domain")

    providers = api.list("/access/identity_providers")
    otp = next((item for item in providers if item.get("type") == "onetimepin"), None)
    if otp is None:
        otp = api.request("POST", "/access/identity_providers", {"name": "NodeNexus email PIN", "type": "onetimepin", "config": {}})
    if not otp.get("id"):
        raise RuntimeError("Cloudflare did not confirm the email identity provider")

    applications = api.list("/access/apps")
    domains = [(f"{project}.pages.dev", "main"), (f"*.{project}.pages.dev", "previews")]
    # More-specific existing apps could override the wildcard's email restriction.
    for app in applications:
        domains_in_app = [app.get("domain", ""), *(app.get("self_hosted_domains") or [])]
        domains_in_app += [item.get("uri", "") for item in (app.get("destinations") or []) if item.get("type") == "public"]
        for domain in domains_in_app:
            host = domain.removeprefix("https://").removeprefix("http://").split("/")[0]
            if host == f"{project}.pages.dev" or host.endswith(f".{project}.pages.dev"):
                if domain not in dict(domains) or app.get("domain") not in dict(domains):
                    raise RuntimeError("An overlapping Access application needs review; no existing app was modified")

    policy_name = f"NodeNexus {project} owner only"
    matches = [policy for policy in api.list("/access/policies") if policy.get("name") == policy_name]
    if len(matches) > 1 or any(policy.get("app_count", 0) > 2 for policy in matches):
        raise RuntimeError("The owner policy is duplicated or shared with other applications; review required")
    policy = {"name": policy_name, "decision": "allow", "include": [{"email": {"email": email}}], "exclude": [], "require": []}
    if matches:
        owner = api.request("PUT", f'/access/policies/{matches[0]["id"]}', policy)
    else:
        owner = api.request("POST", "/access/policies", policy)
    owner_id = owner["id"]
    verified = api.request("GET", f"/access/policies/{owner_id}")
    if any(verified.get(key) != policy[key] for key in ("decision", "include")) or verified.get("exclude") or verified.get("require"):
        raise RuntimeError("Cloudflare did not confirm the exact owner-only policy")

    for domain, label in domains:
        name = f"NodeNexus {project} {label}"
        matches = [app for app in applications if app.get("domain") == domain]
        if len(matches) > 1:
            raise RuntimeError("Multiple Access applications protect the same domain; review required")
        app = matches[0] if matches else None
        # Adopt only project-specific applications; leave unrelated applications alone.
        if app and app.get("name") != name:
            raise RuntimeError(f"An existing Access application protects {domain}; review it before automatic adoption")
        if app:
            linked = api.request("GET", f'/access/apps/{app["id"]}').get("policies") or []
            if any((item if isinstance(item, str) else item.get("id")) != owner_id for item in linked):
                raise RuntimeError("Unexpected Access policies require review; game upload blocked")
        config = {"name": name, "domain": domain, "type": "self_hosted", "session_duration": "24h", "allowed_idps": [otp["id"]], "auto_redirect_to_identity": True, "policies": [{"id": owner_id, "precedence": 1}]}
        if app:
            app = api.request("PUT", f'/access/apps/{app["id"]}', config)
        else:
            app = api.request("POST", "/access/apps", config)
        verified_app = api.request("GET", f'/access/apps/{app["id"]}')
        linked = verified_app.get("policies") or []
        ids = [item if isinstance(item, str) else item.get("id") for item in linked]
        if ids != [owner_id] or verified_app.get("domain") != domain:
            raise RuntimeError("Cloudflare did not confirm the application's owner-only policy attachment")
        print(f"ACCESS_CONFIGURED: {domain} (single-email policy)")

    if current.get("production_branch") != "master":
        api.request("PATCH", path, {"production_branch": "master"})
        if api.request("GET", path).get("production_branch") != "master":
            raise RuntimeError("Cloudflare did not confirm production branch master")
    return team


def main():
    defaults = json.loads((Path(__file__).resolve().parents[1] / ".cloudflare/project.json").read_text())
    account = os.environ.get("CF_ACCOUNT_ID") or defaults["account_id"]
    project = os.environ.get("CF_PROJECT") or defaults["project_name"]
    token = os.environ.get("CF_API_TOKEN", "")
    email = os.environ.get("CF_ACCESS_EMAIL", "").strip()
    if not token or not email:
        raise ValueError("Save CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCESS_EMAIL in GitHub Repository Secrets; no game upload was attempted")
    if not re.fullmatch(r"[a-fA-F0-9]{32}", account):
        raise ValueError("Invalid Cloudflare account ID")
    team = provision(Cloudflare(account, token), project, email)
    values = {"CF_ACCOUNT_ID": account, "CF_PROJECT": project, "CF_ACCESS_TEAM": team}
    with open(os.environ["GITHUB_ENV"], "a") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")
    print("CLOUDFLARE_SETUP_PASSED")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, urllib.error.URLError) as error:
        print(f"Setup stopped: {error}", file=sys.stderr)
        sys.exit(1)
