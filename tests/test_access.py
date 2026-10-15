"""Security regression checks for the pre-upload Access gate (no remote calls)."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("access", Path(__file__).resolve().parents[1] / "tools/check-access.py")
access = importlib.util.module_from_spec(spec)
spec.loader.exec_module(access)


class Response:
    def __init__(self, code, location=""):
        self.code = code
        self.headers = {"Location": location}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


class AccessGateTests(unittest.TestCase):
    def check_response(self, response):
        opener = Mock()
        opener.open.side_effect = lambda *args, **kwargs: response
        with patch.object(access.urllib.request, "build_opener", return_value=opener):
            access.check("https://pr-1.example.pages.dev", "example.cloudflareaccess.com", attempts=1)
        return opener

    def test_access_login_is_required_for_each_asset(self):
        opener = self.check_response(Response(302, "https://example.cloudflareaccess.com/cdn-cgi/access/login/pr-1.example.pages.dev"))
        self.assertEqual(opener.open.call_count, 4)
        self.assertEqual([call.args[0].full_url.rsplit("/", 1)[-1] for call in opener.open.call_args_list], ["", "index.wasm", "index.pck", "build-info.json"])

    def test_public_content_and_generic_denials_block_upload(self):
        for code in (200, 401, 403, 404, 500):
            with self.subTest(code=code), self.assertRaises(RuntimeError):
                self.check_response(Response(code))

    def test_wrong_team_and_non_access_redirects_block_upload(self):
        for target in ("https://other.cloudflareaccess.com/cdn-cgi/access/login/example", "https://example.cloudflareaccess.com.evil.test/cdn-cgi/access/login", "https://example.cloudflareaccess.com/", "http://example.cloudflareaccess.com/cdn-cgi/access/login"):
            with self.subTest(target=target), self.assertRaises(RuntimeError):
                self.check_response(Response(302, target))


if __name__ == "__main__":
    unittest.main()
