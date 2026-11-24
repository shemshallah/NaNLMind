From NaNLM Require Import MinskyNaN16Words.

Set Printing All.
Redirect "certificates/nan16-table/nan16_lookup_agrees_all.statement.txt.out"
  Check nan16_lookup_agrees_all.
Redirect "certificates/nan16-table/nan16_sixbyte_lookup_agree.statement.txt.out"
  Check nan16_sixbyte_lookup_agree.
Redirect "certificates/nan16-table/nan16_address_step_refines.statement.txt.out"
  Check nan16_address_step_refines.
Redirect "certificates/nan16-table/nan16_address_run_refines.statement.txt.out"
  Check nan16_address_run_refines.
Redirect "certificates/nan16-table/nan16_zipper_run_bisim.statement.txt.out"
  Check nan16_zipper_run_bisim.

Redirect "certificates/nan16-table/nan16_lookup_agrees_all.assumptions.txt.out"
  Print Assumptions nan16_lookup_agrees_all.
Redirect "certificates/nan16-table/nan16_sixbyte_lookup_agree.assumptions.txt.out"
  Print Assumptions nan16_sixbyte_lookup_agree.
Redirect "certificates/nan16-table/nan16_address_step_refines.assumptions.txt.out"
  Print Assumptions nan16_address_step_refines.
Redirect "certificates/nan16-table/nan16_address_run_refines.assumptions.txt.out"
  Print Assumptions nan16_address_run_refines.
Redirect "certificates/nan16-table/nan16_zipper_run_bisim.assumptions.txt.out"
  Print Assumptions nan16_zipper_run_bisim.
