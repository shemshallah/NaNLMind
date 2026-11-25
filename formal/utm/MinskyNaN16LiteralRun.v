(** * ISA-OBL-3d: literal execution of the full fixture program

    [MinskyNaN16LiteralPuts.v] proves that the literal code region
    [0,99) decodes to [fixture_prog_full], including the [puts] block.
    This file executes that code from the literal image itself.

    The execution is deliberately split into three checked layers:

      - [MinskyNaN16LiteralMachine.v] only defines the literal NaN16
        machine ([lp_run], five-block memory, [lp_exec]);
      - [MinskyNaN16LiteralPrefix.v] certifies the 20,247-instruction
        prefix.  It caches the prefix state as the transparent value
        [literal_run100_valu] and proves
        [literal_run100_matches_nrun100],
        [nrun100_matches_published_trace] and
        [literal_run100_cells] from that cache;
      - [MinskyNaN16LiteralTail01] ... [Tail11] and
        [MinskyNaN16LiteralTail.v] execute the remaining 778
        instructions in eleven checked chunks (100 steps for the first
        five, 50 for the next five, 28 for the last) and derive the
        postcondition lemmas.

    Thus [literal_full_run_pass] is derived from the smaller certified
    prefix/tail facts and the checked native [nrun] fixture result; no
    proof reduces [lp_run 21025 lp_reset] in one VM call.

    Results:

      - [literal_run100_matches_nrun100]: after the [run100] block has
        executed its 100 Minsky steps (20,247 literal instructions,
        ending back at [pc = 7]), the literal state, head and halt cells
        and the 73-cell tape window at [tbase + 128] agree with
        [nrun 100 fixture_table fixture_table_base fixture_tape_base];
      - [literal_full_run_pass]: from the reset state, 21,025 literal
        instructions reach [halted = true] with the PASS output
        ["MTH MINSKY NATIVE PASS"], state 2, head 166, halt 0, and the
        code cells [0,99) unchanged.

    The traditional OBL-RAW-1 phrase "100 steps" refers to the 100
    Minsky table steps, not to 100 literal instructions.  A single table
    step costs roughly 200 literal instructions; the exact fuel figures
    are recorded below. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine
  MinskyNaN16LiteralPrefix MinskyNaN16LiteralTail
  MinskyNaN16LiteralDecode MinskyNaN16LiteralImage
  MinskyNaN16LiteralPuts LiteralImageData MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16RunConcrete MinskyNaN16Run
  MinskyNaN16StepSpec MinskyTable MinskyTableData MinskyNaN16VM.

Open Scope nat_scope.

(** ** The full program, including the PASS check and puts call *)

Definition literal_final : LPState := lp_run 21025 lp_reset.

(** ** The fuel split [21,025 = 20,247 + 778]

    [lp_run] is opaque in this module: the split proof only needs to
    *rewrite* with the already-proved prefix/tail lemmas, never to
    reduce a run.  This also keeps the kernel from unfolding the
    20,247-step prefix while checking the definitional identity
    [literal_run100 = lp_run 20247 lp_reset]. *)

Opaque lp_run.

Lemma literal_final_split :
  literal_final = lp_run 778 literal_run100.
Proof.
  unfold literal_final.
  assert (Hprefix : lp_halted (lp_run 20247 lp_reset) = false).
  { change (lp_halted literal_run100 = false).
    exact (proj1 (proj2 literal_run100_cells)). }
  replace 21025 with (20247 + 778) by reflexivity.
  rewrite (lp_run_add 20247 778 lp_reset Hprefix).
  change (lp_run 778 literal_run100 = lp_run 778 literal_run100).
  reflexivity.
Qed.

Theorem literal_full_run_pass :
  lp_halted literal_final = true /\
  lp_pc literal_final = 28 /\
  payload_word (mem_get (lp_mem literal_final) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_final) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_final) action_halt_addr) = 0 /\
  lp_out literal_final = pass_string /\
  lget_reg (lp_reg literal_final) 1 = 4357 /\
  code_preserved_bool (lp_mem literal_final) = true.
Proof.
  rewrite literal_final_split.
  rewrite literal_tail_compose.
  exact literal_tail_pass.
Qed.

(** ** Full-image statement *)

Theorem literal_image_code_and_pass :
  decode_range_p 0 99 = Some fixture_prog_full /\
  List.length literal_image = 4366 /\
  lp_halted literal_final = true /\
  lp_out literal_final = pass_string /\
  payload_word (mem_get (lp_mem literal_final) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_final) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_final) action_halt_addr) = 0 /\
  code_preserved_bool (lp_mem literal_final) = true.
Proof.
  destruct literal_full_code_decodes as [Hlen [Hdec Hplen]].
  destruct literal_full_run_pass as
    (Hh & Hpc & Hs & Hhd & Hht & Hout & Hr1 & Hcode).
  repeat split; assumption.
Qed.

(** ** Assumption audit *)

Print Assumptions literal_run100_matches_nrun100.
Print Assumptions nrun100_matches_published_trace.
Print Assumptions literal_run100_cells.
Print Assumptions literal_full_run_pass.
Print Assumptions literal_image_code_and_pass.
