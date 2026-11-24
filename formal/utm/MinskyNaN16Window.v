From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyAddressRefinement.

(** A finite nonnegative window for a signed tape coordinate.  The VM's
    flat memory stores the source cell at [z] at address [base + (z + K)].
    The depth [K] is the left-window shift used by the final theorem. *)

Definition win_addr (base : nat) (K : nat) (z : Z) : nat :=
  Nat.add base (Z.to_nat (z + Z.of_nat K)).

Definition win_mem (c : AddressConfig) (base : nat) (K : nat) : nat -> nat :=
  fun k => a_tape c (Z.of_nat (Nat.sub k base) - Z.of_nat K).

Lemma win_addr_ge_base :
  forall (base K : nat) (z : Z), Nat.le base (win_addr base K z).
Proof. intros. unfold win_addr. lia. Qed.

Lemma win_addr_inj :
  forall (base K : nat) (z1 z2 : Z),
    (0 <= z1 + Z.of_nat K)%Z ->
    (0 <= z2 + Z.of_nat K)%Z ->
    win_addr base K z1 = win_addr base K z2 ->
    z1 = z2.
Proof.
  intros base K z1 z2 H1 H2 H.
  unfold win_addr in H.
  assert (Hn : Z.to_nat (z1 + Z.of_nat K) = Z.to_nat (z2 + Z.of_nat K))
    by lia.
  apply (f_equal Z.of_nat) in Hn.
  rewrite Z2Nat.id in Hn by exact H1.
  rewrite Z2Nat.id in Hn by exact H2.
  lia.
Qed.

Lemma win_mem_addr :
  forall (c : AddressConfig) (base K : nat) (z : Z),
    (0 <= z + Z.of_nat K)%Z ->
    win_mem c base K (win_addr base K z) = a_tape c z.
Proof.
  intros c base K z H.
  unfold win_mem, win_addr.
  replace (Nat.sub (Nat.add base (Z.to_nat (z + Z.of_nat K))) base)
    with (Z.to_nat (z + Z.of_nat K)) by lia.
  rewrite Z2Nat.id by exact H.
  replace (z + Z.of_nat K - Z.of_nat K) with z by lia.
  reflexivity.
Qed.

Lemma win_mem_write :
  forall (c : AddressConfig) (base K : nat) (h : Z) (v : nat),
    (0 <= h + Z.of_nat K)%Z ->
    forall z,
      (0 <= z + Z.of_nat K)%Z ->
      win_mem
        {| a_state := a_state c; a_head := a_head c;
           a_tape := write_at (a_tape c) h v;
           a_halted := a_halted c |} base K (win_addr base K z) =
      (if Z.eqb z h then v else a_tape c z).
Proof.
  intros c base K h v Hh z Hz.
  unfold win_mem, win_addr.
  replace (Nat.sub (Nat.add base (Z.to_nat (z + Z.of_nat K))) base)
    with (Z.to_nat (z + Z.of_nat K)) by lia.
  rewrite Z2Nat.id by exact Hz.
  replace (z + Z.of_nat K - Z.of_nat K) with z by lia.
  unfold write_at. reflexivity.
Qed.

Lemma win_mem_write_at_eq :
  forall c base K h v,
    (0 <= h + Z.of_nat K)%Z ->
    win_mem
      {| a_state := a_state c; a_head := a_head c;
         a_tape := write_at (a_tape c) h v;
         a_halted := a_halted c |} base K (win_addr base K h) = v.
Proof.
  intros c base K h v H.
  rewrite win_mem_write by exact H.
  rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma win_mem_write_at :
  forall (c : AddressConfig) (base K : nat) (h : Z) (v : nat),
    (0 <= h + Z.of_nat K)%Z ->
    forall z,
      (0 <= z + Z.of_nat K)%Z ->
      win_mem
        {| a_state := a_state c; a_head := a_head c;
           a_tape := write_at (a_tape c) h v;
           a_halted := a_halted c |} base K (win_addr base K z) =
      (if Z.eqb z h then v else win_mem c base K (win_addr base K z)).
Proof.
  intros c base K h v Hh z Hz.
  rewrite (win_mem_write c base K h v Hh z Hz).
  destruct (Z.eqb z h) eqn:E.
  - reflexivity.
  - rewrite win_mem_addr by exact Hz. reflexivity.
Qed.
