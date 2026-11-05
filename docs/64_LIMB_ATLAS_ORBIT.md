# U2/U3: limb counters, atlas paging, reference orbit

## 1. U2 — chart limb counters

`ChartLimbStore` stores 16-bit limbs in `AddressReg::meta` at a base address.
`LimbCounter` does carry/borrow across limbs:

```text
1 -> 0xFFFF + 1 -> 0x10000 (two limbs)
0x10000 - 1 -> 0xFFFF
1 - 1 -> 0
```

No host integer is the counter.

## 2. U3 — atlas paging

`Atlas` owns 8 MiB `Universe` pages. `AtlasLimbStore` maps global limb index to
`page = index / limbs_per_page`, `offset = index % limbs_per_page`.

Test: 17 limbs with 16 per page -> two pages; limb 16 reads/writes on page 2.

```text
PASS multi-limb counters and atlas paging
```

This is the fixed-rule growth path: a counter can cross a page boundary without a
host bigint.

## 3. Reference 2CM orbit

`tests/test_two_counter_orbit.cpp` runs the chart 2CM and a host reference 2CM
step-by-step on the copy program. After every step:

```text
ip, c0, c1, halted match
```

Final: C0=0, C1=5, HALT; 22 decodes including the final HALT.

```text
PASS reference 2CM orbit comparison
```

## 4. Honest boundary

- U1 `step` still uses 64-bit metadata counters.
- U2/U3 are storage/allocator prototypes, **not yet wired into `step`**.
- The atlas is a prototype; no TM encoder yet.
- No UTM claim.

## 5. Next

1. Replace U1 counters with `LimbCounter` in `TwoCounterMachine`.
2. Use `AtlasLimbStore` for unbounded counters.
3. Add reference orbit for carry/borrow and paged counters.
4. Then TM → 2CM encoding.
