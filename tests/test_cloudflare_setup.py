"""Exercise provisioning, repeat runs, and refusal of unsafe account state offline."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).resolve().parents[1] / "tools/bootstrap-cloudflare.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class FakeCloudflare:
    def __init__(self):
        self.project = {"name": "nodenexus-dev", "production_branch": "production", "source": None}
        self.organization = None
        self.providers = []
        self.apps = []
        self.policies = []
        self.calls = []

    def request(self, method, path, data=None):
        self.calls.append((method, path, copy.deepcopy(data)))
        if path == "/pages/projects/nodenexus-dev":
            if method == "PATCH":
                self.project.update(data)
            if self.project is None:
                raise bootstrap.APIError(404, [8000007])
            return copy.deepcopy(self.project)
        if path == "/pages/projects" and method == "POST":
            self.project = {**data, "source": None}
            return copy.deepcopy(self.project)
        if path == "/access/organizations":
            if method == "POST":
                self.organization = {"auth_domain": "test.cloudflareaccess.com", "name": "NodeNexus"}
            if method == "PUT":
                self.organization.update(data)
            return copy.deepcopy(self.organization)
        if path == "/access/identity_providers" and method == "POST":
            provider = {**data, "id": "otp-id"}
            self.providers.append(provider)
            return copy.deepcopy(provider)
        if path == "/access/apps" and method == "POST":
            app = {**data, "id": f"app-{len(self.apps)}"}
            self.apps.append(app)
            return copy.deepcopy(app)
        parts = path.split("/")
        if len(parts) == 4 and parts[2] == "apps":
            app = next(app for app in self.apps if app["id"] == parts[3])
            if method == "PUT":
                app.update(data)
            return copy.deepcopy(app)
        if parts[2] == "policies":
            if method == "POST":
                self.policies.append({**data, "id": "owner-policy"})
                return copy.deepcopy(self.policies[-1])
            policy = next(item for item in self.policies if item["id"] == parts[3])
            if method == "PUT":
                policy.update(data)
            return copy.deepcopy(policy)
        raise AssertionError((method, path))

    def list(self, path):
        if path == "/access/identity_providers":
            return copy.deepcopy(self.providers)
        if path == "/access/apps":
            return copy.deepcopy(self.apps)
        if path == "/access/policies":
            return copy.deepcopy(self.policies)
        raise AssertionError(path)


class SetupTests(unittest.TestCase):
    def test_first_setup_and_repeat_do_not_duplicate_resources(self):
        api = FakeCloudflare()
        for _ in range(2):
            self.assertEqual(bootstrap.provision(api, "nodenexus-dev", "owner@example.com"), "test.cloudflareaccess.com")
        self.assertEqual(len(api.providers), 1)
        self.assertEqual(len(api.apps), 2)
        self.assertEqual(api.project["production_branch"], "master")
        self.assertEqual({app["domain"] for app in api.apps}, {"nodenexus-dev.pages.dev", "*.nodenexus-dev.pages.dev"})
        self.assertEqual(len(api.policies), 1)
        self.assertEqual(api.policies[0]["decision"], "allow")
        self.assertEqual(api.policies[0]["include"], [{"email": {"email": "owner@example.com"}}])
        self.assertTrue(all(app["policies"] == [{"id": "owner-policy", "precedence": 1}] for app in api.apps))
        self.assertEqual(api.organization["session_duration"], "168h")
        self.assertEqual(api.policies[0]["session_duration"], "168h")
        self.assertTrue(all(app["session_duration"] == "168h" for app in api.apps))

    def test_missing_pages_project_is_created(self):
        api = FakeCloudflare()
        api.project = None
        bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        self.assertEqual(api.project["name"], "nodenexus-dev")

    def test_access_not_enabled_still_creates_the_organization(self):
        api = FakeCloudflare()
        original = api.request
        def disabled_get(method, path, data=None):
            if method == "GET" and path == "/access/organizations" and api.organization is None:
                raise bootstrap.APIError(403, [9999], message="access.api.error.not_enabled: Access is not enabled")
            return original(method, path, data)
        api.request = disabled_get
        bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        self.assertEqual(api.organization["auth_domain"], "test.cloudflareaccess.com")

    def test_other_forbidden_responses_do_not_create_an_organization(self):
        api = FakeCloudflare()
        original = api.request
        def forbidden_get(method, path, data=None):
            if method == "GET" and path == "/access/organizations":
                raise bootstrap.APIError(403, [10000], message="Authentication error")
            return original(method, path, data)
        api.request = forbidden_get
        with self.assertRaises(bootstrap.APIError):
            bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        self.assertIsNone(api.organization)

    def test_invalid_identity_fails_before_any_api_calls(self):
        api = FakeCloudflare()
        for email in ("", "everyone", "a@example.com\nb@example.com"):
            with self.subTest(email=email), self.assertRaises(ValueError):
                bootstrap.provision(api, "nodenexus-dev", email)
        self.assertEqual(api.calls, [])

    def test_unrelated_organization_session_is_not_changed(self):
        api = FakeCloudflare()
        api.organization = {"name": "Other work", "auth_domain": "test.cloudflareaccess.com", "session_duration": "24h"}
        bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        self.assertEqual(api.organization["session_duration"], "24h")

    def test_more_specific_application_blocks_setup(self):
        api = FakeCloudflare()
        api.apps.append({"id": "other", "name": "Unrelated", "domain": "pr-1.nodenexus-dev.pages.dev"})
        with self.assertRaisesRegex(RuntimeError, "overlapping"):
            bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        self.assertFalse(any(path.startswith("/access/apps") and method != "GET" for method, path, _ in api.calls))

    def test_unexpected_allow_everyone_policy_blocks_setup(self):
        api = FakeCloudflare()
        bootstrap.provision(api, "nodenexus-dev", "owner@example.com")
        api.apps[0]["policies"].append({"id": "extra", "name": "Allow everyone"})
        with self.assertRaisesRegex(RuntimeError, "Unexpected Access policies"):
            bootstrap.provision(api, "nodenexus-dev", "owner@example.com")

    def test_ignored_email_policy_is_not_success(self):
        api = FakeCloudflare()
        original = api.request
        def unsafe_response(method, path, data=None):
            result = original(method, path, data)
            if path == "/access/policies/owner-policy" and method == "GET":
                result["include"] = [{"everyone": {}}]
            return result
        api.request = unsafe_response
        with self.assertRaisesRegex(RuntimeError, "exact owner-only policy"):
            bootstrap.provision(api, "nodenexus-dev", "owner@example.com")


if __name__ == "__main__":
    unittest.main()
