# The register file: one chart, 8 MiB, bit for bit

A chart is one 8 MiB page. It has two linked layers:

1. **65,536 address registers** — one for every 16-bit address, including both
   orientations of every mirror pair. Each is 32 bytes. This is the
   individually addressable layer: mirror link, pair link, capabilities, tags,
   epoch, checksum.
2. **32,896 shared pair/head registers** — the canonical cells. Each is 64
   bytes: four NaN16 words (`s+`, `s-`, `q+`, `q-`), operator mask, rule,
   flags, epoch, generation, owner, metadata. The pair state is stored once;
   the two address registers point at it.

The rest of the page is the descriptor table, the address/canonical/pair
indexes, the 256-head table, the adjacency bitmap, dirty maps, checksums, and a
~1.77 MiB extension area for head scratchpads, hyperedges, mailboxes, and future features.

Why 8 MiB is the right size:

- every address is a real register, not an alias;
- the shared pair/head state is not duplicated;
- the page is a power of two, so it fits page caches and range reads;
- it leaves ~2 MiB for the features that are coming (hyperedges, temporal
  blocks, mailboxes, capability tables);
- depth-1 (256 charts) is 2 GiB dense, which fits six 7 GiB head runners with
  placement and history.

---

## 1. Page layout

All values little-endian. The exact layout is:

| offset | size | region | purpose |
|---:|---:|---|---|
| `0x000000` | 4,096 | header | magic, version, genome, counts, page root |
| `0x001000` | 131,072 | index | 65,536 × u16: address → canonical index |
| `0x021000` | 65,792 | canonical | 32,896 × u16: index → canonical address |
| `0x031100` | 65,280 | pair table | 32,640 × u16: pair index → canonical index |
| `0x041000` | 2,097,152 | address registers | 65,536 × 32 B |
| `0x241000` | 1,579,008 | descriptors | 32,896 × 48 B |
| `0x3C2800` | 2,105,344 | shared registers | 32,896 × 64 B |
| `0x5C4800` | 8,192 | head table | 256 × 32 B |
| `0x5C6800` | 8,192 | adjacency | 256 × 256 bits |
| `0x5C8800` | 4,112 | dirty cells | 32,896 bits |
| `0x5C9810` | 8,192 | dirty addresses | 65,536 bits |
| `0x5CB810` | 131,584 | checksums | 32,896 × u32 |
| `0x5EBA10` | 262,144 | head scratch | 256 × 1 KiB |
| `0x62BA10` | 65,536 | chart scratch | shared working memory |
| `0x63BA10` | 1,044,480 | hypermatrix | 32,640 pair rows × 256 candidate bits |
| `0x73B010` | 808,432 | free | extension space |
| `0x800000` | | end | 8 MiB |

The extension is intentional. It holds the 256 per-head scratchpads, the
64 KiB shared chart scratch, the mapped 32,640-row hypermatrix, and room for
hyperedge descriptors, temporal blocks, head mailboxes, and per-address
capability tables without changing the page size again. The hypermatrix rows
are 32 bytes each: a 256-bit candidate set for the unordered pair row. A
triple (a,b,c) projects into rows pair(a,b), pair(b,c), and pair(c,a).

---

## 2. Header

| field | size | meaning |
|---|---:|---|
| magic | 8 | `NLMCHRT1` |
| version | u32 | format version |
| genome | u64 | deterministic genesis seed |
| canonical_count | u32 | 32,896 |
| address_count | u32 | 65,536 |
| pair_count | u32 | 32,640 |
| head_count | u32 | 256 |
| page_bytes | u32 | 8,388,608 |
| chart_path | 4 × u8 + u8 | depth + path |
| parent_hash | 32 | parent chart digest |
| root_hash | 32 | digest of this chart |
| flags | u32 | resident / dirty / read-only / sealed |
| epoch | u64 | last committed epoch |
| reserved | | alignment |

A page with the same header and the same contents has the same digest. A page
with a different root hash is a different state.

---

## 3. Address registers (65,536 × 32 B)

Every address has one:

| offset | size | field | meaning |
|---:|---:|---|---|
| 0 | 2 | addr | the raw 16-bit address |
| 2 | 2 | mirror | `reverse16(addr)` |
| 4 | 2 | pair | pair index, or `32640` for a fixed point |
| 6 | 1 | head_a | row head |
| 7 | 1 | head_b | column head |
| 8 | 1 | flags | fixed / canonical / upper / paired / dirty / locked / portal |
| 9 | 1 | caps | R / W / X bits |
| 10 | 2 | generation | per-address generation |
| 12 | 4 | epoch | last committed epoch |
| 16 | 4 | checksum | FNV-1a over the record except this field |
| 20 | 4 | aux | caller-defined |
| 24 | 8 | meta | canonical cell index / future pointer |

Flags:

| bit | name | meaning |
|---:|---|---|
| 0 | fixed | palindromic address; its own mirror |
| 1 | canonical | `addr == canonical16(addr)` |
| 2 | upper | the mirror orientation (`addr == reverse16(canonical)`) |
| 3 | paired | has a distinct mirror partner |
| 4 | dirty | address-specific metadata changed |
| 5 | locked | cannot be written without a capability |
| 6 | portal | can own a child chart |
| 7 | reserved | future |

For a fixed point: `pair == 32640`, `head_a == head_b == row`, flags `fixed |
canonical | upper | portal`.

For a pair: `head_a = min(row,col)`, `head_b = max(row,col)`, `pair =
pair_index(head_a, head_b)`, and exactly one of `canonical` / `upper` is set.

The mirror link is reciprocal:

```text
address_reg(a).mirror = R(a)
address_reg(R(a)).mirror = a
```

The pair payload is not duplicated. Both address registers point at the same
canonical `NanCell`.

---

## 4. Shared registers (32,896 × 64 B)

Each shared register is the pair/head state:

| offset | size | field |
|---:|---:|---|
| 0 | 32 | four NaN16 words: `s+`, `s-`, `q+`, `q-` |
| 32 | 4 | epoch |
| 36 | 2 | `ops` — 16 Boolean functions enabled |
| 38 | 2 | generation |
| 40 | 2 | owner — row head, or `0xFFFF` for shared |
| 42 | 2 | aux |
| 44 | 1 | selected rule 0..15 |
| 45 | 1 | flags |
| 46 | 18 | meta: local tag, checksum fragment, provenance |

Flags:

| bit | name | meaning |
|---:|---|---|
| 0 | head | diagonal fixed point / resonance head |
| 1 | pair | off-diagonal mirror pair |
| 2 | dual | two rails are independent |
| 3 | portal | cell can own a child chart |
| 4 | locked | cannot be written without a capability |
| 5 | dirty | written since the last flush |
| 6 | checked | checksum verified |
| 7 | shadow | shadow / validation cell |

The four words are the four NaN types. See
[03_MATHEMATICAL_STRUCTURE.md](03_MATHEMATICAL_STRUCTURE.md) for the truth-table
encoding.

---

## 5. Descriptors (32,896 × 48 B)

The descriptor is the link record for a shared register:

| offset | size | field | meaning |
|---:|---:|---|---|
| 0 | 2 | canonical | canonical 16-bit address |
| 2 | 2 | mirror | `reverse16(canonical)` |
| 4 | 4 | pair | pair index, or `32640` for a head |
| 8 | 1 | head_a | row head |
| 9 | 1 | head_b | column head |
| 10 | 1 | flags | head / pair / dual / portal / locked / dirty |
| 11 | 1 | rule | selected Boolean function |
| 12 | 2 | generation | local generation |
| 14 | 2 | owner | row head |
| 16 | 4 | epoch | last committed epoch |
| 20 | 4 | child | child chart pointer / id |
| 24 | 4 | checksum | FNV-1a of the 64-byte shared register |
| 28 | 4 | aux | caller-defined |
| 32 | 4 | next_a | next pair in head_a's row list |
| 36 | 4 | next_b | next pair in head_b's column list |
| 40 | 8 | reserved | future: lease, capability, provenance |

The pair index has a head sentinel of `32640`; list terminators use
`kNoIndex`.

---

## 6. Head table (256 × 32 B)

| offset | size | field | meaning |
|---:|---:|---|---|
| 0 | 2 | fixed_addr | palindromic address `addr(h,h)` |
| 2 | 2 | edge_head | first pair index in the row list |
| 4 | 2 | edge_count | 255 |
| 6 | 2 | child | child chart pointer / id |
| 8 | 4 | phase | Q16.16 resonance phase |
| 12 | 4 | energy | Q16.16 resonance energy |
| 16 | 4 | load | homeostasis |
| 20 | 4 | flags | active / sleeping / consolidating / failed |
| 24 | 4 | genome | deterministic head seed |
| 28 | 4 | checksum | head record checksum |

All 256 heads exist. None is reserved. The fixed address is
`addr(h,h) = (h << 8) | reverse8(h)`.

---

## 7. Three views of the same state

### 7.1 Address view

For a local address `x`, the canonical address is `C(x) = min(x, R(x))`. The
index table gives `canonical_index[C(x)]`, and the shared register is
`registers[canonical_index]`. The address register is `address_regs[x]`.

Both `x` and `R(x)` have their own address register; they share the same
canonical register.

### 7.2 Pair view

For heads `a < b`, the pair index is

```text
π(a,b) = 255a - a(a-1)/2 + (b-a-1).
```

The pair table gives `pair_index[π] = canonical_index`. The pair view is dense:
iterating 0..32,639 visits every edge exactly once.

### 7.3 Head view

Head `h` has a row list of pairs `(h,b)` for `b > h` and a column list of pairs
`(a,h)` for `a < h`. The row list starts at `head[h].edge_head` and follows
`descriptor.next_a`; the column list starts at pair index `h-1` and follows
`descriptor.next_b`. Together they cover 255 edges.

The adjacency bitmap gives O(1) membership:

```text
adjacent(a,b) = (adjacency[a][b/64] >> (b%64)) & 1.
```

The bitmap is 8 KiB; it is symmetric and has zero diagonal.

---

## 8. Resolution: bit, byte, word, cell, KB, page, superpage

The memory system exposes the same state at several resolutions. Each is a
`Ref`:

| kind | size | typical use |
|---|---|---|
| `Bit` | 1 bit | capabilities, dirty/presence, parity, Boolean op enable |
| `Byte` | 8 bits | head ids, tags, small counters, checksum fragments |
| `Word` | 64 bits | one NaN16 word / rail |
| `Cell` | 64 bytes | one shared register |
| `Kilobyte` | 1,024 bytes | hyperedge member lists, mailboxes, small bitmaps |
| `Page` | 8 MiB | one chart |
| `SuperPage` | 2 GiB | 256 charts = one head's full child atlas |

A `Ref` is:

```text
(kind, flags, page path, offset)
```

The offset is interpreted according to the kind. A bit ref is
`(cell << 8) | (word << 6) | bit`. A byte ref is `(cell << 8) | (word << 3) | byte`.
A cell ref is the canonical index. A KB ref is a 1 KiB block within the page's
extension or table area. A page ref is the chart path. A superpage ref is a
depth-1 path prefix.

This is the "resolution of resolution" design: store each structure at the
coarsest resolution that is still exact. Capabilities are bits, tags are
bytes, NaN words are words, a shared register is a cell, a hyperedge list is a
KB block, a chart is a page, and a head's whole child atlas is a superpage.

---

## 9. Operations

### Read a bit

1. resolve the chart;
2. read the address register for per-address capabilities;
3. canonicalize the local address;
4. look up the canonical index;
5. select the word 0..3 and bit 0..63;
6. return the bit.

### Write a bit

1. resolve the chart;
2. check the address capability and the page lease;
3. if the page is shared, clone it (copy-on-write);
4. set or clear the bit;
5. mark the canonical cell dirty and the address register dirty;
6. bump the page version;
7. optionally append a ledger event with before/after hashes.

### Set a capability

1. resolve the address register;
2. update `caps`;
3. recompute the address checksum;
4. mark the address dirty;
5. append a ledger event if the change is durable.

The capability is per address, so the two mirrors can have different rights.
This is a deliberate feature: one orientation can be read-only while the other
is writable, and the shared pair payload is still one object.

### Flush

1. clear the dirty cell and address maps;
2. recompute the page root hash;
3. advance the version;
4. publish the page as a new generation.

### Snapshot

A snapshot is the serialized page (`Universe::serialize()`), which contains:

```text
magic + genome + counts
shared registers (32,896 × 64)
address registers (65,536 × 32)
address dirty map (8 KiB)
head scratchpads (256 × 1 KiB)
chart scratch (64 KiB)
descriptors (32,896 × 48)
heads (256 × 32)
adjacency (8 KiB)
canonical table (32,896 × u16)
pair table (32,640 × u16)
```

The index table is rebuilt from the canonical table on load. This keeps the
snapshot format compact and makes corruption detectable through structural
verification.

### Copy-on-write

Multiple chart paths may map to the same page. A write through one path clones
the page if the `shared_ptr` use count is greater than one. The original path
keeps its old state; the new path gets the new state. Overlapping coordinate
regions coexist without a locking hierarchy.

### Verify

`Universe::verify()` checks:

- 32,896 shared registers and descriptors;
- 65,536 address registers;
- every address register's mirror, pair, heads, flags, capabilities, and
  checksum;
- every descriptor's canonical address and mirror;
- every index entry maps to the same canonical index;
- exactly 256 heads and 32,640 pairs;
- every pair index round-trips;
- every pair descriptor links the correct heads;
- every head has 255 edges across its row and column lists;
- the adjacency bitmap matches the pair set;
- every shared-register checksum matches.

A page that fails verification is rejected before it enters the pager.

---

## 10. Memory arithmetic

```text
shared registers   32,896 × 64   = 2,105,344 B  (2.00 MiB)
address registers  65,536 × 32   = 2,097,152 B  (2.00 MiB)
descriptors        32,896 × 48   = 1,579,008 B  (1.50 MiB)
index              65,536 × 2    =   131,072 B  (128 KiB)
canonical table    32,896 × 2    =    65,792 B  (64.25 KiB)
pair table         32,640 × 2    =    65,280 B  (63.75 KiB)
head table         256 × 32      =     8,192 B  (8 KiB)
adjacency          256 × 32      =     8,192 B  (8 KiB)
dirty cells        32,896 bits   =     4,112 B
dirty addresses    65,536 bits   =     8,192 B
checksums          32,896 × 4    =   131,584 B  (128.5 KiB)
head scratch       256 × 1,024   =   262,144 B  (256 KiB)
chart scratch      65,536        =    65,536 B  (64 KiB)
used                               6,535,696 B
free                               1,852,912 B
page                               8,388,608 B  (8 MiB)
```

A depth-1 atlas (256 charts) is 2 GiB dense. A depth-2 atlas is 512 GiB. The
sparse store only materializes written charts.

---

## 11. Why not 4 MiB?

A 4 MiB canonical-only page can store the 32,896 shared registers and their
descriptors, but it cannot give both mirrors a first-class register without
compromising the descriptor or extension space. The requirement "all addresses
with mirrors individually addressable" makes the 8 MiB page the better unit:

| design | shared state | address registers | extension | verdict |
|---|---|---|---|---|
| 4 MiB canonical-only | 2 MiB | aliases only | ~0.09 MiB | compact, but mirrors not first-class |
| 8 MiB full-address | 2 MiB | 2 MiB (65,536) | ~2 MiB | **chosen** |
| 16 MiB full-address + duplication | 4 MiB | 2 MiB | large | wasteful; pair payload duplicated |

The 8 MiB page keeps the pair payload stored once and still makes every address
individually addressable at bit/byte/word/cell/KB resolution.

---

## 12. Invariants

1. Every palindromic address is a head; every non-palindromic address is one
   orientation of exactly one pair.
2. Every one of the 65,536 addresses has its own 32-byte register.
3. The two mirror address registers point at the same shared register.
4. The shared pair payload is stored once; it is not duplicated per mirror.
5. The 32,896 shared registers are the complete quotient.
6. The pair table is a bijection over `C(256,2)`.
7. The adjacency bitmap is symmetric with zero diagonal.
8. A head's row list plus column list covers exactly 255 edges.
9. A descriptor's checksum matches its shared register.
10. An address register's checksum matches its record.
11. A snapshot round-trips to the same digest.
12. A copy-on-write alias never mutates the original page.
13. An 8 MiB page is the atomic unit of placement and migration.
14. No hidden second array is needed to address any register or any mirror.
