(** * ISA-OBL-3d: literal tail chunk 11 (28 instructions, steps 750..778)

    Executes literal instructions [750, 778) of the 778-instruction tail
    that follows the cached 20,247-instruction prefix, starting from
    chunk 10.  The chunk state is cached as a transparent
    [vm_compute] value, so later chunks only ever reduce their own
    instructions and never re-evaluate an earlier chunk or the prefix. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16LiteralMachine MinskyNaN16LiteralTail10.

Open Scope nat_scope.

Definition literal_tail11 : LPState.
Proof.
  let x := eval vm_compute in (lp_run 28 literal_tail10) in
  exact x.
Defined.

(** The chunk is exactly the next 28 instructions of the tail. *)

Lemma literal_tail11_spec : lp_run 28 literal_tail10 = literal_tail11.
Proof. vm_compute. reflexivity. Qed.

(** This final chunk reaches the halted PASS state; the
    postconditions are stated in [MinskyNaN16LiteralTail.v]. *)

Print Assumptions literal_tail11_spec.
