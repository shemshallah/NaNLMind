# NaNLMind-side CLOCKED interface

The upstream CLOCKED SDK client, API gateway, credentials, demo harness and service tests are owned by [NaNLMind_CLOCKED](https://github.com/shemshallah/NaNLMind_CLOCKED).

This directory retains only the receiving-language contract and native learner-side integration:

- `protocol.schema.json` — canonical CLOCKED experience observation envelope.
- `endpoint-observation.schema.json` — canonical hardware-neutral NANNET observation envelope.
- `endpoint_client.py` — scoped publisher for the NaNLMind observation interface; it never calls the upstream CLOCKED SDK.
- `native_demo.cpp` — native NaNLMind head/routing experiment compiled against NaNLMind APIs.
- `training_endpoints.json` — canonical topology and endpoint ownership registry.

NaNLMind also owns the durable evidence consumer, Boolean heads, M0-M9 transformations, relation learner, six-runner ring and canonical generation commits. CLOCKED supplies external typed observations only.

See the [CLOCKED/NANNET receiving-side bridge](../../docs/73_CLOCKED_NANNET_BRIDGE.md), [chainable training contract](../../specs/CLOCKED_CHAINABLE_TRAINING.md), and [HERMES autonomous CLOCKED/head-cortex design](https://github.com/shemshallah/NaNLMind_CLOCKED/blob/main/docs/HERMES_AUTONOMOUS_CLOCKED_HEAD_CORTEX.md).
