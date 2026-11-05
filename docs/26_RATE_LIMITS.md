# Rate limits and the 24/7 guard

The ring is designed to fail closed, not to burn the PAT. This document records
the guards and the one real incident.

## 1. Observed failure

During heavy development polling, GitHub returned:

```text
HTTP 403: API rate limit exceeded
```

The state was intact: the ring run failed in `Dispatch 6-slot head epoch`, not
in a page write or a commit. The dispatcher, the keeper, and the user shell were
all polling the same PAT.

## 2. Guards

| guard | behavior |
|---|---|
| `ring.yml` preflight | `/rate_limit`; fail if core remaining < 200 |
| `keeper.yml` | resume only if core remaining >= 100 |
| `ring_dispatch.py --poll` | default 30s between run lookups |
| `ring_dispatch.py` retry | 60s sleep on `403` / `rate limit` |
| persistent loop | one job processes 10 epochs; far fewer dispatches |
| single writer | no concurrent reporam writes |
| `concurrency` groups | no duplicate ring/keeper/atomic runs |
| `clock-sync.yml` | skips while the ring is active |

## 3. Operational rules

1. Do not poll `gh run watch` in a shell loop while the ring is active.
2. Use the persistent loop (`epochs=10`) rather than one job per epoch.
3. Let the keeper restart the ring; do not manually dispatch a second ring.
4. Check the budget with `gh api rate_limit`, not by hammering run endpoints.
5. Keep the PAT scopes minimal but sufficient.
6. The Qwen ring has its own dispatches; both rings share the same account
   budget. Leave headroom.

## 3.1 The six-hour limit

Six hours is the **maximum duration of one job**, not a daily quota.

- a job may run up to 360 minutes;
- after it ends, another job can be dispatched;
- concurrency, API budgets, and fair-use limits still apply;
- a public repository's standard runners are free, but that is not a license
  to run unbounded parallel jobs.

The ring uses:

```text
job timeout       350 minutes
loop budget       300 minutes
epochs per shift  200
```

The loop checks a deadline and exits cleanly before the job timeout. The next
shift is a fresh job.

## 4. Budget math

A persistent loop job:

```text
1 dispatch + ~10-20 run-list polls over ~5 minutes
```

A one-epoch six-slot job:

```text
6 dispatches + 6 waits + 1 finalize -> far more API calls
```

That is why the persistent loop is the default operational path.

## 5. Failure behavior

- `403` during dispatch: retry with 60s backoff, then fail the workflow.
- `403` during polling: `latest_run` returns `None`; the waiter retries.
- `403` during keeper: rate precheck `<100` skips the resume.
- No state change happens on a failed dispatch.
- The keeper will resume when the budget resets.

## 6. User-facing commands

```sh
gh api rate_limit --jq '.resources.core'
gh run list -R shemshallah/NaNLMind --workflow ring.yml --limit 1
```

Use these sparingly. The ring itself already checks the budget.
