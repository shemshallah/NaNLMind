# Bootstrap head store: train → map → persist

## 1. What this connects

The Hopfield learner produces 256 head vectors. `HeadStore` writes those vectors
through the runner map into the 2 GiB overbootstrap head arena:

```text
HopfieldRouter
  256 head vectors
       |
       v
RunnerMap (page 1)
  256 head regions x 32 KiB
       |
       v
OverbootstrapMap
  2 GiB virtual register
```

The 8 MiB live runner image is page 0. The 256 head regions live in page 1, so
the full head vector set is 256 x 32 B = 8 KiB inside the 8 MiB page. The
remaining space in each 32 KiB head region is reserved for that head's slots,
keys, and layer payload.

## 2. Test path

`tests/test_overbootstrap_map.cpp` now:

1. trains the 8-token Hopfield cycle for 10 passes;
2. writes all 256 head vectors through `HeadStore::write_all`;
3. reads heads 0..7 back and compares them with the trained router;
4. verifies only pages 0, 1, and the explicitly touched peer page are resident.

This is the first full **train → runner map → 2 GiB overbootstrap** path.

## 3. Android boundary

`OverbootstrapMap` is disabled on Android:

```text
Android: 8 MiB universe only
runner:  8 MiB live image + 2 GiB overbootstrap
```

The dense-map test is skipped on Android. The runner path maps the real 2 GiB
region and can call `prefault()` for full-density residency. Android never
constructs that map.

## 4. Slots and layers

`HeadStore::write_slots` packs each head's used pair slots into its 32 KiB head
region. The first 32 bytes hold the head vector, the next 2 bytes hold the slot
count, and each stored slot is 48 bytes. This is tested with the 8-token cycle.

`LayerPayloadStore` allocates per-layer payload regions starting at page 2, so
it cannot overlap the live 8 MiB image (page 0) or the 256-head arena (page 1).
The test writes a vector-layer payload and a rule-layer payload and reads them
back.

## 5. What is still missing

- remote route-diff merge beyond the local `RouteMerger` test;
- atomic nanclock merge stamps for the 8 MiB universe;
- a real corpus beyond the 8-token cycle;
- the remaining layer payload schemas (syntax/code/corpus).

The store makes the mapping real; it does not claim that the 256 head vectors
are a language model yet.
