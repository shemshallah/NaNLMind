# NaNLMind CLOCKED interface boundary

The CLOCKED service implementation lives in the dedicated repository:
https://github.com/shemshallah/NaNLMind_CLOCKED

This directory retains only NaNLMind-side interface material:
- `endpoint-observation.schema.json`: generic authenticated endpoint observation contract consumed by the NaNLMind evidence intake.
- `endpoint_client.py`: standard-library publisher for the NaNLMind observation intake; it does not call the CLOCKED SDK.
- `native_demo.cpp`: native learner demonstration using the NaNLMind head/evidence implementation.
- `training_endpoints.json`: canonical NaNLMind endpoint/learner registry.

The native bridge, observation validation, evidence ledger, Boolean head mapping, and canonical training admission remain owned by NaNLMind. CLOCKED credentials, SDK calls, endpoint orchestration, service gateway, and CLOCKED-specific tests belong in NaNLMind_CLOCKED.

HERMES integration is intentionally deferred until the CLOCKED service and this native interface have passed their independent tests.
