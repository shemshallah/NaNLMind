From NaNLM Require Import MinskyLeftInfiniteClockRun.

Set Printing All.
Redirect "certificates/lic_lifted_halting_equivalence.statement.txt.out"
  Check lic_lifted_halting_equivalence.
Redirect "certificates/lic_lifted_halting_equivalence.assumptions.txt.out"
  Print Assumptions lic_lifted_halting_equivalence.
Redirect "certificates/lic_lifted_halting_equivalence.proofterm.txt.out"
  Print lic_lifted_halting_equivalence.
