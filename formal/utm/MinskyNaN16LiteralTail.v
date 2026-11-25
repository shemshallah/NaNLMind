(** * ISA-OBL-3d: the 778-instruction literal tail

    After the 20,247-instruction prefix certified in
    [MinskyNaN16LiteralPrefix.v], the literal program is at [pc = 7]
    (just after the [run100] call returned) with the published trace
    already checked by [nrun100_matches_published_trace]:

      state 2, head 166, halt 0, and the 73-cell tape window
      [4224, 4297) equal to [expected_cells].

    The remaining 778 instructions are the main PASS check over that
    window and the [puts] call that emits
    ["MTH MINSKY NATIVE PASS"].  They read only fixed cells of the
    already-cached prefix state, so they are evaluated here on the
    transparent cache, never on [lp_run 21025 lp_reset]. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine
  MinskyNaN16LiteralPrefix MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts LiteralImageData
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  MinskyNaN16Run MinskyNaN16StepSpec MinskyTable MinskyTableData
  MinskyNaN16VM.

Open Scope nat_scope.

(** ** The cached tail value *)

Definition literal_tail : LPState.
Proof.
  let x := eval vm_compute in (lp_run 778 literal_run100_valu) in
  exact x.
Defined.

(** The tail of the certified prefix run is the cached value. *)

Lemma literal_tail_spec : lp_run 778 literal_run100 = literal_tail.
Proof.
  rewrite literal_run100_valu_spec.
  vm_compute. reflexivity.
Qed.

(** ** The full-run postconditions, computed on the small tail state *)

Theorem literal_tail_pass :
  lp_halted literal_tail = true /\
  lp_pc literal_tail = 28 /\
  payload_word (mem_get (lp_mem literal_tail) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_tail) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_tail) action_halt_addr) = 0 /\
  lp_out literal_tail = pass_string /\
  lget_reg (lp_reg literal_tail) 1 = 4357 /\
  code_preserved_bool (lp_mem literal_tail) = true.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

Print Assumptions literal_tail_spec.
Print Assumptions literal_tail_pass.
