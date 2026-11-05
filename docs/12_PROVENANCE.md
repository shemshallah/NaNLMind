# Provenance, archives, and hashes

## 1. What was extracted

All 28 ZIP archives were extracted into one directory per archive:

```text
NaNLM_statespace/
  *.zip                         original archives (retained)
  ARCHIVE_SHA256.txt            SHA-256 manifest
  archive/
    <archive-stem>/             extracted tree
      <top-level-dir>/          the archive's own root
```

Per-archive directories avoid collisions between:

- `Round5.zip` and `Round5-1.zip` (byte-identical duplicate);
- `Round8.zip` and `Round8-1.zip` (byte-identical duplicate);
- `Round15.zip` content appearing as `distributedmind.zip`;
- `merged_R15-R17` and `merged_R15-R18` (the latter adds R18).

## 2. SHA-256 manifest

| archive | SHA-256 |
|---|---|
| `NaN16_PTC_merged_R15-R17.zip` | `81faf026bd557a2952a39b341e81ce66b6972cf8be7e33ae6e43deefe8cd6431` |
| `NaN16_PTC_merged_R15-R18.zip` | `54d180e8557cda794f031caf33169773fc5b2109bac4226328dfdb1a12f837b3` |
| `NaN16_Palindromic_Temporal_Computer_Round2.zip` | `02a9511c0a48996879fee8e529d7ff46eb97ded9c25b336772d33b51b88add08` |
| `...Round3.zip` | `2513f0e3e7a920a281bec5b27d59027d2d5b6870371c075872e496a6b303c64d` |
| `...Round4.zip` | `3fc7b3f59329a4d69fc62097eed57938d000cd5ea9652d5f034c7108dc7586ab` |
| `...Round5.zip` | `cce33c5be5876e83d9e1d7786730115f29d997b0f4a6f9f11e095a257a71d2a1` |
| `...Round5-1.zip` | `cce33c5be5876e83d9e1d7786730115f29d997b0f4a6f9f11e095a257a71d2a1` |
| `...Round6.zip` | `5769ede3781a2c3bd4bd19bb9a4c2de17f0736ef37f2f4dd65f48afa3e94b756` |
| `...Round7.zip` | `99f4b75c74f78c0dbbbd3c0326abfe936ba160a4e24748c266bb3c1c479e308c` |
| `...Round8.zip` | `016a76ccc865799cb2933a76c53cb48fc65af447856987a1a4b78f6e820eb19d` |
| `...Round8-1.zip` | `016a76ccc865799cb2933a76c53cb48fc65af447856987a1a4b78f6e820eb19d` |
| `...Round9.zip` | `effee938635cc0712c21fc38b9e590c67849495f0be72ee4efc6ee7b96d14bb2` |
| `...Round10.zip` | `44936c573948fca30fafb2bd2bb73305752e7bf8719ba451f6844166cb5e7d58` |
| `...Round11.zip` | `564156bce9497cbaf80734ee7e99d4a32e0c229bf3e2391b23751dba2d3ec6a1` |
| `...Round12.zip` | `d15a4d6cfe7777488155db1c3d759d2aa6b23cc37d33e9fcbc1dce8712cdfa37` |
| `...Round13.zip` | `421f5017aac6fdd0055342f2d56989bce2684f8c35a0a98ae18358a346b85af3` |
| `...Round14.zip` | `2fb8070a5e8d51d52961e736bfdbf574ca24f80c612741390505ecbfa0d08ff0` |
| `...Round16.zip` | `d4ec8ada1d249bdaadbdcfd3b8e3c9d98f89351df30316bc8b1b29e119825f97` |
| `...Round17.zip` | `27493b15b3dd1cd4bcaac066d1d914215669a3909338979c162ed1d0c1d310c9` |
| `...Round18.zip` | `952c5717e19b94a6b2a5cabfb49eeb24ff0dcc23896fcb244544b3701f038d0c` |
| `...Round19.zip` | `9ccfe0ad163f2d3418afa9a19f8791bcf04e8c774ed8fd69ed9e21627cc0f167` |
| `...Round20.zip` | `11578f726e614a62a08773e0ed8742022949b754ff12e557064e8975aa1f8913` |
| `...Round21.zip` | `757ebe1ca3d50ee232bc4e92dde3780fb7044924f74de60cb7a24a55d20d6360` |
| `...Round22.zip` | `0422b9ce4f5a8f924855cc1e0e2091df5c976f75e33d87e391abb3801c58fa2f` |
| `...Round23.zip` | `d6a2fc0dda93da9cbc97ff671a1a2da50c3c27e4916451298dd7bad7bcc936a6` |
| `distributedmind.zip` | `fe05b7f112383de52f530a51c7c6527566caf2ccda81153885c11b9b4c72031f` |
| `nanclock.zip` | `b0347e4809b24c2aa1449dbf05348954691d793da33a30263f054387614d52ed` |
| `NaN16_PTC_merged_R15-R23clock.zip` | `debcce32e6820ff5c6ad65573801a91e0b830558c2e22dd3112a05b593e8c002` |

The full machine-readable list is `NaNLM_statespace/ARCHIVE_SHA256.txt`.

## 3. Duplicates and merges

- **Round 5 and 5-1** are byte-identical. Keep both archives; use either
  extracted tree.
- **Round 8 and 8-1** are byte-identical. Same.
- **`distributedmind.zip` is Round 15** plus the compiled `test_r14` binary and
  `include/continuity.hpp`. The binary is not part of the source; the header is
  the important addition.
- **`merged_R15-R17`** merges distributedmind (R15), R16, and R17. Newest file
  wins; byte-identical duplicates removed; older versions kept under
  `_superseded/`.
- **`merged_R15-R18`** adds R18 (`tests/test_round18.cpp`, `docs/ROUND18.md`,
  Makefile target `test18`).
- **No merged R19–R23.** Use the R23 archive as the latest cumulative code.
  R23 includes all tests R4–R23 and the `RuleVmCycle`/Kripke/modal code.
- **No Round 1 archive.** Round 2 contains `BRAINSTORM_1.md` and
  `BRAINSTORM_2.md`; it is the earliest snapshot and the origin of the design.
- **`NaN16_PTC_merged_R15-R23clock.zip`** is the newest merged snapshot: R15–R22 plus the clock-sync experiment (`experiments/r23_clock/clock_sync.py`, `docs/CLOCK_SYNC.md`) and the R18T RNN/transposition experiments.
- **`nanclock.zip` is a companion**, not a round. It is the temporal oscillator
  integrated as the logical clock in `include/nanlm/clock.hpp`.

## 4. Round map

| round | top-level directory | notes |
|---:|---|---|
| 2 | `NaN16_Palindromic_Temporal_Computer_Round2` | Brainstorm 1/2, address orbits |
| 3 | `...Round3` | first topology |
| 4 | `...Round4` | Rule 110, arithmetic, dual fields |
| 5 | `...Round5` | multiplication |
| 5-1 | `...Round5` (duplicate zip) | identical |
| 6 | `...Round6` | signal adder, event-driven |
| 7 | `...Round7` | dual rails |
| 8 | `...Round8` | local dual rules |
| 8-1 | `...Round8` (duplicate zip) | identical |
| 9 | `...Round9` | host-blind gates |
| 10 | `...Round10` | checkpoint suite |
| 11 | `...Round11` | `RuleOpDispatch` |
| 12 | `...Round12` | VM |
| 13 | `...Round13` | 2CM, self-modifying, hierarchy |
| 14 | `...Round14` | cognitive architecture |
| 15 | `distributedmind` | heads, ledger, continuity |
| 16 | `...Round16` | unity |
| 17 | `...Round17` | continuity |
| 18 | `...Round18` | resonance |
| 19 | `...Round19` | hard cognition |
| 20 | `...Round20` | extreme cognition |
| 21 | `...Round21` | formal logic |
| 22 | `...Round22` | puzzles |
| 23 | `...Round23` | modal logic |
| merged | `NaN16_PTC_merged_R15-R17`, `...R15-R18` | merged snapshots |
| clock | `nanclock` | 64-cell temporal oscillator, period-2 orbit |

## 5. Reproduction

The R23 archive was built and tested on Termux aarch64 with Clang:

```sh
cd NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round23/R23
make test
```

Result:

```text
Round 23: 13 passed, 0 failed
```

The nanclock archive is built and tested independently:

```sh
cd NaNLM_statespace/archive/nanclock
make test
```

Result: the period-2 HALT/LOOP orbit and the exact +qNaN/-sNaN bits are
verified.

The new core is built and tested from the repository root:

```sh
make test
./build/nanlm-universal verify
```

Result:

```text
ALL CHECKS PASSED
```

The other round archives were not all re-run in this session. Their
`TEST_RESULTS.txt` files are retained as provenance. A future CI job should run
the canonical R23 suite and a representative R4/R6/R10/R15 regression to keep
the historical behavior honest.

## 6. Canonical snapshot policy

If a future merge is needed:

1. choose the newest version of each file;
2. keep byte-identical duplicates only once;
3. keep older versions under `_superseded/`;
4. never delete a test that documents a claim;
5. never delete a scope note;
6. record the merge in `MERGE_NOTES.md`;
7. re-run the complete test suite;
8. hash the merged tree.

The merged R15-R18 archive is the model for this policy.

## 7. What not to infer from the archives

- The presence of a test does not mean the test is emergent.
- The presence of a `RULE` enum does not mean the rule is local.
- The presence of a VM does not mean the topology is universal.
- The presence of a word "mind" does not mean a mind.
- The presence of a large state count does not mean a large useful state.

The discovery audit ([01_DISCOVERY.md](01_DISCOVERY.md)) is the interpretation
layer. The archives are the raw evidence.
