# Provenance archive

This directory contains the original NaN16 Palindromic Temporal Computer
archives and their extracted snapshots.

```
NaNLM_statespace/
  *.zip                  original archives (28 files)
  ARCHIVE_SHA256.txt     SHA-256 manifest
  archive/
    <archive-stem>/      one extracted tree per archive
```

The extraction is deliberately one directory per archive, so duplicate round
names never overwrite each other:

- `Round5.zip` and `Round5-1.zip` are byte-identical;
- `Round8.zip` and `Round8-1.zip` are byte-identical;
- `distributedmind.zip` is Round 15;
- `merged_R15-R17` and `merged_R15-R18` are merged snapshots;
- there is no Round 1 archive; Round 2 contains `BRAINSTORM_1.md` and
  `BRAINSTORM_2.md`;
- `NaN16_PTC_merged_R15-R23clock.zip` is the newest merged snapshot (R15–R22 + clock-sync + R18T RNN experiments);
- `nanclock.zip` is the independent temporal oscillator (64 cells, LE/PAST and
  BE/FUTURE boundaries, period-2 HALT/LOOP orbit).

## Where to start

1. `archive/NaN16_Palindromic_Temporal_Computer_Round2/.../BRAINSTORM_1.md`
2. `archive/NaN16_Palindromic_Temporal_Computer_Round2/.../BRAINSTORM_2.md`
3. `archive/NaN16_Palindromic_Temporal_Computer_Round23/R23/` — latest
   cumulative code and tests.
4. `docs/01_DISCOVERY.md` — the round-by-round audit.
5. `docs/12_PROVENANCE.md` — hashes, duplicates, and the round map.

## Rebuild the latest archive

```sh
cd archive/NaN16_Palindromic_Temporal_Computer_Round23/R23
make test
```

The new clean core is at the repository root:

```sh
make test
./build/nanlm-universal verify
```
