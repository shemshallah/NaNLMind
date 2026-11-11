# NaNLMind / NaNROUTER main-only native consolidation ledger

Date: 2026-11-11. This is a **claim ledger**, not a blanket merge assertion.
Write to `main` only. Preserve the original frozen 48M decoder, existing
checkpoints, its 128 MiB (64+64 MiB) full mirrored tensor, and the single
six-runner ring/global/meta authority. Do not create new model instances.

**Native arithmetic rule:** mathematical decisions run in raw NaN16 `.nas`
guest kernels on canonical NaN0S. Host-language code is limited to transport,
I/O, authenticated authority, receipts and persistence; it cannot substitute
unvalidated predictions or arithmetic for guest calculations. A NaN volume
identity is data, not a VM instruction.

## What was actually added directly on main

### NaNLMind/main

- `mth/nan16/mth_spectral_trihead_tensor_proposal.nas`: typed signed-I64
  measurements from the canonical weighted-CSR operator; 256 physical
  coordinates, 255 candidate-eligible heads, 85 trihead 2-of-3 masks, quorum
  >=43; explicit per-head capability; fresh generation; independent global and
  MC0 admission; directed mirror pair addresses; zero active-bank writes.
- `mth/drivers/field_driver.nas` opcode **106**: the same native kernel is
  callable through the existing persistent 48M guest VM. It uses disjoint
  `0x003Dxxxx` guest memory for I64 spectral data, trihead masks, pair
  coordinates, writer bits, scratch, candidate records and request. The native
  result ABI is `0x4010..0x4013`.
- `include/nanlm/raw_field.hpp` + `src/raw_field.cpp`: typed transport and
  defensive candidate-bank receipt validation. It does not calculate spectra,
  quorum or tensor offsets.
- Native regressions:
  `mth/tests/mth_spectral_trihead_tensor_proposal_test.nas`,
  `mth/tests/mth_spectral_tensor_driver_opcode_test.nas`, both registered in
  `tools/run_nan16_fixtures.py`. Host integration regression in
  `tests/test_native48m_feedback.cpp`.
- `mth/tests/mth_weighted_csr_to_tensor_native_test.nas` and workflow
  `.github/workflows/48m-weighted-csr-to-hypertensor.yml` execute the
  canonical NaNROUTER weighted CSR kernel and the NaNLMind tensor proposal in
  one native guest image. The original weighted source is included directly
  from the NaNROUTER checkout, not copied into a competing implementation.
  The workflow verifies the current source SHA separately from the historical
  capability evidence digest and reruns the original native numerical oracle.
  The same fixture passed on Linux x86-64 and ARM64 hosted runners.
- No new 48M checkpoint was trained or promoted. Native proposal/transport
  tests do not establish a held-out natural-language improvement.

### NaNROUTER/main

- `mth/nan16/mth_hw5_gutenberg_slot_guard.nas`: structural HW admission.
  `HW4:0` is WordNet, `HW5:0` is Gutenberg. Dedicated HW0..HW3 and
  HW6..HW8 cannot be allocated as community devices. Public allocation is
  **HW9..HW255**; do not adopt old HW5+ or HW8+ allocator variants.
  This guest is NOT a lease issuer, cryptographic authority, TLS service,
  or replacement for the existing portal.
- `mth/tests/mth_hw5_gutenberg_slot_guard_test.nas` and
  `.github/workflows/native-hw5-gutenberg-slot-guard.yml` exhaust all 256
  public allocations and test dedicated operations/revision failures.
  `docs/BS0_HARDWARE_SLOT_CONTRACT.md` now matches the portal's actual
  HW9+ allocation logic.
- `mth/nan16/mth_nan_volume_address64.nas`: native four-tier logical volume
  codec `+sNaN/+sNaN`, `0x7FF1_4E1T_SSCC_F17F`, CRC-8/ATM; BS0/MC0/SC0/GM0,
  256 shards each. It neither moves provider volumes nor changes mount roots.
  It does not cryptographically authenticate a registry.
- `mth/tests/mth_nan_volume_address64_test.nas` and
  `.github/workflows/native-nan-volume64.yml` roundtrip all 1024 tier/shard
  identities, check pinned root identities and reject corrupted headers/CRC.
  The **existing** signed `runner_riddle/volume_registry.py` remains the
  authority for physical-volume bindings, generations and provider identity.

## Requested historical-branch disposition

| Inventory | Treatment / exact remaining gate |
|---|---|
| 1 architecture | NaN16 guest portability tested x86-64 and ARM64; a complete Android/Termux native build-and-run parity matrix remains open |
| 7 topology head roles | Keep separate physical heads, candidate permissions, HWn:0 devices and BS0 runner ports; avoid numerical aliasing |
| 8 contract drift audit | Main already has scanner/CI; verify hash manifests across ALL repos before branch deletion |
| 9-10 HERMES native recovery and leases | Main already has implementations, but full crash-after-reservation and signed lease regression across live portal not reaudited this round |
| 11 geometric trail | Original opcode 41 is present; 85 triheads and >=43 field acceptance preserved |
| 12 native gated conversation | Keep Boolean/deep-logic native gates and teaching provenance independent from free-chat; no LLM answer is a model update |
| 13 seven-credit trainer | Seven native credit kernels and 48M feedback are on main. Do not import the older 8D demo as another decoder; reintroduce its **native-only** fixture cases as appropriate |
| 14 HW allocation | HW5 Gutenberg overrides the historical HW5+ allocator. Actual portal allocates HW9+. Native guard and contract added; existing leases require non-destructive migration |
| 15-16 math preflight | Main has preflight paths; retain a single authoritative catalog and executable checks |
| 17-20 rawroute / 64-bit volume tiers | NaNROUTER is the canonical logical addressing owner; native four-tier codec added. The mounted-shard HTTP/DB implementation is still partly in NaNLMind—this is NOT yet a completed ownership migration |
| 22 lease expiration | Main already has code; cross-portal lease/pending-work replay test needed before treating migration complete |
| 23-24 Koyeb readiness | Preserve `/healthz` vs `/readyz` and SQLite quick_check; independent production rollout check still open |
| 25 universal corpus intake | Main implements chunked quarantine/receipts. Live HW5:0 Gutenberg NANNET streaming + candidate updates still requires a verified end-to-end run |
| 26 rawroute-mounted shards | Preserve generation/idempotency and stable logical placement; native code does not replace its authenticated API/database |
| 27-28 resolution-aware relations | Main already contains native and host integration parts; reconcile remaining branch-by-branch behavior and test all ten resolutions, not byte CE alone |
| 29 router-ring client | Retain six synchronized workers and one registry generation/digest; no new independent state authorities |
| 30 RSS preflight status | Keep digest/ABI/workspace/execution evidence gates mandatory |
| 31-32 weighted CSR v2 | One NaNROUTER canonical kernel, verified numerical oracle, one NaNLMind guest chain, candidate-only opcode 106. Actual live graph-to-48M held-out NLL improvement and persistent promotion are NOT established |
| 33 ten learning modes | Preserve distinct objectives/held-out tests; a full ten-resolution training/evaluation suite remains open |

Nonselected historical branches, especially CLOCKED gateways and demos, also
cannot be deleted on the strength of file existence alone. Maintain their
individual comparison inventories until behavior-specific parity is measured.

## Hard promotion and deployment boundaries

1. No native proposal writes directly to the active tensor or modifies frozen
   48M checkpoint parameters.
2. Every tensor candidate needs a valid writer lease, generation, quorum,
   real Hodge and MC0 evidence, source provenance, and strict **actual
   normalized whole-word** held-out NLL improvement. Native fixture data,
   external teacher labels, source hashes and capability declarations are not
   substitute evidence.
3. Do not redeploy production Koyeb, move volumes, alter live issuer DBs,
   expose credentials or reassign HW4/HW5 as a side effect of consolidation.
4. `/healthz` must not be mistaken for authenticated readiness.
5. Keep 33 historical branches until per-diff tests and missing paths are
   reconciled; this ledger does not authorize branch deletion.

## Reproducible verification

- NaNLMind full CI with original new guest fixture:
  https://github.com/shemshallah/NaNLMind/actions/runs/43060828022
- Native weighted CSR -> 48M candidate tensor (one guest image):
  https://github.com/shemshallah/NaNLMind/actions/runs/43062206289
- Cross-architecture weighted CSR -> tensor:
  https://github.com/shemshallah/NaNLMind/actions/runs/43063016397
- NaNROUTER HW5 Gutenberg admission:
  https://github.com/shemshallah/NaNROUTER/actions/runs/43061421606
- NaNROUTER 1024 native volume identities:
  https://github.com/shemshallah/NaNROUTER/actions/runs/43062797812
- Latest 48M parity with opcode106 host ABI and candidate regression:
  https://github.com/shemshallah/NaNLMind/actions/runs/43064110413

All changes in this ledger were made on pre-existing `main` refs. No new
feature branch was created and no old branch pointer was deleted.
