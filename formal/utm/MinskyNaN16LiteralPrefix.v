(** * ISA-OBL-3d: cached 20,247-instruction literal prefix

    The full-fixture literal execution is split at [20247] instructions:

      - [literal_run100_valu] is the already-certified 20,247-step
        prefix run, cached as a transparent value.  The cache is built
        by a VM reduction in this module only, so later modules never
        re-evaluate the prefix;
      - the remaining 778 instructions (the published-trace check and
        the [puts] call) are evaluated in [MinskyNaN16LiteralTail.v].

    The prefix cache is exactly the computation performed by
    [literal_run100_matches_nrun100] and [literal_run100_cells] in the
    previous monolithic file; the difference is that the computed state
    is now a reusable value instead of being recomputed in every proof. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts LiteralImageData
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  MinskyNaN16Run MinskyNaN16StepSpec MinskyTable MinskyTableData
  MinskyNaN16VM.

Open Scope nat_scope.

(** ** The cached prefix value

    [let x := eval vm_compute in ...] stores the normal form as the
    transparent body of [literal_run100_valu].  It is a checked Coq VM
    reduction (the same one used by the old prefix theorems), performed
    in this module's worker. *)

Definition literal_run100_valu : LPState.
Proof.
  let x := eval vm_compute in (lp_run 20247 lp_reset) in
  exact x.
Defined.

(** The cache is the prefix run.  [vm_compute] performs the single VM
    reduction of [lp_run 20247 lp_reset]; the right-hand side is already
    a normal form, so [reflexivity] is cheap. *)

Lemma literal_run100_valu_spec : literal_run100 = literal_run100_valu.
Proof. vm_compute. reflexivity. Qed.

(** ** The 100 Minsky steps, derived from the cache *)

Theorem literal_run100_matches_nrun100 :
  lp_pc literal_run100 = 7 /\
  payload_word (mem_get (lp_mem literal_run100) action_state_addr) =
    n_state nrun100 /\
  payload_word (mem_get (lp_mem literal_run100) action_head_addr) =
    n_head nrun100 /\
  payload_word (mem_get (lp_mem literal_run100) action_halt_addr) =
    n_halt nrun100 /\
  map (fun i =>
         payload_word
           (mem_get (lp_mem literal_run100)
              (fixture_tape_base + 128 + i)))
      (seq 0 73) =
  map (fun i => n_mem nrun100 (fixture_tape_base + 128 + i)) (seq 0 73).
Proof.
  rewrite literal_run100_valu_spec.
  vm_compute. repeat split; reflexivity.
Qed.

(** The native run agrees with the published table trace: state 2,
    head 166, halt 0, and the 73-cell expected tape window. *)

Theorem nrun100_matches_published_trace :
  n_state nrun100 = 2 /\
  n_head nrun100 = 166 /\
  n_halt nrun100 = 0 /\
  map (fun i => n_mem nrun100 (fixture_tape_base + 128 + i)) (seq 0 73)
    = expected_cells.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

Theorem literal_run100_cells :
  lp_pc literal_run100 = 7 /\
  lp_halted literal_run100 = false /\
  payload_word (mem_get (lp_mem literal_run100) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_run100) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_run100) action_halt_addr) = 0 /\
  map (fun i =>
         payload_word
           (mem_get (lp_mem literal_run100)
              (fixture_tape_base + 128 + i)))
      (seq 0 73) = expected_cells.
Proof.
  rewrite literal_run100_valu_spec.
  vm_compute. repeat split; reflexivity.
Qed.

Print Assumptions literal_run100_valu_spec.
Print Assumptions literal_run100_matches_nrun100.
Print Assumptions nrun100_matches_published_trace.
Print Assumptions literal_run100_cells.
