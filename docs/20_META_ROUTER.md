# The meta-router: universes as heads, routes as pairs

## 1. Is the next layer more spaces? Yes.

The local chart geometry does **not** change:

```text
256 x 256 addresses
256 palindromic heads
32,640 mirror pairs
32,896 canonical cells
2 rails per pair
```

A higher layer is **more charts**, using the same 256×256 algebra. A chart whose
heads are themselves universes is a **router chart**.

```text
Level 0:  1 universe        = 1 chart       = 256 x 256 cells
Level 1:  256 universes     = 256 charts    = 8,421,376 canonical cells
Level 2:  65,536 universes  = 65,536 charts = 2,155,872,256 canonical cells
Level 3:  16,777,216 universes
Level 4:  4,294,967,296 universes
```

The count multiplies by 256 per layer. It is not 256×2; it is 256×256 per chart
with two rails per pair.

---

## 2. A router chart

A router chart is an ordinary chart with a different **role**:

| chart element | normal role | router role |
|---|---|---|
| 256 diagonal heads | resonance heads | portals to 256 child universes |
| 32,640 pair cells | relations | routes between universes |
| `s+` rail | forward state | forward route / BE/FUTURE |
| `s-` rail | reverse state | reverse route / LE/PAST |
| `q+`, `q-` | shadows | route checksum / validation |
| `ops` | Boolean mask | route-enable mask |
| `aux` | local metadata | route flags + operation code |
| `epoch` | local time | route epoch |

The 256 diagonal points are **universe roots**, not separate minds. Each is a
portal into a child chart of the same object. The off-diagonal pair cells are
the routes between those child universes. The 32,640 routes are the binary
channels and flag carriers across the layer.

---

## 3. The portal word

A route word carries data and flags:

```text
PortalWord {
    op      // read / write / ack / open / close
    flags   // 8 bits
    data    // 32 bits
}
```

The NaN class encodes the operation and direction:

| class | NaN | direction | meaning |
|---|---|---|---|
| 0 | `+qNaN` | BE / FUTURE | quiet read |
| 1 | `-qNaN` | LE / PAST | quiet read, reverse |
| 2 | `+sNaN` | BE / FUTURE | signaling write / open |
| 3 | `-sNaN` | LE / PAST | signaling write / close / rollback |

The four classes are the portal protocol. `q` means quiet/observe; `s` means
signaling/change. The sign selects BE/FUTURE (`+`) or LE/PAST (`-`). This is a
machine convention, not IEEE floating-point semantics.

`aux` carries:

```text
bits 0..7   flags: present, open, secure, dirty, ack, error, reserved
bits 8..15  operation code
```

The pair address gives the source and destination:

```text
addr(src, dst) = (src << 8) | reverse8(dst)
```

Bit reversal swaps source/destination. The canonical pair is one shared cell;
the two rails are the two directions. The address pairing is exactly the
binary/flag channel across universes.

---

## 4. Routing

A route operation:

1. select source universe `src` and destination `dst`;
2. compute the canonical pair address;
3. choose the forward (`s+`) or reverse (`s-`) rail from the portal op;
4. write `PortalWord` data and flags;
5. set `aux` operation/flags and the route epoch;
6. update the descriptor checksum and dirty state;
7. optionally append a ledger event.

A read operation decodes the rail and returns the data, flags, operation, and
direction. The reverse rail is independent; a forward write does not erase the
reverse route.

The router is a field of the one topology. It is not an external coordinator.
A "central layer mind" is the root router chart's resonance/attention field:
it selects routes, opens portals, and propagates activation. It still uses the
one ledger and the one digest.

---

## 5. Custom index for a final layer

The final layer can use a **custom 16-bit directory**:

```text
final_index = addr(a, b) = (a << 8) | reverse8(b)
```

There are 65,536 index values, 32,896 canonical entries, 256 diagonal portals,
and 32,640 routes. The same palindrome/transpose rules apply, so a final-layer
index is still a pair of 8-bit universe ids. If a deployment needs a different
namespace, it can map the 16-bit index to a semantic handle without changing
the pair algebra.

A custom index is useful for:

- routing tables keyed by `(source, destination)`;
- a 256×256 adjacency matrix of universes;
- a final directory of 256 portals with 32,640 inter-port routes;
- a binary/flag channel between any two universes.

---

## 6. Code

`include/nanlm/router.hpp`, `src/router.cpp`:

```cpp
RouterChart router(topology, PageId::root());
router.open_universe(3);

router.route(3, 7, PortalOp::WriteForward, 0xDEADBEEF, 0x5, epoch);
auto r = router.read(3, 7, true);
// r.word.data == 0xDEADBEEF, r.word.flags == 0x5
```

`tests/test_router.cpp` verifies:

- 256 portals map to child chart paths;
- forward and reverse routes are independent;
- qNaN/sNaN and BE/LE decode correctly;
- binary payload and flags cross the pair;
- a child universe can be materialized on demand;
- the router chart remains structurally valid after route writes.

---

## 7. Scaling

| level | universes | canonical cells | dense |
|---:|---:|---:|---:|
| 0 | 1 | 32,896 | 8 MiB |
| 1 | 256 | 8,421,376 | 2 GiB |
| 2 | 65,536 | 2,155,872,256 | 512 GiB |
| 3 | 16,777,216 | 551,903,297,536 | 128 TiB |
| 4 | 4,294,967,296 | 141,287,244,169,216 | 32 PiB |

A router chart is 8 MiB. Level 1 is 256 router pages; Level 2 is 65,536. The
router layer is sparse: a portal can exist before its child universe is
resident.

---

## 8. What this changes

- The 256 fixed points are not only resonance heads; at the meta-layer they
  are **universe roots**.
- The pair cell is not only a relation; at the meta-layer it is a **route**
  carrying data and flags.
- qNaN/sNaN and BE/LE are not decoration; they are the portal operation and
  direction.
- The "central mind" is a routing field in the one topology, not a new
  separate brain.

## 9. Open questions

1. Should a route be opened by resonance attention or by an explicit flag?
2. How does congestion/backpressure propagate through the router?
3. Should the router layer have its own clock phase or inherit the global one?
4. How are child universes preloaded and evicted?
5. What is the final-layer custom index policy?
6. Can a route carry a hyperedge reference instead of only 32 bits?
7. How does a route failure roll back through the reverse rail?
