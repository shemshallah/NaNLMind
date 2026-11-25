(** * ISA-OBL-3d: literal tail chunk 01 (100 instructions, steps 0..100)

    Executes literal instructions [0, 100) of the 778-instruction tail
    that follows the cached 20,247-instruction prefix, starting from
    the cached 20,247-instruction prefix state.  The chunk state is cached as a transparent
    [vm_compute] value, so later chunks only ever reduce their own
    instructions and never re-evaluate an earlier chunk or the prefix. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine
  MinskyNaN16LiteralPrefix.

Open Scope nat_scope.

Definition literal_tail1 : LPState.
Proof.
  let x := eval vm_compute in (lp_run 100 literal_run100_valu) in
  exact x.
Defined.

(** The chunk is exactly the next 100 instructions of the tail. *)

Lemma literal_tail1_spec : lp_run 100 literal_run100 = literal_tail1.
Proof.
  rewrite literal_run100_valu_spec.
  vm_compute.
  reflexivity.
Qed.

(** The run has not halted inside this chunk. *)

Lemma literal_tail1_halted : lp_halted literal_tail1 = false.
Proof. vm_compute. reflexivity. Qed.

Print Assumptions literal_tail1_spec.
Print Assumptions literal_tail1_halted.
