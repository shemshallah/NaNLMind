(** * ISA-OBL-3d: literal tail chunk 10 (50 instructions, steps 700..750)

    Executes literal instructions [700, 750) of the 778-instruction tail
    that follows the cached 20,247-instruction prefix, starting from
    chunk 09.  The chunk state is cached as a transparent
    [vm_compute] value, so later chunks only ever reduce their own
    instructions and never re-evaluate an earlier chunk or the prefix. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine MinskyNaN16LiteralTail09.

Open Scope nat_scope.

Definition literal_tail10 : LPState.
Proof.
  let x := eval vm_compute in (lp_run 50 literal_tail9) in
  exact x.
Defined.

(** The chunk is exactly the next 50 instructions of the tail. *)

Lemma literal_tail10_spec : lp_run 50 literal_tail9 = literal_tail10.
Proof. vm_compute. reflexivity. Qed.

(** The run has not halted inside this chunk. *)

Lemma literal_tail10_halted : lp_halted literal_tail10 = false.
Proof. vm_compute. reflexivity. Qed.

Print Assumptions literal_tail10_spec.
Print Assumptions literal_tail10_halted.
