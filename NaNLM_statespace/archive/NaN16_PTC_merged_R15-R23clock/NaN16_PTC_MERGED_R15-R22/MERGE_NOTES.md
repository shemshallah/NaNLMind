# Merge notes (R15-R22)

Sources merged: distributedmind.zip (= Round15), Round16, Round17, my earlier merge R15-R18, Round20, Round21, Round22.
Rule: newest version of each file wins (order R15 < R16 < R17 < R20 < R21 < R22); byte-identical duplicates removed; older differing versions kept under `_superseded/<source>/`.

## Naming collision resolved
Two different "Round 18"s existed:
- R20-R22 lineage: "Resonance + deep cognition" -> tests/test_round18.cpp, docs/ROUND18.md (kept as-is).
- Mine: transposition correspondence + learning -> renamed Round 18T:
  tests/test_round18t_transposition.cpp, docs/ROUND18T_TRANSPOSITION.md, docs/ROUND18T_SUMMARY.md, docs/ROUND18T_CONTROL.md, experiments/r18t_rnn/.

## Build / test
make test        # round 22 (latest)
make test18t     # round 18T transposition (12/12 pass, built against the R22 library)
make test-all    # all rounds 4-22 + 18T (not run end-to-end by me in this merge; round 22 and 18T were run and pass)

## Not done
- Did not run every historical round's test against the R22 header; run `make test-all` to check for regressions.
- Control experiment partially complete (see docs/ROUND18T_CONTROL.md).
- Dropped compiled binary test_r14 (from Round15).

Added: docs/CLOCK_SYNC.md, experiments/r23_clock/.
