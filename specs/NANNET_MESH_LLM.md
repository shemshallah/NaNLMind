# NANNET Mesh-LLM Cluster Universe
## Technical architecture proposal

**Status:** Proposed architecture; not yet implemented  
**Target repository:** `shemshallah/NaNLMind`  
**Target path:** `specs/NANNET_MESH_LLM.md`  
**Primary integration:** [Mesh-LLM](https://github.com/Mesh-LLM/mesh-llm) and its Skippy execution runtime  
**Scope:** Bootstrap-universe experiment, one control-plane orchestrator, up to 255 registered GPU worker slots per cluster

---

## 1. Executive summary

This proposal adds a **Cluster Universe** as a managed compute environment inside the NANNET bootstrap universe. A cluster has one logically authoritative **orchestrator service** and up to **255 worker slots**. A worker slot represents one enrolled compute node; it is not a promise that every slot is occupied, that every node contains exactly one physical GPU, or that 255 GPUs can be treated as one coherent device.

Mesh-LLM supplies the distributed inference data plane and model-execution capabilities. Its current architecture combines:
- Mesh node discovery, peer membership, encrypted QUIC transport (through iroh), gossip and request routing;
- an OpenAI-compatible inference surface, normally on `:9337/v1`;
- a management API, normally on `:3131`;
- Skippy, which owns model loading, native inference and package-backed layer-stage execution for supported model architectures.

NANNET remains the authority and policy layer. It owns global identity, device enrollment, authorization, cluster membership, scoped credentials, quotas, leases, lifecycle policy and the public API boundary. Mesh-LLM must not become a second identity authority and must not be allowed to mint or broaden NANNET credentials.

The orchestrator is an **operational control-plane coordinator**, not a semantic coordinator for NaNLMind's global topology. This distinction is mandatory. NaNLMind's existing one-global-topology principle remains intact: clusters are execution/resource placements and test boundaries, not independent minds, histories or competing global ledgers. Cluster-local operational state (membership, reservations, deployments and health) is allowed; authoritative semantic state remains governed by the existing global ledger and commit rules.

The first milestone is deliberately small: create one cluster, enroll two real workers where available, run a supported inference workload, and exercise a 255-slot simulated membership/failure test. A 255-node simulation validates control-plane scale; it does not establish 255-GPU inference performance.

## 2. Goals and non-goals

### 2.1 Goals

1. Establish a reproducible Cluster Universe that can be created, inspected, drained and destroyed through NANNET.
2. Support one orchestrator plus 0–255 enrolled worker slots per cluster.
3. Authenticate each device independently and authorize it for a specific cluster and role.
4. Keep authority-master material exclusively in the trusted authority environment.
5. Use Mesh-LLM/Skippy for supported peer networking, inference routing and distributed layer execution rather than reimplementing those systems.
6. Make worker capability, model placement, health, reservations and resource accounting observable.
7. Handle worker loss, stale membership, duplicate enrollment, credential revocation, orchestrator restart and partial model deployment safely.
8. Test the control plane at 255 simulated workers before claiming physical scale.
9. Preserve NaNLMind's single-global-topology, single-ledger and immutable-generation invariants.

### 2.2 Non-goals

- Claiming that 255 GPUs form one hardware GPU or one shared VRAM address space.
- Assuming linear speedup from adding workers.
- Treating parameter count or summed VRAM as sufficient proof that a model can be split.
- Replacing Mesh-LLM's model runtime, Skippy's stage protocol, or its supported-architecture checks.
- Making Android/Termux a prerequisite for the initial GPU worker. Android can participate as a NANNET client or a separately qualified CPU/lightweight worker.
- Giving guest workers the authority master, GitHub repository credentials, deployment secrets or unrestricted orchestrator access.
- Creating a separate semantic universe, ledger, training history or independent NaNLMind identity for every cluster.
- Claiming hardware attestation, trusted execution, or anti-Sybil guarantees unless a concrete platform mechanism has been implemented and verified.

## 3. Terminology and capacity model

| Term | Definition |
|---|---|
| Bootstrap Universe | The NANNET environment that creates and tests managed resources. |
| Cluster Universe | A named, versioned compute allocation containing one orchestrator identity and up to 255 worker slots. |
| Orchestrator | The trusted NANNET service that reconciles desired cluster state, authorizes workers, assigns slots, enforces policy and observes Mesh-LLM. |
| Worker | An enrolled host running a NANNET worker agent and a compatible Mesh-LLM node/runtime. |
| Worker slot | A cluster-local integer in the range 1–255. A slot is an allocation, not a hardware identity. |
| Node identity | A cryptographic identity bound to a device enrollment record. It must not be derived from a MAC address alone. |
| Mesh identity | Mesh-LLM's transport/peer identity, explicitly bound to an authorized NANNET enrollment. |
| Model deployment | A versioned desired placement of one model or its supported execution stages across workers. |
| Lease | A bounded, revocable authorization to occupy a slot or perform a particular operation. |

**Capacity rule:** the number 255 is a NANNET product-level limit for worker slots in one cluster. It is not a Mesh-LLM protocol limit and must not be represented as one. A cluster may have fewer than 255 workers, may leave slots empty, and may allocate multiple GPUs to one worker host if the worker agent can report and manage them accurately. The initial implementation should use one worker enrollment per host and report individual GPU devices as resources beneath that host.

The orchestrator is a separate logical service and does not consume one of the 255 worker slots. A standby orchestrator may be introduced later, but it must share the same durable authority state and fencing protocol rather than create a second writable control plane.

## 4. System context and responsibility boundaries

### 4.1 Component responsibilities

| Component | Owns | Must not own |
|---|---|---|
| NANNET Authority | Root trust, authority master, credential derivation policy, authorization decisions | GPU scheduling details or model execution |
| Bootstrap Universe | Creation/test lifecycle, experiment policy, test fixtures and reports | A competing identity root |
| Cluster Orchestrator | Cluster desired state, worker-slot assignment, leases, quotas, deployment reconciliation, health aggregation | Authority master; independent semantic history |
| NANNET Worker Agent | Device key, enrollment proof, local inventory, resource telemetry, local process lifecycle | Global authority or cluster-wide policy |
| Mesh-LLM | Peer discovery, encrypted peer transport, routing, mesh runtime and management surfaces | NANNET enrollment decisions or NANNET root credentials |
| Skippy | Model preparation/loading, native execution, supported staged model splits and stage protocol | NANNET identity or cluster admission |
| Inference Gateway | Authenticated client API, tenant/role checks, rate limits, routing to a cluster endpoint | Direct worker enrollment or secret derivation |
| NaNLMind global state | Existing global topology, canonical semantic ledger/digest and commit invariants | Per-cluster semantic forks |

### 4.2 Logical topology

```text
                         NANNET AUTHORITY
                   root trust / credential derivation
                                  |
                         Bootstrap Universe
                                  |
                    Cluster Orchestrator (control)
                    /       |        |         \
             Registry   Scheduler  Leases   Reconciler
                    \       |        |         /
                      NANNET Worker Agents
                         |      |      |
                       W001   W002   ... W255
                         |      |          |
                    Mesh-LLM peer/data plane (QUIC)
                         |      |          |
                    Skippy local or staged execution
                                  |
                       Cluster inference endpoint
                                  |
                      NANNET authenticated gateway
                                  |
                         authorized clients/apps
```

This diagram separates the NANNET control plane from Mesh-LLM's peer/inference data plane. The orchestrator may request and verify lifecycle changes through supported Mesh-LLM management interfaces, but it should not proxy every inference token or activation through itself. Large model-stage traffic should flow over the Mesh-LLM data plane wherever the product's supported topology permits.

### 4.3 Control-plane coordinator versus global semantic coordinator

The orchestrator is authoritative for operational questions such as:
- Which cluster exists?
- Which enrolled worker occupies slot 17?
- Is that worker currently authorized and leased?
- Which model deployment is desired?
- Which workers are healthy and eligible for placement?

It is not authoritative for semantic truth in the NaNLMind global object. It cannot create a second global ledger, silently rewrite committed state, or assign a private history to a cluster. If a future training job emits semantic updates, those updates must enter the existing validated global commit path with base hashes, idempotency keys, leases and ledger events. The cluster is compute placement, not a new source of truth.

## 5. Identity, enrollment and credential security

### 5.1 Authority master

The existing `NANNET_AUTHORITY_MASTER_KEY` remains the root secret and must remain exactly as currently provisioned. The architecture must not rotate, rewrite, print, log, expose through an API, or copy this value into worker configuration as part of this proposal. It is held only by the trusted authority environment or an approved secret manager.

All operational credentials are derived from the authority root using a reviewed, domain-separated KDF/MAC construction. A recommended design is HKDF-SHA-256 with explicit, versioned context labels and stable identifiers. If the existing implementation uses a different reviewed derivation construction, document and preserve that implementation rather than introducing a parallel scheme.

Conceptual derivation domains:

- `nannet/v1/admin/<principal-id>/<scope>`
- `nannet/v1/guest/<enrollment-id>/<cluster-id>/<scope>`
- `nannet/v1/worker/<device-id>/<cluster-id>/<lease-epoch>`
- `nannet/v1/mesh-binding/<device-id>/<cluster-id>/<mesh-key-id>`

The labels above define separation of purpose, not a demand that long-lived bearer tokens be deterministic. Prefer short-lived signed credentials or random opaque tokens whose issuance is authorized by a key derived in the appropriate domain. Never derive a guest credential in the admin domain or let a worker credential authenticate as an administrator.

### 5.2 Device identity is not a MAC address

A MAC address is mutable, can be randomized, can be cloned, and is not a reliable cryptographic identity. It may be retained as optional, privacy-reviewed diagnostic metadata, but it must not be the sole identity key or the sole duplicate-device defense.

On first enrollment, the worker agent creates or uses a device-held asymmetric key pair. The private key should be non-exportable where the platform supports it; otherwise protect it with OS permissions and clearly record the weaker assurance level. The authority issues a device enrollment record binding the public key to:
- a stable NANNET device ID;
- enrollment status and assurance level;
- permitted owner/tenant and cluster scope;
- approved worker role and resource policy;
- creation, expiry and revocation metadata.

The worker proves possession by signing a fresh authority challenge. Re-enrollment with a different MAC must not silently create a new device identity. A legitimate key replacement requires an explicit recovery/re-enrollment path that revokes or supersedes the old key. A copied repository or cloned software image must not inherit an already enrolled private key.

Hardware attestation may strengthen assurance on platforms that support it, but is optional and must be represented explicitly as verified, unavailable or failed. Self-reported hardware inventory is useful for scheduling but is not proof of physical hardware identity.

### 5.3 Admission lifecycle

Recommended lifecycle:

`DISCOVERED -> CHALLENGED -> ENROLLED -> AUTHORIZED -> LEASED -> ACTIVE`

Additional terminal/intermediate states:

`QUARANTINED`, `DRAINING`, `SUSPENDED`, `REVOKED`, `EXPIRED`, `OFFLINE`, `REJECTED`.

Admission sequence:

1. Worker contacts the NANNET enrollment endpoint over authenticated TLS.
2. Authority returns a single-use, short-expiry challenge bound to the requested cluster and enrollment attempt.
3. Worker signs the challenge with its device key and submits public-key and platform evidence.
4. Authority validates proof, policy, existing enrollment and duplicate/recovery rules.
5. Authority creates or resumes the device record and issues a short-lived, cluster-scoped guest/worker credential.
6. Orchestrator reserves an available slot and creates a lease with a monotonically increasing epoch/fencing token.
7. Worker starts or joins the configured private Mesh-LLM mesh using the authorized Mesh identity/invite mechanism.
8. Orchestrator verifies that the connected Mesh peer maps to the enrolled device and authorized slot before marking it ACTIVE.
9. Worker publishes inventory and heartbeats; it receives only the capabilities needed for its role.

A Mesh peer that appears before NANNET authorization remains quarantined from cluster workloads. Mesh-LLM's own peer admission is not a substitute for NANNET admission.

### 5.4 Credential scope and revocation

- Admin credentials are derived/issued in an admin-only domain and never distributed to workers.
- Guest credentials are bound to an enrollment, cluster, role, scope, expiry and key ID.
- Worker credentials authorize only the worker's own heartbeat, inventory, assigned job, and permitted Mesh binding.
- Slot leases are separate from device identity. A device can remain enrolled while its cluster lease is released.
- Revocation invalidates NANNET API access immediately and triggers Mesh peer removal/disconnection through the supported control path.
- Short credential TTLs and lease epochs limit damage if a worker is offline during revocation.
- Never rely on client-side deletion of a token as the revocation mechanism.
- Never use a worker-provided node ID, slot number, MAC address or claimed GPU count as authorization evidence.

## 6. Cluster data model

The first implementation can use the existing NANNET durable database. Avoid a new database service until measured scale requires one. All records need explicit schema versions and migrations.

### 6.1 Core records

**Cluster**
- `cluster_id` (opaque stable ID)
- `universe_id`
- `name`, `state`, `schema_version`
- `worker_slot_limit` (must be 1–255; default 255 for this proposal)
- `orchestrator_identity`
- `mesh_id` and private/public discovery policy
- `desired_config_digest`, `observed_config_digest`
- `created_at`, `updated_at`, `generation`

**DeviceEnrollment**
- `device_id`, `public_key`, `key_id`
- `assurance_level`, `platform`, `agent_version`
- `owner_or_tenant_id`, `status`
- `enrolled_at`, `last_seen_at`, `revoked_at`
- optional privacy-reviewed hardware metadata

**WorkerSlot**
- `cluster_id`, `slot_id` (1–255)
- `device_id`, `lease_id`, `lease_epoch`
- `state`, `assigned_at`, `last_heartbeat_at`
- uniqueness constraints on (cluster_id, slot_id) and on active device assignment within the cluster

**ResourceInventory**
- `device_id`, `observed_at`, `inventory_generation`
- host OS/architecture, CPU, RAM, storage and network observations
- zero or more GPU records: vendor, device identifier, backend, reported VRAM, driver/runtime versions, supported precision and measured health
- source and confidence for each field (self-reported, runtime-probed, attested)

**ModelDeployment**
- `deployment_id`, `cluster_id`, `model_ref`, `artifact_digest`
- `runtime_name` and version (Mesh-LLM/Skippy)
- `execution_mode` (local, peer-routed, staged)
- desired stage/worker assignments, resource reservations
- deployment generation, state, readiness evidence and rollback target

**Lease**
- `lease_id`, `resource_type`, `resource_id`
- `holder_device_id`, `cluster_id`, `epoch`
- `issued_at`, `expires_at`, `renewal_deadline`, `revoked_at`
- idempotency key and issuer identity

**Event**
- append-only operational event with event ID, cluster ID, actor, action, object ID, generation, timestamp, outcome and correlation ID
- do not place secrets, bearer tokens, prompts, model inputs or raw private keys in event payloads

### 6.2 Slot allocation

Slots are cluster-local labels in [1, 255]. Allocation must be transactional:
1. verify cluster is ACTIVE and capacity remains;
2. verify device enrollment and authorization;
3. ensure the device has no conflicting active lease;
4. reserve a free slot and increment its fencing epoch;
5. persist the lease before returning credentials;
6. bind the Mesh peer only after peer identity verification.

Slot reuse does not reuse a lease epoch. A stale worker holding an old slot credential must be rejected after reassignment. Slot numbers are presentation/routing identifiers, not secrets.

## 7. NANNET address integration

The existing global address form is:

`nan:/GM0:SC(0-255):MC(0-255):BS(0-255):HW`

The Cluster Universe must integrate with this topology without inventing a competing address grammar. A cluster and worker should be represented through the existing coordinate allocation rules and registered metadata. Do not assume that `SC`, `MC`, `BS` or `HW` maps one-to-one to a GPU index until the address allocator's canonical semantics explicitly define that mapping.

The cluster registry should store:
- canonical NANNET address;
- cluster ID and universe ID;
- worker slot ID;
- device ID and Mesh peer ID;
- address allocation generation and current lease epoch.

The 255 worker-slot limit and the 0–255 coordinate ranges are related capacity constraints but are not interchangeable. In particular, do not reserve address 0 or repurpose the 256 palindromic NaNLMind heads unless the existing topology specification explicitly requires it. The orchestrator's service identity should use the established NANNET service-address allocation, not masquerade as a GPU worker.

## 8. Mesh-LLM and Skippy integration

### 8.1 Integration strategy

Use an adapter/agent boundary. Do not fork Mesh-LLM merely to add NANNET authentication. NANNET's worker agent should:
- enroll with NANNET;
- obtain a scoped worker credential;
- verify cluster policy and lease;
- launch/manage the pinned Mesh-LLM version and configuration;
- bind the local Mesh identity to the NANNET device enrollment;
- report Mesh status and local resource inventory;
- apply orchestrator lifecycle commands;
- stop or drain workloads on lease expiry or revocation.

The orchestrator talks to NANNET worker agents and Mesh-LLM's documented management/control surfaces. It should not depend on private internal Rust APIs unless a pinned upstream integration requires a maintained adapter and version-specific tests.

### 8.2 Current Mesh-LLM surfaces to target

At proposal time, upstream documentation describes:
- OpenAI-compatible inference at `:9337/v1`;
- node management/status API at `:3131`;
- peer networking over QUIC via iroh;
- encrypted peer traffic for requests, responses and split-model activations;
- a distinct owner-control lane for operator configuration/inventory actions;
- Mesh gossip/discovery/routing;
- Skippy stage splits using package-backed layer stages for supported architectures.

These are upstream product interfaces and behaviors, not NANNET guarantees. Pin a tested Mesh-LLM release/commit and record the exact API schema and CLI options used. Do not assume a management endpoint is remotely reachable or authenticated merely because it exists locally. Bind management listeners to loopback/private interfaces by default and protect remote access with a mutually authenticated NANNET-controlled tunnel or an explicitly supported upstream owner-control mechanism.

References:
- https://github.com/Mesh-LLM/mesh-llm
- https://github.com/Mesh-LLM/mesh-llm/blob/main/mesh/docs/design/DESIGN.md
- https://github.com/Mesh-LLM/mesh-llm/blob/main/skippy/docs/SKIPPY_SPLITS.md
- https://meshllm.cloud/docs/pages/architecture/

### 8.3 Supported execution modes

The orchestrator exposes an explicit execution mode for every deployment:

**LOCAL** — one worker hosts the complete model. Prefer this when the model fits with safe memory headroom. This avoids unnecessary inter-node activation traffic.

**PEER_ROUTED** — multiple workers independently host models or replicas; requests route to an eligible host. This is the preferred initial multi-worker mode because it is easier to validate and avoids assuming layer-split efficiency.

**STAGED_SPLIT** — Skippy distributes contiguous model layer stages across selected peers using a supported package-backed model split. The deployment must pass upstream architecture certification, package/artifact verification, capacity checks and topology validation. Downstream stages must report ready before the stage-0 route becomes available, consistent with Skippy's documented startup behavior.

**EXPERT/MoE DISTRIBUTION** — a future experimental mode only. Do not infer that generic Mesh-LLM stage splitting implements arbitrary expert sharding or efficient cross-node expert routing. Enable only when a specific model family, package format, routing behavior and end-to-end correctness/performance test are documented and supported.

The first release should implement LOCAL and PEER_ROUTED. STAGED_SPLIT is enabled only for upstream-certified artifacts and a tested topology. EXPERT/MoE remains explicitly experimental.

### 8.4 Resource-aware scheduling

A placement decision must consider more than total VRAM:
- exact artifact/package digest and size;
- model architecture and upstream split certification;
- per-stage memory estimate including runtime, KV cache, context length and batch concurrency;
- GPU backend, driver/runtime and supported operations;
- CPU RAM and storage bandwidth;
- inter-worker latency, bandwidth, loss and network topology;
- current load, thermal/power state where available, and worker health;
- data locality, trust level and tenant policy;
- expected activation traffic and stage balance.

Use measured benchmark profiles where available. Self-reported GPU memory is advisory until probed. Never add all VRAM figures and claim the sum is a single allocatable memory pool.

## 9. Orchestrator architecture

The orchestrator is a durable, stateless-where-practical service backed by the existing NANNET durable state store. It can be decomposed into modules within the current service initially; separate microservices are not required for the first milestone.

### 9.1 Modules

1. **Cluster API:** create, inspect, configure, drain and destroy clusters.
2. **Enrollment Broker:** validate device challenges and request authority-issued scoped credentials.
3. **Registry:** cluster, device, slot, Mesh peer and resource records.
4. **Lease Manager:** transactional reservations, renewal, expiry and fencing epochs.
5. **Scheduler:** selects eligible workers and placements based on policy and measured resources.
6. **Deployment Reconciler:** compares desired model state with observed Mesh/Skippy state and applies safe transitions.
7. **Health Manager:** heartbeats, timeout policy, quarantine, drain and recovery.
8. **Gateway Integration:** publishes only authorized cluster inference endpoints and enforces tenant quotas.
9. **Audit/Event Log:** records security- and lifecycle-relevant actions without sensitive payloads.
10. **Simulation Harness:** produces virtual workers, network conditions, faults and repeatable 255-slot tests.

### 9.2 Desired-state reconciliation

Cluster operations should be idempotent and generation-based. The API records desired state and returns an operation/deployment ID. A reconciler performs the work and publishes observed state. Repeating the same request with the same idempotency key must not create duplicate clusters, leases or deployments.

Suggested cluster states:

`CREATING -> READY_IDLE -> READY_SERVING -> DRAINING -> STOPPED`

Failure states:

`DEGRADED`, `QUARANTINED`, `FAILED`, `DELETING`.

Suggested worker states:

`PENDING -> ENROLLED -> JOINING -> READY -> BUSY`

Additional states:

`DRAINING`, `SUSPECT`, `OFFLINE`, `REVOKED`, `QUARANTINED`.

A cluster may be READY_IDLE with no models loaded. Daemon/control-plane health must be distinguished from model-serving health.

### 9.3 Orchestrator availability and fencing

The initial deployment may use one orchestrator instance. It must still be restart-safe:
- persist desired state, leases, epochs and deployment records before acknowledging changes;
- on restart, reload and reconcile rather than assume workers stopped;
- use a monotonically increasing control-plane generation/fencing token;
- reject commands from a stale orchestrator generation;
- never issue two valid writers for the same slot/resource;
- keep the authority/ledger commit path as the durable source for global semantic updates.

A later standby orchestrator is permitted only with a proven single-writer election or external lease/fencing mechanism. Two active orchestrators must not independently allocate slots or write conflicting desired state.

## 10. API proposal

The following is a logical API contract, not a claim that these routes already exist. Match the repository's current API conventions and versioning when implementing.

| Method | Route | Purpose |
|---|---|---|
| POST | `/v1/clusters` | Create a cluster universe |
| GET | `/v1/clusters` | List authorized clusters |
| GET | `/v1/clusters/{cluster_id}` | Read cluster desired/observed state |
| POST | `/v1/clusters/{cluster_id}/workers/enroll` | Start a device challenge |
| POST | `/v1/clusters/{cluster_id}/workers/complete` | Complete proof-of-possession enrollment |
| GET | `/v1/clusters/{cluster_id}/workers` | List authorized workers and slots |
| POST | `/v1/clusters/{cluster_id}/workers/{device_id}/drain` | Drain worker safely |
| DELETE | `/v1/clusters/{cluster_id}/workers/{device_id}` | Release membership/slot (not necessarily erase enrollment) |
| POST | `/v1/clusters/{cluster_id}/deployments` | Create model deployment |
| GET | `/v1/clusters/{cluster_id}/deployments/{deployment_id}` | Read deployment state |
| POST | `/v1/clusters/{cluster_id}/deployments/{deployment_id}/rollback` | Roll back to verified deployment |
| GET | `/v1/clusters/{cluster_id}/health` | Cluster/worker/model health |
| POST | `/v1/clusters/{cluster_id}/simulate` | Admin-only simulation job |
| DELETE | `/v1/clusters/{cluster_id}` | Drain and destroy cluster |

All routes require authenticated authorization. Admin-only actions include cluster creation/destruction, policy changes, simulation configuration and deployment approval. Guest/worker actions are restricted to the caller's own enrollment, heartbeat, inventory, assigned tasks and release request.

### 10.1 Example cluster creation request

```json
{
  "name": "bootstrap-cluster-001",
  "universe_id": "bootstrap",
  "worker_slot_limit": 255,
  "mesh": {
    "visibility": "private",
    "discovery": "invite_only"
  },
  "policy": {
    "allow_guest_workers": true,
    "require_device_proof": true,
    "require_attestation": false,
    "default_worker_role": "inference",
    "max_concurrent_deployments": 2
  }
}
```

The server must validate every field, apply a schema version, enforce caller policy and generate the cluster ID. The client cannot choose a privileged orchestrator identity, Mesh peer identity, lease epoch or authority credential.

### 10.2 Example resource report

```json
{
  "device_id": "dev_opaque_id",
  "agent_version": "0.1.0",
  "platform": {
    "os": "linux",
    "architecture": "x86_64"
  },
  "resources": {
    "cpu_threads": 32,
    "ram_bytes": 137438953472,
    "gpus": [
      {
        "vendor": "nvidia",
        "backend": "cuda",
        "vram_bytes": 25769803776,
        "driver": "reported-driver-version",
        "health": "ready"
      }
    ]
  },
  "network": {
    "transport": "quic",
    "measured_rtt_ms": 3.4,
    "measured_bandwidth_mbps": 8500
  },
  "evidence": {
    "inventory_source": "runtime_probe",
    "attestation": "unavailable"
  }
}
```

Values above are illustrative only. The API must distinguish absent/unknown fields from zero and must not treat this sample as measured hardware.

## 11. Security and trust model

### 11.1 Threats

The design assumes that guest workers may be:
- misconfigured, compromised or malicious;
- disconnected or partitioned;
- running modified worker agents;
- reporting false CPU/GPU capacity or fake benchmark results;
- replaying expired enrollment or lease messages;
- attempting to impersonate another device or retain a slot after release;
- able to inspect model fragments, activations or prompts that are sent to them for execution.

The system must not assume a worker is trusted merely because it joined an encrypted Mesh-LLM mesh.

### 11.2 Required controls

- TLS for public NANNET APIs; mutual authentication for privileged service-to-service paths.
- Device proof-of-possession and scoped, short-lived credentials.
- Domain-separated credential derivation; no authority master distribution.
- Transactional slot allocation and monotonically increasing lease epochs.
- Strict authorization on every admin, guest and worker operation.
- Private Mesh-LLM mesh by default; do not publish bootstrap test clusters to public discovery.
- Pin Mesh-LLM/Skippy versions and verify release artifacts.
- Verify model/package digests before deployment; reject unexpected artifacts.
- Restrict management APIs to loopback/private authenticated channels.
- Rate limits, quotas, bounded request sizes and enrollment abuse controls.
- Audit security events without logging credentials, prompts or private payloads.
- Drain and revoke workers on policy violations, key compromise or lease expiry.
- Separate tenant data and model deployment permissions.
- Explicit user consent before a device contributes compute, storage, network or power.

### 11.3 Model and data confidentiality

End-to-end encrypted transport protects network traffic from passive intermediaries; it does not make a participating worker blind to data it must process. In staged inference, a worker may see model layers, intermediate activations and other execution metadata. A worker hosting the input stage may see prompts; a final stage may see later activations or output-related state.

Therefore:
- only place workloads on workers whose trust/consent policy permits the data exposure;
- do not promise confidential inference on untrusted GPUs;
- support trusted-only placement for sensitive workloads;
- document which stages see prompts, weights, activations and outputs;
- treat encryption at rest and in transit separately from execution confidentiality;
- do not claim TEEs or secure multi-party inference without a separately designed and tested mechanism.

### 11.4 Duplicate devices and Sybil resistance

A different MAC address is not proof of a different device. A cloned software image is not a new trusted device. The primary control is a unique device key plus enrollment record, challenge-response and revocation. Rate limits and manual review can slow mass enrollment, but they do not prove physical uniqueness. Stronger uniqueness requires platform attestation or an external identity/verification process and must be reported as such.

## 12. Worker lifecycle and failure handling

### 12.1 Heartbeats and leases

Workers send authenticated heartbeats containing device ID, cluster ID, slot, lease ID/epoch, agent version and coarse health. Heartbeat cadence and expiry are configuration values, not hard-coded protocol assumptions.

Use monotonic local time for timeout measurement and a trusted server time source for persisted expiry. NaNLMind's logical clock may order deterministic ledger events, but must not be the sole basis for real-time lease expiration or network timeout decisions.

Lease renewal is accepted only when:
- device enrollment remains valid;
- cluster policy still authorizes the worker;
- presented lease ID and epoch match the current record;
- the slot is not fenced by a newer epoch;
- resource/health policy permits continued participation.

### 12.2 Worker disconnect

1. Mark worker SUSPECT after missed heartbeat threshold.
2. Stop assigning new requests/stages to it.
3. If it is part of an active staged deployment, use Mesh-LLM/Skippy's supported failure behavior; do not assume a stage can be transparently migrated.
4. Mark deployment DEGRADED or FAILED according to whether the model can still serve safely.
5. Expire/revoke the lease after the configured grace period and increment the slot fencing epoch before reuse.
6. Re-admit the returning worker only after proof, policy and Mesh identity binding are revalidated.

### 12.3 Graceful release

A worker release request:
1. marks the worker DRAINING;
2. stops new work assignment;
3. waits for or cancels active work according to policy;
4. reports final status;
5. removes the Mesh peer through the supported path;
6. releases the slot and revokes the cluster-scoped worker credential;
7. retains or revokes the device enrollment according to the user's explicit choice and policy.

A device that finishes one session should not need a new identity for every reconnect. It should re-enroll/authenticate using its device key and obtain a new lease. Enrollment identity and temporary cluster membership are distinct.

### 12.4 Orchestrator outage

Workers must fail closed for new privileged operations when the orchestrator is unreachable. Existing inference may continue only within an explicitly bounded lease and policy window. After expiry, workers stop accepting new cluster work and drain safely. They must not elect an independent authority or continue issuing slots offline.

## 13. Scheduling and model deployment

### 13.1 Placement pipeline

1. Resolve exact model reference and immutable artifact/package digest.
2. Determine whether upstream Mesh-LLM/Skippy supports the architecture and requested execution mode.
3. Collect current resource inventory and health.
4. Estimate runtime memory, KV cache, concurrency and stage working set.
5. Measure/estimate network topology and inter-worker traffic.
6. Filter workers by authorization, trust policy, compatibility and resource headroom.
7. Select LOCAL, PEER_ROUTED or STAGED_SPLIT.
8. Reserve workers and create deployment generation.
9. Materialize and verify artifacts.
10. Start downstream stages first for staged execution; wait for readiness.
11. Publish the client route only after all required components pass health/readiness checks.
12. Monitor, drain, rollback or mark degraded based on observed state.

### 13.2 Model placement principles

- Prefer one-node LOCAL when the full model fits comfortably.
- Prefer independent models or replicas for the first multi-node test.
- Use staged layer splitting when the exact model package is supported and the network is suitable.
- Do not split a model merely to consume all available GPUs.
- Avoid stage imbalance; a slow stage throttles the pipeline.
- KV cache and concurrent sessions consume memory beyond static weight size.
- Cross-region or internet WAN links may make layer splitting slower than local execution.
- A cluster with 255 workers can host many independent models even when no single model should span all workers.

### 13.3 DeepRepo and existing model assets

The existing DeepRepo/Qwen environment may be used as a separately approved test source for model artifacts or inference comparisons. It must not be silently migrated, repurposed or deleted by this proposal. Preserve the currently working Qwen3-30B-A3B and Qwen1.5B services and the DeepRepo keeper until a replacement is independently healthy and validated. Keep repository credentials such as `DEEPREPO_PAT` scoped to the GitHub Actions workflows that require them; do not distribute them to cluster workers.

## 14. Bootstrap implementation plan

The work is staged so the control plane is proven before GPU-scale claims are made.

### Phase 0 — Upstream compatibility and threat-model gate

Deliverables:
- pin an upstream Mesh-LLM release/commit;
- build/run a single-node local model test;
- record supported OS/architecture/GPU backends and management/inference API schemas;
- verify private mesh join and peer identity behavior;
- test one supported Skippy split using upstream artifacts;
- document licensing, release integrity and operational dependencies;
- decide which worker platforms are supported for the first milestone.

Exit criteria:
- repeatable single-node inference;
- repeatable two-node private mesh;
- verified API and identity binding;
- no dependence on undocumented API behavior.

### Phase 1 — Orchestrator and empty Cluster Universe

Deliverables:
- versioned cluster/device/slot/lease schema;
- create/list/inspect/drain/destroy API;
- cluster state machine and generation-based reconciler;
- authority-issued admin/guest/worker scopes;
- idempotency and audit events;
- empty-cluster integration tests.

Exit criteria:
- cluster creation is idempotent;
- no worker slot is allocated without authorization;
- no authority master appears in cluster state or worker config;
- restart restores desired state and reconciles correctly.

### Phase 2 — Two real workers

Deliverables:
- worker agent enrollment and proof-of-possession;
- scoped worker credential issuance;
- private Mesh-LLM join and NANNET/Mesh identity binding;
- inventory/heartbeat reporting;
- worker drain and slot release;
- PEER_ROUTED inference across two workers.

Exit criteria:
- unauthorized peer is quarantined;
- authorized workers can serve/rout requests;
- revoked worker loses access;
- disconnect/reconnect does not duplicate slots;
- a worker cannot act as another worker or as admin.

### Phase 3 — 4–8 workers and model deployment

Deliverables:
- resource-aware scheduling;
- local and peer-routed deployment;
- model artifact digest verification;
- deployment readiness and rollback;
- first supported Skippy staged split, if a suitable certified artifact and network exist;
- per-worker and per-deployment telemetry.

Exit criteria:
- placement decisions are explainable and reproducible;
- no route is published before readiness;
- worker failure produces a bounded, correct degraded state;
- benchmark compares single-node and distributed performance honestly.

### Phase 4 — 255-slot simulation

Deliverables:
- 255 virtual worker identities with generated key pairs;
- enrollment, slot allocation and lease renewal load tests;
- duplicate/replay/stale-epoch tests;
- simulated network latency, packet loss, partitions and churn;
- orchestrator restart and recovery tests;
- API rate, database and event-log measurements.

Exit criteria:
- exactly 255 slots can be allocated; the 256th request is rejected cleanly;
- no duplicate active slot/device binding;
- stale lease epochs cannot renew or execute;
- revocation propagates within the defined bound;
- no split-brain allocation occurs during orchestrator restart tests;
- system remains observable under worker churn.

This phase validates control-plane capacity only. It does not count as a physical 255-GPU test.

### Phase 5 — Physical scale-out

Only after the earlier gates:
- expand to 16, 32 and then larger physical worker groups;
- qualify hardware/backend combinations;
- benchmark throughput, latency, utilization, network transfer and cost;
- test staged model deployments with realistic failure injection;
- document supported topology sizes and performance envelopes.

Do not advertise 255-GPU production support until a 255-worker physical test has been completed with repeatable measurements and a published failure/recovery report.

## 15. Test matrix and measurable acceptance criteria

| Area | Test | Required result |
|---|---|---|
| Identity | Challenge signed by enrolled device key | Accepted only for matching enrollment |
| Identity | Same image without private key | Cannot inherit enrollment |
| Duplicate | Same device requests second slot in same cluster | Rejected or handled by explicit multi-resource policy |
| Duplicate | MAC changes, device key unchanged | Same device identity |
| Duplicate | New key claims existing device | Requires recovery/rotation authorization |
| Authorization | Guest requests admin operation | 403/denied; no side effect |
| Authorization | Worker accesses another worker's lease | Denied |
| Credentials | Worker credential used in another cluster | Denied |
| Revocation | Revoke device/lease | New operations denied; peer removed/drained |
| Slots | Allocate 255 workers | Exactly 255 unique slots |
| Slots | Allocate worker 256 | Capacity error; no partial record |
| Fencing | Old lease used after slot reassignment | Rejected |
| Idempotency | Repeat create/enroll/release request | No duplicate state or side effect |
| Restart | Restart orchestrator with active workers | Reconciles from durable desired state |
| Network | Partition worker from control plane | No new privileged work after lease expiry |
| Mesh binding | Unregistered Mesh peer attempts workload | Quarantined/denied |
| Artifact | Model package digest mismatch | Deployment rejected |
| Model support | Unsupported split architecture | Fail closed before stage launch |
| Readiness | Downstream stage fails | Stage-0 route not published |
| Performance | Single-node vs peer-routed vs split | Report measured latency/throughput and hardware/network |
| Privacy | Logs and events scanned for secrets/prompts | No credentials or sensitive inference payloads |
| Global state | Cluster lifecycle events | Do not fork NaNLMind semantic ledger or global digest |

Performance acceptance thresholds should be established from baseline measurements rather than invented in this proposal. Report p50/p95 latency, tokens/sec, time-to-first-token, worker utilization, inter-node bytes, model load time, error rate and recovery time. Include model digest, quantization, context length, concurrency, GPU/driver/runtime, network topology and exact Mesh-LLM/Skippy version in every benchmark.

## 16. Observability and operations

Minimum metrics:
- cluster desired/observed generation and state;
- enrolled/active/suspect/offline worker counts;
- occupied/free slots;
- lease issue/renew/expiry/revocation counts;
- enrollment failures and duplicate/replay rejections;
- Mesh peer connectivity and version;
- per-GPU utilization, VRAM use and health where available;
- model deployment state and stage readiness;
- inference request count, errors, queue time, TTFT, tokens/sec and latency percentiles;
- network RTT, throughput, retransmits and bytes per stage;
- orchestrator reconcile lag and database latency.

Use correlation IDs across gateway, orchestrator, worker agent and Mesh runtime. Keep operational events separate from semantic NaNLMind ledger entries. Only validated semantic updates should enter the global semantic commit pipeline.

## 17. Deployment and platform strategy

**Initial orchestrator:** Linux server/container service in the existing trusted NANNET environment. Keep its database and secrets on the trusted side.

**Initial workers:** Linux x86_64 or ARM64 systems with a GPU backend explicitly supported by the pinned Mesh-LLM release. Use dedicated test hosts first.

**Android/Termux:** treat Android as a client or lightweight CPU worker initially. Do not assume Mesh-LLM's Linux ARM64 build is automatically compatible with Android/Termux, GPU drivers or mobile lifecycle constraints. Qualify Android separately with an explicit build/runtime test.

**Networking:** private mesh by default. QUIC peer connectivity may require relay traversal where direct connectivity is unavailable. Measure the actual path; do not assume relayed links are appropriate for high-throughput stage activations.

**Versioning:** pin Mesh-LLM, Skippy/runtime bundle, worker agent, model package and schema versions. Mixed-version support requires an explicit compatibility matrix.

**Secrets:** authority master remains server-side. GitHub tokens and repository credentials remain in the specific CI/keeper workflows that require them. They are never copied into a worker image or guest credential.

## 18. Open decisions before implementation

These are implementation decisions to resolve during Phase 0, not reasons to weaken the invariants:

1. Exact pinned Mesh-LLM release/commit and its current owner-control API authentication mechanism.
2. Whether the first orchestrator will run alongside the existing NANNET authority service or as a separately deployed service.
3. Existing database schema and migration conventions for cluster, device, lease and deployment records.
4. Concrete NANNET address allocation for cluster and worker records under the established `nan:/GM0:SC:MC:BS:HW` format.
5. Worker-agent packaging and supported Linux distributions.
6. First physical GPU/backend combination and benchmark model.
7. Heartbeat interval, suspect threshold, lease TTL and revocation propagation target based on observed network conditions.
8. Trusted-worker policy for prompts, model fragments and intermediate activations.
9. Whether the first physical demonstration uses independent model routing or one certified Skippy stage split.

No open decision authorizes changing the existing authority master, discarding a healthy keeper/model service, exposing CI credentials to workers, or creating a second NaNLMind semantic ledger.

## 19. Recommended first demonstrator

Build **Cluster Universe 001** with:
- one trusted Linux orchestrator;
- two Linux worker hosts where compatible GPU hardware is available;
- one private Mesh-LLM mesh;
- one small, upstream-supported model for the first peer-routing test;
- a NANNET-authenticated OpenAI-compatible gateway;
- a 255-worker simulation running alongside the two-node real test.

Demonstration sequence:
1. Admin creates Cluster Universe 001.
2. Two devices enroll using distinct device keys and receive guest-scoped credentials.
3. Orchestrator assigns slots 1 and 2 and binds their authorized Mesh peers.
4. Both workers report verified runtime inventory (with evidence level clearly marked).
5. Deploy a model locally or route between independent model hosts.
6. Send an authenticated inference request through the NANNET gateway.
7. Disconnect worker 2; verify new routing avoids it and cluster state degrades accurately.
8. Revoke worker 2; verify old credentials and lease epochs fail.
9. Re-enroll/reconnect using the authorized device key and verify safe slot allocation.
10. Run the 255-slot simulation and publish its test report.

The demonstrator succeeds when identity, authorization, routing, revocation, recovery and observability work end-to-end. A successful demo does not by itself prove production security, 255 physical GPUs, arbitrary MoE expert sharding, or confidential inference.

## 20. Upstream references and evidence

The proposal is based on the upstream documentation below, checked during drafting. Upstream interfaces evolve; Phase 0 must pin and re-verify the exact release used.

1. Mesh-LLM repository and README: https://github.com/Mesh-LLM/mesh-llm
2. Mesh-LLM design: https://github.com/Mesh-LLM/mesh-llm/blob/main/mesh/docs/design/DESIGN.md
3. Skippy split guide: https://github.com/Mesh-LLM/mesh-llm/blob/main/skippy/docs/SKIPPY_SPLITS.md
4. Mesh-LLM architecture overview: https://meshllm.cloud/docs/pages/architecture/
5. Mesh-LLM operator/usage documentation: https://github.com/Mesh-LLM/mesh-llm/blob/main/docs/USAGE.md
6. NaNLMind global-topology and distributed-state constraints: `README.md`, `docs/07_DISTRIBUTED.md`, and `docs/37_TWO_RATE_MESH.md` in this repository.

---

## Decision summary

Adopt Mesh-LLM as a replaceable distributed-inference data plane behind NANNET's authority-controlled Cluster Universe. Implement one operational orchestrator plus a maximum of 255 independently enrolled worker slots. Keep authority, device identity, scoped credentials, slot leases and policy in NANNET; keep peer networking and model execution in Mesh-LLM/Skippy; keep NaNLMind's semantic state under its existing single global topology and ledger.

Start with an empty cluster, two authenticated workers and a 255-slot simulation. Expand to physical GPU scale only after the identity, fencing, deployment, failure and benchmark gates pass.
