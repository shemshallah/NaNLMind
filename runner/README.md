# NaNLMind runner ring

`NaNLMind` is the idle orchestrator/storage repository. The six
`nanlm-cpu-1..6` repositories are disposable head runners. The retired Qwen
ring is gone; only the `deeprepo` engine dependency remains.

## One secret

Use the existing `DEEPREPO_PAT` everywhere. It needs:

| repo | permission |
|---|---|
| `NaNLMind` | Contents R, Actions RW, Variables RW |
| `deeprepo` | Contents R |
| `nanlm-ram`, `nanlm-vram` | Contents RW |
| `nanlm-cpu-1..6` | Actions RW, Contents R |

Add the secret to `NaNLMind` and all six `nanlm-cpu-*` repos.

## Head ring

```text
NaNLMind/ring.yml
  -> dispatch nanlm-cpu-1 .. 6, one at a time, interleaved order
     -> prewarm / verify
     -> headshift: packets for heads h where h % 6 == slot
     -> write nanlm/head/<epoch>/<slot> to nanlm-ram registers
     -> when all six slots are present:
          verify 256 unique heads
          write nanlm/round/<epoch>
          increment nanlm/manifest
          advance nanlm/clock tick and phase
  -> self-redispatch the next epoch
```

`keeper.yml` restarts the ring only when no ring run is active. `ring.yml`
checks the GitHub rate limit before dispatching and uses the existing
`deepcore` budget/meter when the tier connection is available.

`nanlm_worker.py` ops:

| op | effect |
|---|---|
| `selftest` | build + verify, write `nanlm/gate` |
| `prewarm` | verify the head map, no writes |
| `headshift` | process one slot's 42–43 heads for one epoch |
| `handoff` | alias for `headshift` |
| `logic` | run one graded logic-curriculum slot |
| `logic-core` | run the staged Boolean/deep/word core session |
| `training` | run the bounded Boolean/deep/word/sentence corpus pipeline |
| `status` | print gate/clock/lease/manifest |

## Tiers

`nanlm-bootstrap.yml` creates the `nanlm-ram` and `nanlm-vram` release tiers,
reusing deeprepo's `deepcore` sparse RAM/VRAM code. NaNLMind is the only ring;
there is no Qwen tier or second writer journal.

## Why one-at-a-time

A full head epoch is a synchronous handoff: each slot preloads, processes,
publishes its packet set, and releases the lease before the next slot starts.
This keeps the GitHub Actions concurrency and API budget bounded. The
bit-reversed slot order keeps survivor spacing when a subset of slots is alive.

## Local development

```sh
make
python3 runner/nanlm_worker.py --op selftest --slot 1 --epoch 0
python3 runner/nanlm_worker.py --op prewarm --slot 1 --epoch 0
python3 runner/nanlm_worker.py --op headshift --slot 1 --epoch 0
```

For logic training:

```sh
python3 runner/nanlm_worker.py --op logic --slot 1 --epoch 0 --rounds 4
python3 runner/logic_local_ring.py --slots 6 --rounds 4
```

The curriculum writes `state/logic_<epoch>_<slot>.json` and publishes the same
record to `nanlm/logic/<epoch>/<slot>` when tiers are available.

Without `deepcore`/tiers the worker falls back to `state/*.json`. The fallback is
for development, not 24/7 operation.


## Relational-spectral runner contract

The shared RSS protocol is defined in `runner/relational_spectral.py`. It validates versioned job/result envelopes and capability manifests only; it contains no graph or spectral mathematics. Native NaN16 MTH kernels must be assembled and executed before a capability may be marked `native_verified`. Dispatch rejects `specified` and `source_written` capabilities and checks workspace budgets. Contract tests: `python3 -m unittest tests/test_relational_spectral_contract.py` (or run the test file directly).


The K256 exact baseline is implemented in MTH as `k256_laplacian_u16`
and passed the canonical NaN16 assemble-and-execute workflow. The worker
advertises this one capability as `native_verified`, with its SHA-256 kernel
digest and a 4096-byte maximum input/output workspace. All general sparse
graph, pair-space, filter, Lanczos, wave and fold capabilities remain
`specified`; no broader RSS execution is implied.
