# Clocked as a Chainable NaNLMind Training Resource

**Status:** Architecture plan; the local native demo is implemented separately  
**Owner:** NaNLMind canonical six-runner training ring  
**External service:** CLOCKED API, implemented and operated from [NaNLMind_CLOCKED](https://github.com/shemshallah/NaNLMind_CLOCKED); NaNLMind consumes only the versioned native evidence interface  
**Endpoint identity:** `nan:/GM0:SC0:MC0:BS0:HW3` (Clocked demo endpoint)  
**Canonical-state rule:** Clocked is an evaluator/experience provider, never the owner of NaNLMind weights, heads, routes, or generations.

## 1. Purpose

Make Clocked a reusable, chainable task-and-evidence resource for the NaNLMind training system. A chain is a versioned directed acyclic graph (DAG) of bounded operations. Each operation consumes explicitly declared inputs and produces a typed, content-addressed artifact. The next operation may consume that artifact only after schema, provenance, policy and validation checks pass.

Clocked can supply task classification, structured extraction, decision judgments, privacy/safety signals, grounding, comparison and reranking. These outputs can help build curricula, label candidate tasks, measure agreement, identify ambiguity and select useful examples. They are **not automatically ground truth** and must not be treated as model gradients or correctness labels.

The chainable design must preserve these invariants:
- one canonical NaNLMind topology, one canonical training generation and one authoritative commit path;
- the six-runner ring remains the primary learner and owns the 256-head state;
- Overbootstrap aggregates endpoint evidence and produces bounded policy/curriculum feedback;
- Clocked remains endpoint HW3 and cannot submit head deltas, active-head claims, correctness labels or generation commits;
- raw source text is not retained in the default observation/event path;
- every imported training example has source provenance, license/consent, validation status, deterministic identity and a replayable lineage.

## 2. What the working demo proves

The companion demo in `NaNLMind_CLOCKED/integrations/clocked/demo.py` exercises a deliberately small path:

1. Read a versioned, labelled synthetic task-family curriculum with separate train and held-out splits.
2. In live mode, submit each sample to the authenticated Clocked gateway, which invokes the server-side Clocked SDK. In fixture mode, use a deterministic local stand-in and label the result as simulated.
3. Extract the allowlisted `task_family` label from the content-minimized Clocked event.
4. Compare the Clocked label with an independent gold label supplied by the demo dataset.
5. Admit only gold-matched training examples to the native learner. Mismatches receive no training credit.
6. Run a native C++ Hopfield routing-memory demonstration and fold verified Clocked events into `OverbootstrapLearner`.
7. Apply bounded evidence feedback to routing biases and replay a held-out split.
8. Emit metrics and a minimized event log without storing source text in that event log.

The native demo uses transparent lexical anchor features for six task families. It demonstrates the mechanics of verified teacher-label admission, native head activation, routing-memory learning, Overbootstrap evidence and held-out replay. It is **not** a general language-model benchmark, a proof that Clocked is always correct, or a claim that Clocked has trained the production NaNLMind model. Live mode requires a configured Clocked API key on the gateway and a scoped participant token. CI uses fixture mode and makes no paid Clocked calls.

## 3. Chain model

### 3.1 Chain definition

A chain definition is immutable once a run starts. It contains:
- `chain_id`, semantic version and schema version;
- ordered operation nodes and typed input/output contracts;
- pinned Clocked endpoint/method configuration (not credentials);
- pinned prompt/instruction templates and allowlisted output fields;
- validation rules and independent evaluator references;
- dataset and artifact digests;
- resource budgets: maximum records, bytes, concurrency, Clocked credits/cost and wall time;
- retry policy and idempotency scope;
- privacy, retention and licensing policy;
- target canonical generation and required minimum generation/manifest compatibility.

A chain run gets a unique `run_id`. Each operation gets an `operation_id` and a content-derived `operation_key` computed from the operation version, canonical input artifact digests and effective non-secret configuration. Repeating the same operation key must return the existing durable result rather than run/bill again where the upstream API's idempotency contract permits it.

### 3.2 Initial operation vocabulary

| Operation | Clocked capability | Purpose | Output trust |
|---|---|---|---|
| `CLASSIFY` | Decide | Task family, intent and bounded labels | Candidate label |
| `EXTRACT` | Extract | Field names and bounded evidence spans/values for an explicitly approved workflow | Unverified extracted evidence |
| `GUARD` | Injection / script safety | Detect hostile or unsafe inputs and gate later operations | Safety signal, not proof of safety |
| `PRIVACY_SCAN` | PII | Detect sensitive-data presence and enforce retention policy | Privacy metadata |
| `GROUND` | Grounding | Check answer claims against declared documents | External verification signal |
| `COMPARE` | Compare | Detect duplicates, disagreements and conflicts between examples | Comparison evidence |
| `RERANK` | Rerank | Select the most relevant examples for a task/curriculum | Ranking signal |
| `DECIDE` | Decide | Evaluate an explicitly defined question against a sample | Candidate decision |
| `HUMAN_REVIEW` | Internal reviewer | Resolve ambiguous, high-impact or disagreement cases | Human-reviewed outcome |
| `EVALUATE` | Native evaluator | Score NaNLMind predictions against held-out gold or deterministic task checks | Training/evaluation authority |
| `FOLD_EVIDENCE` | Native Overbootstrap | Deduplicate and aggregate trusted endpoint evidence | Bounded meta-learning feedback |
| `TRAIN` | Canonical six-runner ring | Apply accepted curriculum/update under generation control | Candidate canonical generation |
| `REPLAY` | Native evaluator | Run fixed held-out and regression suites against candidate generation | Promotion evidence |
| `COMMIT` | Canonical ring barrier | Atomically publish the next generation and ledger receipt | Canonical state transition |

The operation graph is a DAG, not an arbitrary script. Each node has bounded input size, output schema, timeout and retry budget. A failed guard can stop downstream processing. A failed optional operation may be marked skipped only where the chain policy explicitly permits it.

### 3.3 Example chain

```text
licensed sample / synthetic task
            |
            v
      PRIVACY_SCAN
            |
            v
          GUARD
        /       \
    blocked    allowed
       |          |
   quarantine   CLASSIFY
                  |
                EXTRACT
                  |
             independent EVALUATE
                  |
          +-------+--------+
          |                |
       mismatch          match
          |                |
   evidence only       verified sample
                           |
                        RERANK
                           |
                     curriculum batch
                           |
                    six-runner TRAIN
                           |
                    held-out REPLAY
                           |
                 Overbootstrap FOLD
                           |
                generation barrier/COMMIT
```

The graph is illustrative. In particular, `EXTRACT` output is not automatically a target label; `GROUND` output is not automatically a correctness oracle; and a Clocked result never bypasses `EVALUATE` or an authorized human-review path.

## 4. Trust and evidence lifecycle

Use three separate trust levels:

1. **Observed:** authenticated endpoint call and content-minimized result. The endpoint identity is assigned by the server. No correctness credit.
2. **Validated:** schema, provenance, license/consent, generation compatibility, deduplication and policy checks pass. This permits controlled use as a candidate example, but does not by itself prove the answer is correct.
3. **Verified:** an independent gold label, deterministic evaluator, trusted human review or an approved cross-check establishes the outcome. Only this level may contribute correctness evidence or a training target.

A Clocked response can be internally consistent and still be wrong. Agreement between two Clocked operations is not independent verification if both rely on the same upstream model or evidence. Verification should use a separate source: held-out gold, executable tests, authoritative source documents, domain review or a different independently justified evaluator.

The native `EndpointEvidenceFold` accepts authenticated endpoint identity, stable event ID, base generation, native active-head trace and verified outcome. The gateway must not accept client-supplied `correct`, `outcome_verified`, active heads, head vectors or deltas as trusted facts. The runner reconstructs model traces from the actual native inference and joins them to a server-verified event.

Unverified Clocked calls may contribute to counts, latency, cost, coverage, disagreement and task-distribution analysis. They do not change correctness reliability, head bias or canonical model state.

## 5. Chainable artifacts and lineage

Use content-addressed artifacts and append-only run receipts. Suggested artifact kinds:

- `source_manifest`: dataset identity, license, provenance, consent, source digest and retention class;
- `clocked_observation`: minimized event schema, endpoint ID, request/response digests, Clocked version, method, timing and credit/cost metadata;
- `candidate_label`: allowlisted label, confidence/evidence metadata if provided, and the independent gold/evaluator reference;
- `validated_example`: normalized input digest, target, task family, validator identity and validation receipt;
- `curriculum_batch`: ordered example IDs, selection policy version, split membership and batch digest;
- `native_trace`: model generation, input digest, actual active-head trace, prediction, abstention, route and native runtime version;
- `training_delta`: base generation, worker/runner identity, bounded update packet digest and idempotency key;
- `replay_report`: fixed benchmark version, split digest, per-task metrics, baseline/candidate comparison and regression flags;
- `commit_receipt`: old/new generation, ledger event, manifest digest and committed artifact IDs.

Artifacts must include schema version, canonical serialization rules and cryptographic digest. A run manifest links each artifact to its parent operation keys. Never use timestamps alone as artifact identity. Never overwrite a prior artifact when a prompt, model version, source dataset, validation rule or native learner changes; produce a new version and retain the prior receipt according to retention policy.

## 6. Durable execution and chain replay

A chain runner should be a durable state machine:
- `QUEUED`
- `RUNNING`
- `WAITING_FOR_REVIEW`
- `VALIDATING`
- `READY_FOR_TRAINING`
- `TRAINING`
- `REPLAYING`
- `COMMITTING`
- `COMMITTED`
- `REJECTED`, `FAILED`, `CANCELLED`

Every transition is compare-and-swap against a run generation. Store operation inputs/outputs by digest, with bounded retries and a durable idempotency receipt. On restart, reconcile incomplete operations from receipts; do not blindly reissue billable Clocked calls. If the upstream result cannot be recovered, mark the operation as uncertain and require explicit retry-as-new behavior rather than silently double-charge.

Clocked's SDK supports idempotency for its own retry attempts. The gateway must also implement caller-level idempotency across client retries: persist the request key, tenant/token scope, request-body digest, status and minimized response. Reuse of a key with a different body must return conflict. A completed request key must replay its stored response without consuming quota or calling Clocked again. This gateway feature is a prerequisite for reliable long-running chains.

## 7. Canonical training integration

The NANNET intake/validator boundary and the six-runner ring have distinct roles:

- Clocked gateway stores minimized external observations and assigns endpoint HW3 identity.
- NANNET stores quarantined corpus packages and observations, enforces quotas and scopes, and exposes only validated items to the runner.
- A trusted validator checks provenance, licensing, format, policy and any independent labels.
- The six-runner ring retrieves validated batches, recomputes native traces, evaluates candidate labels and prepares generation-bound deltas.
- The ring's prepare/barrier/commit cycle validates all six runner packets and atomically advances the single canonical generation.
- Overbootstrap folds verified cross-endpoint trace evidence and emits bounded policy/curriculum recommendations for a later canonical training cycle.

Do not treat the generic NANNET byte-trigram corpus consumer as a replacement for the native C++ learner. It is a deterministic intake/feature prototype. The production chain must route validated examples into the repository's actual native training APIs, serialize/checkpoint the resulting candidate state, run held-out replay, and publish a canonical ledger commit. A merge receipt from an intake service is not proof that the C++ model snapshot was updated.

### 7.1 Generation safety

Each training batch pins a `base_generation` and base manifest digest. If either changes before prepare, the batch is stale and must be rebased/re-evaluated. A commit receipt must bind:
- previous generation and manifest digest;
- new generation and manifest digest;
- all six runner packet digests and runner identities;
- validated curriculum artifact digest;
- replay report digest and promotion policy;
- idempotency key and ledger event ID.

No Clocked API, gateway, participant or external runner has permission to commit the canonical generation.

## 8. Training and evaluation policy

### 8.1 Data separation

Split by source, template family, time window and semantic duplicate cluster—not just random row split. Keep a fixed held-out evaluation set that Clocked never sees during prompt tuning or curriculum selection. Avoid leakage from repeated templates or near-duplicate documents across train and test.

### 8.2 What Clocked can contribute

- Task family and task-intent candidates.
- Candidate structured fields and evidence locations.
- Safety/privacy flags for gating and routing.
- Candidate comparison and duplicate/conflict signals.
- Reranking signals for curriculum selection.
- External evaluation traces, timing and cost measurements.
- Disagreement/uncertainty indicators that select examples for human review.

### 8.3 What Clocked cannot decide alone

- Whether its own answer is correct.
- Whether a training example is licensed or consented.
- Whether an external claim is true without authoritative evidence.
- Which NaNLMind heads should be updated.
- Whether a candidate model generation should be committed.
- Whether a model improvement generalizes beyond the held-out benchmark.

### 8.4 Promotion gates

Promote a candidate generation only when:
- all six runner packets are valid and generation-compatible;
- every training example has accepted provenance/license/consent metadata;
- no unverified Clocked label was used as a correctness target;
- held-out performance improves on the pre-registered primary metric;
- no critical task family or safety metric regresses beyond its declared tolerance;
- duplicate/replay/idempotency tests pass;
- artifact lineage and replay are complete;
- the canonical barrier produces one durable commit receipt.

Report accuracy, coverage, abstention, calibration where available, per-family confusion, latency, cost/credit, and source-specific performance. Include sample counts and confidence intervals. A demo's 100% on a tiny synthetic set is a pipeline demonstration, not a production quality claim.

## 9. Security, privacy and cost controls

- The upstream Clocked key exists only in the gateway's server-side secret manager.
- Participants receive short-lived scoped gateway tokens, never the upstream key, admin token, runner token or bootstrap token.
- Admin, validator, runner and canonical commit credentials remain separate.
- Never place secrets in chain definitions, artifact metadata, logs, command-line arguments, source files or demo outputs.
- Store minimized observations by default; raw source retention requires explicit policy, license/consent and an approved protected storage path.
- Apply PII scanning before persistence and before any downstream sharing, but do not assume one pipeline step's anonymized result sanitizes later steps; Clocked pipeline steps operate on their own declared inputs.
- Bound records, bytes, concurrency, retries, timeouts, credits and cost per tenant and per chain run.
- Persist cost basis and credit usage as accounting metadata, not as a quality label.
- Require an explicit approval for large batch runs and any chain that sends sensitive or proprietary content to an external service.

## 10. Longer-term implementation sequence

### Stage A — Hackathon demo (current priority)

- Keep the existing server-side Clocked gateway and participant token model.
- Build and run the native C++ task-family routing demo.
- Validate Clocked predictions against independent gold labels before native training.
- Show baseline abstention, verified training, bounded Overbootstrap feedback and held-out replay.
- Provide fixture-mode CI and a live mode for a configured gateway.
- Clearly label fixture results as simulated and live results with Clocked event IDs/cost metadata.

### Stage B — Durable Clocked event consumer

- Add caller-level idempotency to the gateway.
- Persist Clocked experience events in a durable inbox with tenant, endpoint HW3, schema, event digest and request receipt.
- Add runner-only poll/ack with lease/claim semantics; admin polling must not be the production consumer protocol.
- Reconstruct native active-head traces in the runner; ignore client-supplied head data.
- Persist native Overbootstrap state/checkpoints and event-id dedup across process restarts.
- Acknowledge the gateway/NANNET event only after a durable native fold receipt exists.

### Stage C — Validated task and corpus chains

- Add versioned DAG definitions and operation execution receipts.
- Connect NANNET quarantine/validator datasets to the Clocked operation graph.
- Support human review and independent deterministic evaluators.
- Add dataset provenance/license checks, semantic deduplication, source-separated splits and replayable curriculum artifacts.
- Run bounded Clocked batches with explicit credit/cost budgets and retry receipts.

### Stage D — Canonical ring integration

- Implement a native runner-ring consumer that converts validated examples into actual repository training API calls.
- Add generation-bound six-runner packet preparation, barrier verification, rollback and commit receipts.
- Persist the candidate native model snapshot and its digest.
- Route Overbootstrap feedback into the next ring cycle only as bounded, versioned policy/curriculum input.
- Benchmark ring-only, Clocked-assisted and multi-endpoint curricula on fixed held-out sets.

### Stage E — Chainable training resource

- Allow one chain's validated output to become the next chain's immutable input artifact.
- Support reusable task-family curricula, evaluation suites, safety filters and dataset builders.
- Add scheduling across the six-runner ring and approved endpoint workers.
- Add resource quotas, priority/fairness, cancellation, recovery and cost attribution.
- Introduce signed chain manifests and reproducible replay bundles.
- Consider community-contributed compute only after identity, data confidentiality, execution integrity and generation fencing are independently qualified.

## 11. Acceptance checklist

A release may claim **working Clocked demo** only when:
- [ ] CI compiles the native C++ demo and passes existing endpoint-evidence tests.
- [ ] Fixture mode completes end-to-end and is explicitly labelled simulated.
- [ ] Live mode successfully calls the configured Clocked gateway using a scoped token.
- [ ] Clocked result is checked against independent gold labels.
- [ ] Mismatched or missing labels never enter the native training set.
- [ ] Native baseline and held-out replay metrics are reported.
- [ ] Overbootstrap counts verified Clocked evidence and applies bounded feedback.
- [ ] Event log contains no raw source text, raw extraction values or credentials.
- [ ] The README distinguishes demo-local learning from canonical production commits.

A release may claim **canonical chainable training** only after Stage D has durable six-runner integration, checkpoint recovery, replayable lineage and a generation/ledger commit receipt. Until then, do not say that Clocked is training the live canonical model.

## 12. Upstream API reference

The current Python SDK package is `clocked-sdk` (not the unrelated `clocked` package), imported as `clocked_sdk`. Pin the tested version in the gateway requirements. The SDK documents Decide, Extract, Fill, PII, Injection, Script, Grounding, Compare, Rerank and Pipeline operations, request idempotency, model timing and credit/cost metadata.

- SDK package and API usage: https://pypi.org/project/clocked-sdk/
- NaNLMind Clocked adapter: `integrations/clocked/`
- Canonical topology: `docs/72_CANONICAL_TRAINING_UNIVERSE.md`
- NANNET universal intake: `integrations/nannet/` (separate companion integration)


## Repository ownership boundary

The upstream CLOCKED SDK adapter, gateway, participant client, demo harness, sample corpus, SDK requirements and service tests live in [NaNLMind_CLOCKED](https://github.com/shemshallah/NaNLMind_CLOCKED). This repository retains only the NaNLMind receiving contract, endpoint publisher, native head demo, durable evidence consumer and canonical training topology. The CLOCKED service cannot mutate NaNLMind heads or commit a generation. See the [autonomous HERMES/head-cortex design](https://github.com/shemshallah/NaNLMind_CLOCKED/blob/main/docs/HERMES_AUTONOMOUS_CLOCKED_HEAD_CORTEX.md).
