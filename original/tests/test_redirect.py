import pathlib
import sys
import unittest
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
import matchday


class UnreadableBody:
    def __init__(self):
        self.closed = False

    def read(self, *args):
        raise AssertionError("a redirect body must never be read")

    def close(self):
        self.closed = True


class Destination:
    def open(self, request, timeout):
        return request.full_url, timeout


class RedirectTests(unittest.TestCase):
    def setUp(self):
        self.handler = matchday.BodylessRedirectHandler()
        self.handler.parent = Destination()

    def test_each_redirect_skips_body_and_follows_location(self):
        for code in (301, 302, 303, 307, 308):
            with self.subTest(code=code):
                body = UnreadableBody()
                request = urllib.request.Request("https://example.com/old")
                request.timeout = 3
                result = getattr(self.handler, f"http_error_{code}")(
                    request, body, code, "redirect", {"Location": "/new"}
                )
                self.assertEqual(result, ("https://example.com/new", 3))
                self.assertTrue(body.closed)

    def test_https_downgrade_is_rejected_without_reading_body(self):
        body = UnreadableBody()
        request = urllib.request.Request("https://example.com/old")
        with self.assertRaisesRegex(ValueError, "insecure redirect"):
            self.handler.http_error_302(
                request, body, 302, "redirect", {"Location": "http://example.com/new"}
            )
        self.assertTrue(body.closed)


if __name__ == "__main__":
    unittest.main()
