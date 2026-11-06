import io
import json
import os
import tempfile
import unittest
from unittest.mock import patch

from clocked_experience import digest, make_event, summarize_step
from gateway import Gateway


class FakeClocked:
    def pipeline(self, text, steps, on_error):
        return {
            "steps": [
                {"endpoint": "decide", "name": "task_classification", "status": 200,
                 "result": {"answers": {"task_family": "technical_document", "contains_claims": True}}},
                {"endpoint": "extract", "name": "evidence_extraction", "status": 200,
                 "result": {"fields": {"claims": ["private claim"], "dates": ["2026-11-05"]}}},
            ],
            "stopped": False,
            "timing": {"total_ms": 12},
        }


def invoke(app, path, method="GET", payload=None, bearer=None):
    raw = b"" if payload is None else json.dumps(payload).encode("utf-8")
    environ = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "CONTENT_LENGTH": str(len(raw)),
        "wsgi.input": io.BytesIO(raw),
    }
    if bearer:
        environ["HTTP_AUTHORIZATION"] = "Bearer " + bearer
    captured = {}

    def start_response(status, headers):
        captured["status"] = status
        captured["headers"] = headers

    body = b"".join(app(environ, start_response))
    return captured["status"], json.loads(body.decode("utf-8"))


class ClockedExperienceTests(unittest.TestCase):
    def test_digest_is_deterministic(self):
        self.assertEqual(digest({"b": 2, "a": 1}), digest({"a": 1, "b": 2}))

    def test_step_summary_does_not_persist_extracted_values(self):
        summary = summarize_step({
            "endpoint": "extract",
            "status": 200,
            "result": {"fields": {"email": "secret@example.test", "amount": "$42"}},
        })
        self.assertEqual(summary["extracted_field_names"], ["amount", "email"])
        self.assertNotIn("secret@example.test", repr(summary))
        self.assertNotIn("$42", repr(summary))

    def test_event_is_explicitly_not_native_training_commit(self):
        event = make_event("hello", {"steps": []}, object())
        self.assertEqual(event["learning_state"], "awaiting_nanlmind_ingest")
        self.assertFalse(event["raw_text_persisted"])
        self.assertFalse(event["raw_response_persisted"])
        self.assertNotIn("hello", repr(event))


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.tmp.name, "gateway.sqlite3")
        self.app = Gateway(self.db_path, FakeClocked())
        self.env = patch.dict(os.environ, {
            "CLOCKED_TOKEN_PEPPER": "test-only-pepper",
            "CLOCKED_GATEWAY_ADMIN_TOKEN": "admin-test-token",
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.addCleanup(self.tmp.cleanup)

    def issue(self, max_requests=2):
        status, result = invoke(
            self.app, "/admin/tokens", "POST",
            {"tenant_id": "test-tenant", "max_requests": max_requests, "ttl_seconds": 600},
            "admin-test-token",
        )
        self.assertEqual(status, "201 Created")
        self.assertEqual(result["token_type"], "CLOCKED_USER_API")
        return result["token"]

    def test_health_does_not_require_credentials(self):
        status, result = invoke(self.app, "/healthz")
        self.assertEqual(status, "200 OK")
        self.assertEqual(result["protocol"], "nanlm.clocked-experience")

    def test_admin_issues_scoped_token_and_demo_returns_content_minimized_event(self):
        token = self.issue()
        status, result = invoke(
            self.app, "/v1/experience", "POST",
            {"protocol": "nanlm.clocked-experience", "text": "private source text"},
            token,
        )
        self.assertEqual(status, "200 OK")
        self.assertEqual(result["event"]["tenant_id"], "test-tenant")
        self.assertEqual(result["event"]["learning_state"], "awaiting_nanlmind_ingest")
        encoded = json.dumps(result)
        self.assertNotIn("private source text", encoded)
        self.assertNotIn("private claim", encoded)
        self.assertNotIn("2026-11-05", encoded)

    def test_quota_is_enforced(self):
        token = self.issue(max_requests=1)
        status, _ = invoke(self.app, "/v1/experience", "POST", {"text": "one"}, token)
        self.assertEqual(status, "200 OK")
        status, result = invoke(self.app, "/v1/experience", "POST", {"text": "two"}, token)
        self.assertEqual(status, "429 Too Many Requests")
        self.assertEqual(result["error"], "quota_exceeded")

    def test_unknown_token_is_rejected(self):
        status, result = invoke(self.app, "/v1/experience", "POST", {"text": "hello"}, "not-a-token")
        self.assertEqual(status, "401 Unauthorized")
        self.assertEqual(result["error"], "unauthorized")


if __name__ == "__main__":
    unittest.main()
