import unittest

from endpoint_client import make_request, validate_event


class EndpointClientTests(unittest.TestCase):
    def setUp(self):
        self.event = {
            "protocol": "nanlm.endpoint-observation",
            "version": 1,
            "event_id": "a" * 64,
            "base_generation": 4,
            "active_heads": [9, 2, 9],
            "outcome_verified": False,
            "ignored_extra": "must not cross the boundary",
        }

    def test_allowlists_fields_and_deduplicates_heads(self):
        clean = validate_event(self.event)
        self.assertEqual(clean["active_heads"], [2, 9])
        self.assertNotIn("ignored_extra", clean)
        request = make_request("https://example.invalid/v1/observations", "scoped-token", self.event)
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer scoped-token")

    def test_rejects_endpoint_asserted_correctness(self):
        event = dict(self.event, outcome_verified=True, correct=True)
        with self.assertRaisesRegex(ValueError, "cannot assert correctness"):
            validate_event(event)

    def test_rejects_invalid_head_and_generation(self):
        with self.assertRaisesRegex(ValueError, "active_heads"):
            validate_event(dict(self.event, active_heads=[256]))
        with self.assertRaisesRegex(ValueError, "base_generation"):
            validate_event(dict(self.event, base_generation=True))

    def test_rejects_non_sha_event_id(self):
        with self.assertRaisesRegex(ValueError, "event_id"):
            validate_event(dict(self.event, event_id="bad"))


if __name__ == "__main__":
    unittest.main()
