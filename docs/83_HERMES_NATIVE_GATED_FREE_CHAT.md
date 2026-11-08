# HERMES native-logic-gated free chat

This is the demo control path: user → HERMES → native NaNLMind → HERMES → user.

The implementation is runner/hermes_free_chat.py. It is separate from the
older stage-selection demonstration in runner/conversation_trainer.py.

## Mandatory logic gate

No HERMES free-chat message is forwarded until the compiled native
nanlm-universal has executed logic-train 32 64 CANDIDATE_STATE.nmg and
reported all of:

- process exit status zero
- stage=boolean_foundation passed=yes correct=1024/1024
- stage=deep_logic_circuits passed=yes correct=32/32
- result=PASS
- a serialized scratch state file

A missing native executable, failed stage, or incorrect pinned SHA-256
blocks chat and teaching. There is no Python math or logic fallback.

## Conversational and explicit learning

After the native gate, the connected Hermes/OpenAI-compatible model handles
ordinary conversational turns. Each turn is recorded in a clocked hash-chained
JSONL transcript. A model reply alone is NOT native NaNLMind learning.

Explicit user teaching uses syntax like:

    /teach penguin|cannot|fly|+|7

The adapter writes a source-bound N16REL/1 record, invokes native
relation-train RECORDS STATE 1, records a verified native status and
before/after scratch digests, then sends that evidence to HERMES to reflect.
Only explicitly labeled training rows can mutate the candidate topology;
an LLM cannot invent teaching labels from ordinary conversation.

## Single canonical state, isolated experimentation

An optional --base-state is copied into the isolated native candidate at
session creation; otherwise the native logic trainer creates a fresh
scratch topology. Nothing in this integration directly overwrites an
existing canonical universe, or bypasses BS0/MC0 merge authority.
Every native teaching result reports canonical_merge_committed=false.

The local monotonic tick is NOT a distributed atomic clock.

Remaining: complete head/branch/leaf tree mutation, a paged 8 MiB native
scratch register API, all-kernel arbitrary-input execution, authorized
BS0/MC0 promotion and global atomic clock agreement.

## CLI

Build the native core:

    make -j2 build/nanlm-universal

Configure a live HERMES-compatible endpoint (do not put credentials in git):

    export NANLM_MODEL_URL=https://YOUR-ENDPOINT/v1
    export NANLM_MODEL=YOUR-MODEL
    export NANLM_MODEL_TOKEN=YOUR-TOKEN
    python3 runner/hermes_free_chat.py --core build/nanlm-universal --interactive

Optionally provide --base-state native/global_universe.nmg to begin from an
existing canonical universe. Omit it if no canonical state exists.
The optional --core-sha256 or NANLM_CORE_SHA256 pins the native executable.

Example session, after the mandatory native logic gate:

    Explain the mathematical tools you can access.
    /teach penguin|cannot|fly|+|7
    What did the native student actually change?
    /quit

Hermes fluency, native scratch relation accuracy and canonical merge
authorization remain independently measured and reported.
