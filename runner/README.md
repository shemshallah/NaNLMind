# NaNLMind runner ring

`NaNLMind` is the idle orchestrator/storage repository. The six
`nanlm-cpu-1..6` repositories are disposable head runners. The Qwen demo remains
on `deeprepo-cpu-1..5`; it is a separate ring.

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
| `status` | print gate/clock/lease/manifest |

## Tiers

`nanlm-bootstrap.yml` creates the `nanlm-ram` and `nanlm-vram` release tiers,
reusing deeprepo's `deepcore` sparse RAM/VRAM code. The Qwen ring keeps
`reporam`/`repovram`; NaNLMind keeps `nanlm-ram`/`nanlm-vram`, so both can run
without sharing a writer journal.

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

Without `deepcore`/tiers the worker falls back to `state/*.json`. The fallback is
for development, not 24/7 operation.
