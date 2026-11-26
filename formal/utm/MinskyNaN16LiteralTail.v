(** * ISA-OBL-3d: composition of the 778-instruction literal tail

    The eleven chunk modules [MinskyNaN16LiteralTail01] ...
    [MinskyNaN16LiteralTail11] execute the tail that follows the cached
    20,247-instruction prefix, 100 then 50 literal instructions at a
    time.  The smaller final chunks keep the puts phase well inside the
    reducer's working set.  This file only composes their equalities;
    it performs no run reduction.

    The split point is [20247 + 778 = 21025].  The last chunk reaches
    [halted = true] with the PASS output, state 2, head 166, halt 0 and
    the code block unchanged. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine
  MinskyNaN16LiteralPrefix
  MinskyNaN16LiteralTail01 MinskyNaN16LiteralTail02
  MinskyNaN16LiteralTail03 MinskyNaN16LiteralTail04
  MinskyNaN16LiteralTail05 MinskyNaN16LiteralTail06
  MinskyNaN16LiteralTail07 MinskyNaN16LiteralTail08
  MinskyNaN16LiteralTail09 MinskyNaN16LiteralTail10
  MinskyNaN16LiteralTail11 MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts LiteralImageData
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  MinskyNaN16Run MinskyNaN16StepSpec MinskyTable MinskyTableData
  MinskyNaN16VM.

Open Scope nat_scope.

(** ** Fuel composition across the eleven chunks *)

Lemma literal_tail_compose :
  lp_run 778 literal_run100 = literal_tail11.
Proof.
  assert (H1 : lp_halted (lp_run 100 literal_run100) = false)
    by (rewrite literal_tail1_spec; exact literal_tail1_halted).
  assert (H2 : lp_halted (lp_run 100 literal_tail1) = false)
    by (rewrite literal_tail2_spec; exact literal_tail2_halted).
  assert (H3 : lp_halted (lp_run 100 literal_tail2) = false)
    by (rewrite literal_tail3_spec; exact literal_tail3_halted).
  assert (H4 : lp_halted (lp_run 100 literal_tail3) = false)
    by (rewrite literal_tail4_spec; exact literal_tail4_halted).
  assert (H5 : lp_halted (lp_run 100 literal_tail4) = false)
    by (rewrite literal_tail5_spec; exact literal_tail5_halted).
  assert (H6 : lp_halted (lp_run 50 literal_tail5) = false)
    by (rewrite literal_tail6_spec; exact literal_tail6_halted).
  assert (H7 : lp_halted (lp_run 50 literal_tail6) = false)
    by (rewrite literal_tail7_spec; exact literal_tail7_halted).
  assert (H8 : lp_halted (lp_run 50 literal_tail7) = false)
    by (rewrite literal_tail8_spec; exact literal_tail8_halted).
  assert (H9 : lp_halted (lp_run 50 literal_tail8) = false)
    by (rewrite literal_tail9_spec; exact literal_tail9_halted).
  assert (H10 : lp_halted (lp_run 50 literal_tail9) = false)
    by (rewrite literal_tail10_spec; exact literal_tail10_halted).
  replace 778 with (100 + 678) by reflexivity.
  rewrite (lp_run_add 100 678 literal_run100 H1).
  rewrite literal_tail1_spec.
  replace 678 with (100 + 578) by reflexivity.
  rewrite (lp_run_add 100 578 literal_tail1 H2).
  rewrite literal_tail2_spec.
  replace 578 with (100 + 478) by reflexivity.
  rewrite (lp_run_add 100 478 literal_tail2 H3).
  rewrite literal_tail3_spec.
  replace 478 with (100 + 378) by reflexivity.
  rewrite (lp_run_add 100 378 literal_tail3 H4).
  rewrite literal_tail4_spec.
  replace 378 with (100 + 278) by reflexivity.
  rewrite (lp_run_add 100 278 literal_tail4 H5).
  rewrite literal_tail5_spec.
  replace 278 with (50 + 228) by reflexivity.
  rewrite (lp_run_add 50 228 literal_tail5 H6).
  rewrite literal_tail6_spec.
  replace 228 with (50 + 178) by reflexivity.
  rewrite (lp_run_add 50 178 literal_tail6 H7).
  rewrite literal_tail7_spec.
  replace 178 with (50 + 128) by reflexivity.
  rewrite (lp_run_add 50 128 literal_tail7 H8).
  rewrite literal_tail8_spec.
  replace 128 with (50 + 78) by reflexivity.
  rewrite (lp_run_add 50 78 literal_tail8 H9).
  rewrite literal_tail9_spec.
  replace 78 with (50 + 28) by reflexivity.
  rewrite (lp_run_add 50 28 literal_tail9 H10).
  rewrite literal_tail10_spec.
  rewrite literal_tail11_spec.
  reflexivity.
Qed.

(** ** Postconditions of the fully executed tail *)

Theorem literal_tail_pass :
  lp_halted literal_tail11 = true /\
  lp_pc literal_tail11 = 28 /\
  payload_word (mem_get (lp_mem literal_tail11) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_tail11) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_tail11) action_halt_addr) = 0 /\
  lp_out literal_tail11 = pass_string /\
  lget_reg (lp_reg literal_tail11) 1 = 4357 /\
  code_preserved_bool (lp_mem literal_tail11) = true.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

Print Assumptions literal_tail_compose.
Print Assumptions literal_tail_pass.
