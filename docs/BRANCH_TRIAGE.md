# Branch triage — 2026-11-11

Canonical: `main` (branch head at the time of this audit).

Do not merge a branch wholesale. A branch survives only if its commits map to a canonical stage in `docs/UNIFIED_SYSTEM.md`. Tag archived branches before deletion.

## Merged branches — deletion candidates after tag

- `origin/docs/runner-ring-authority-20261108` — 2026-11-08 8079285 Document atomic runner-ring authority and HW5 ring
- `origin/feat/atomic-runner-ring-authority-20261108` — 2026-11-08 431e077 Add atomic Koyeb runner-ring nanclock, lease and handoff authority
- `origin/feat/nannet-koyeb-router-cutover` — 2026-11-08 6ba1712 Cross-test signed NANNET pairing and MTH against merged native HERMES plugin main
- `origin/feat/single-service-portal-ring-ingress-20261108` — 2026-11-08 cb8e87d Serve embedded /v1/ring ingress from the single portal service
- `origin/feature/retire-koyeb-config-examples-20261108` — 2026-11-08 d6ee15e Mark NaNLMind legacy portal deployment guide as rollback-only after router ownership transfer
- `origin/gpt/global-persistence-ntf` — 2026-11-05 d6e5529 Merge TM persistence and sharded global history
- `origin/graph-spectral-foundation` — 2026-11-06 2cb0479 Cross-link foundational research game plan and MTH implementation plan
- `origin/math-catalog-unification` — 2026-11-06 9d760c2 Verify mapping and language layer namespaces stay distinct
- `origin/nan-rawroute-four-tier-addressing` — 2026-11-06 82115ca docs: specify NaN rawroute four-tier storage and address model
- `origin/nannet-canonical-route-hardening` — 2026-11-06 52dbff1 Document direction-specific point-zero decoding on native bridge
- `origin/rss-sparse-capability-contract` — 2026-11-06 ef03cc9 Fix RSS status import for package and worker execution
- `docs/runner-ring-authority-20261108` — 2026-11-08 8079285 Document atomic runner-ring authority and HW5 ring
- `feat/atomic-runner-ring-authority-20261108` — 2026-11-08 431e077 Add atomic Koyeb runner-ring nanclock, lease and handoff authority
- `feat/single-service-portal-ring-ingress-20261108` — 2026-11-08 cb8e87d Serve embedded /v1/ring ingress from the single portal service
- `integration/raw-symbiotic` — 2026-11-09 56cb451 Use backoff-compatible raw field test in integration

## Unmerged remote branches — decision list

| branch | only in branch | only in main | last commit | recommendation |
|---|---:|---:|---|---|
| `origin/clocked-universe-nannet` | 117 | 609 | 2026-11-05 899e320 ci(clock): add bridge regression gate with merge dependency | ARCHIVE; control-plane/transport only |
| `origin/nannet-universal-intake` | 111 | 609 | 2026-11-05 3c9d1f4 Keep operator device status synchronized when leases expire | ARCHIVE; control-plane/transport only |
| `origin/clocked-universe` | 75 | 612 | 2026-11-05 15a2e09 test(clock): cover runner lease recovery and scoped auth | ARCHIVE; control-plane/transport only |
| `origin/resolution-aware-conversation-learning` | 40 | 510 | 2026-11-06 2fd9232 test: surface local ring subprocess diagnostics | REVIEW; candidate for credit/relation stage |
| `origin/nan-volume-addresses` | 32 | 422 | 2026-11-06 8b4db30 Clarify NaN paths are mount roots, not database file paths | ARCHIVE; control-plane/transport only |
| `origin/clocked-native-demo-mainline` | 31 | 417 | 2026-11-06 86b0228 Add Clocked native demo build and test targets | ARCHIVE; control-plane/transport only |
| `origin/feat/hermes-router-lease-delegation` | 21 | 177 | 2026-11-08 e7001e2 Verify final signed native NANNET integration against merged NaNROUTER and HERMES main | ARCHIVE; control-plane/transport only |
| `origin/rawroute-mounted-shards-api` | 20 | 422 | 2026-11-06 2d65998 Link the production Koyeb environment example | ARCHIVE; control-plane/transport only |
| `origin/feature/mth-seven-credit-nanlm-train-20261109` | 17 | 97 | 2026-11-09 9895bda Document NaN16 Q16-to-float gate conversion and resumable native MTH7 training | REVIEW; candidate for credit/relation stage |
| `origin/math-preflight-integration` | 17 | 181 | 2026-11-07 ecdbd45 Document worker-side NaN16 math preflight operation | ARCHIVE; control-plane/transport only |
| `origin/nan-rawroute-parser` | 15 | 423 | 2026-11-06 a9c3a5e test: validate logical namespaces and shared physical storage reporting | ARCHIVE; control-plane/transport only |
| `origin/resolution-aware-relation-training-rebased` | 14 | 423 | 2026-11-06 b41ffbe Fix local ring to read worker zero-based output paths | REVIEW; candidate for credit/relation stage |
| `origin/nan-volume-addresses-mainline` | 13 | 421 | 2026-11-06 6ec2808 Port NaN volume address specification onto mainline | ARCHIVE; control-plane/transport only |
| `origin/clocked-hackathon` | 8 | 557 | 2026-11-05 34f6df8 feat(clocked): add gateway demo and chainable integration | ARCHIVE; control-plane/transport only |
| `origin/nan-volume-addresses-final` | 8 | 419 | 2026-11-06 3c72210 Preserve relation trainer and add volume address test to current Makefile | ARCHIVE; control-plane/transport only |
| `origin/feat/hermes-n16t-dispatch-recovery-portal` | 7 | 176 | 2026-11-08 ed2e993 Verify signed native session recovery against merged NaNROUTER and HERMES main | ARCHIVE; control-plane/transport only |
| `origin/feature/hermes-native-gated-free-chat-20261108` | 7 | 175 | 2026-11-08 bd2189b Gate Hermes free-chat PR on protocol tests and actual native C++ logic/relation smoke | ARCHIVE; control-plane/transport only |
| `origin/router-ring-runner-client` | 7 | 415 | 2026-11-06 c2eaebf Fix local test server cleanup order to avoid blocking CI | ARCHIVE; control-plane/transport only |
| `origin/feat/cross-repo-nan-contract-drift-audit` | 6 | 149 | 2026-11-08 76abb29 Fix malformed contract drift list-comprehension filter before CI | ARCHIVE after extracting documentation |
| `origin/fix/bs0-hw4-wordnet-hw5-255-allocation` | 5 | 177 | 2026-11-07 4d978fb Correct BS0:0 shared port, HW0:0 node and reserved WordNet HW4 descriptions | ARCHIVE after extracting documentation |
| `origin/nannet-demo-points-9-255` | 5 | 316 | 2026-11-06 7a37725 Clarify reserved HW slots for the 9..255 point pool | ARCHIVE; control-plane/transport only |
| `origin/clocked-nannet-consumer-mainline` | 4 | 419 | 2026-11-06 630164c Port Clocked NANNET consumer tests onto current main | ARCHIVE; control-plane/transport only |
| `origin/rss-weighted-csr-v2` | 4 | 209 | 2026-11-06 a74ffb6 Document weighted CSR v2 native evidence and RSS capability boundary | ARCHIVE; control-plane/transport only |
| `origin/rss/weighted-csr-v2-mainline` | 4 | 181 | 2026-11-07 731e158 Add weighted CSR v2 RSS contract tests on current main | ARCHIVE; control-plane/transport only |
| `origin/nannet-expired-lease-auth` | 3 | 315 | 2026-11-06 bdf716f Document six-hour lease policy and expired-token restrictions | ARCHIVE; control-plane/transport only |
| `origin/nannet-koyeb-readiness` | 3 | 539 | 2026-11-05 6d6166b Document persistent NANNET readiness requirements | ARCHIVE; control-plane/transport only |
| `origin/nannet-readiness-mainline` | 3 | 417 | 2026-11-06 9409a1a Document strict NANNET readiness probe | ARCHIVE; control-plane/transport only |
| `origin/feat/v2-geometric-trail-field-credit` | 2 | 119 | 2026-11-09 cf7f785 Wire NaN16 geometric TRAIL block into field driver; test 2/3, 43/85 and stale rollback | REVIEW; candidate for credit/relation stage |
| `origin/math-preflight-mainline-assets` | 2 | 178 | 2026-11-07 8950581 Record merged native preflight evidence accurately | ARCHIVE; control-plane/transport only |
| `origin/rss/preflight-required-status-v1` | 2 | 180 | 2026-11-07 cffdb18 Assert native evidence is not dispatch authorization | ARCHIVE; control-plane/transport only |
| `origin/training-modes-live-learning` | 2 | 510 | 2026-11-06 635d662 Persist learned relations in mirror pairs and report per-bit metrics | REVIEW; candidate for credit/relation stage |
| `origin/architecture` | 1 | 534 | 2026-11-06 7a225f8 Document architecture target and build requirements | ARCHIVE; extract no code until stage mapping matches |
| `origin/docs/topology-head-roles-not-hw-ports` | 1 | 148 | 2026-11-08 9d77203 Clarify that 256 structural NaN16 heads, 255 MP writers and 250 curriculum roles coexist in one topology | ARCHIVE after extracting documentation |

## Unmerged local branches

| branch | only in branch | only in main | last commit | recommendation |
|---|---:|---:|---|---|
| `architecture` | 1 | 534 | 2026-11-06 7a225f8 Document architecture target and build requirements | ARCHIVE; extract no code until stage mapping matches |
| `head-cortex-token-length` | 1 | 182 | 2026-11-07 bed92a4 Accept scoped NANNET bearer tokens in head cortex | AUDIT then archive |
| `nannet-pairing-admin` | 1 | 254 | 2026-11-07 bd323b9 Expose stable pairing issuer and operator pairing-code endpoint | ARCHIVE; control-plane/transport only |
| `single-service-head-cortex` | 1 | 183 | 2026-11-07 bd002d3 Run head cortex inside the single nannet portal service | AUDIT then archive |

## Detached worktrees

| path | HEAD | state | recommendation |
|---|---|---|---|
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-backoff` | `88861a8` | merged; branch | remove after confirming no unique work |
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-batch` | `8836d7f` | merged; branch | remove after confirming no unique work |
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-copy` | `78f4e9b` | merged; branch | remove after confirming no unique work |
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-eval` | `0dec07f` | merged; branch | remove after confirming no unique work |
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-field` | `92c2f60` | merged; branch | remove after confirming no unique work |
| `/data/data/com.termux/files/home/.local/share/opencode/worktree/3bc029/nan-hash` | `c81d1b9` | unmerged; branch | audit/cherry-pick then remove |

## Rule

- `main`: canonical only.
- One active learning branch only while a stage is being integrated.
- No permanent `architecture`, `hypertensor`, `vectorization`, `context`, or `meta` branches; those are stages, not products.
- Archived branches remain recoverable by tag, not by remote branch.

