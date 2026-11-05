# Global wall-clock anchor

## 1. Two clocks, two jobs

| clock | authority | use |
|---|---|---|
| logical oscillator | state order | epochs, phases, handoff, replay |
| wall anchor | real time | lease expiry, human timestamps, “when” |

The logical clock never needs to know what a nanosecond is. The wall anchor
never reorders state.

## 2. Sampling

`runner/atomic_clock.py` samples three HTTPS sources:

1. GitHub `Date` header from `api.github.com/rate_limit`;
2. `worldtimeapi.org`;
3. `timeapi.io`.

Each sample records:

```text
server_unix, uncertainty_seconds, source, local_mid
offset = server_unix - local_mid
```

The script takes the median offset, rejects samples more than 2 seconds from the
median, and reports:

```json
{
  "ok": true,
  "wall_unix": 1793859999.5,
  "offset_s": 0.42,
  "uncertainty_s": 0.51,
  "sources": [...],
  "errors": [...]
}
```

If fewer than two consistent sources survive, the sync fails closed and the
previous anchor remains. There is no silent “best guess.”

## 3. Anchor record

`nanlm/atomic` carries:

```text
wall_unix
offset_s
uncertainty_s
sources[]
at
```

The ring reads the anchor before a shift. A lease can use the anchored wall time
for expiry; the logical epoch still orders the state transition. The anchor is
included in the generation manifest as metadata, not in the state digest.

## 3.1 Universe time request

A universe does not call the time API directly. It sends a route request through
the router chart:

```text
RouterChart::request_time(src, dst, epoch)
  PortalOp::ReadForward
  data  = "TIME" (0x54494d45)
  flags = kTimeRequestFlag
```

The response is a `SnapshotStamp`:

```text
wall_ns, uncertainty_ns, logical_tick, phase, anchor_id
```

`GlobalTopology::set_atomic_anchor()` stores the latest anchor;
`stamp_snapshot()` combines it with the logical clock. The ring round record and
manifest include the same `atomic` record, so a snapshot can always be traced to
one wall anchor.

This is how 256 universes share one time source without 256 API calls. The
router is the fan-out; the anchor is the single truth.

## 4. Rate limits

- sync at most every 30 minutes;
- skip entirely while a ring run is active;
- three HTTPS requests per sync, no GitHub API writes except the register tick;
- keep the last anchor when sources fail;
- one workflow, `clock-sync.yml`, with `concurrency: nanlm-atomic`.

## 5. Failure modes

| failure | response |
|---|---|
| one source down | use the median of the rest |
| outlier clock | reject >2 s from the median |
| fewer than 2 sources | fail closed; keep previous anchor |
| wall clock jumps | no state reorder; leases see the jump, logical epoch does not |
| ring active | skip; do not contend for the writer |
| anchor stale | uncertainty grows in the record; re-sync before a long lease |

## 6. What this is not

- It is not a local atomic clock.
- It does not make GitHub Actions real-time.
- It does not replace the logical clock for ordering.
- It does not guarantee sub-millisecond accuracy; the uncertainty field is the
  honest bound.

## 7. Self-test

```sh
python3 runner/atomic_clock.py --self-test
```

The self-test feeds three consistent samples and one outlier; it checks the
median offset, the outlier rejection, and the uncertainty bound. CI runs this
without network access.

## 8. Why the ring needs it

The logical clock can order a handoff, but a lease still expires in real time.
The wall anchor lets all six runners agree on “now” within a stated uncertainty
without putting wall time into the state digest. That is the right split:
**logical time for causality, wall time for leases.**
