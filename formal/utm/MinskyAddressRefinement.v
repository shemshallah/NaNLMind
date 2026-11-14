(** * Address-based Minsky interpreter refinement

    The earlier MinskyTable model uses a two-list tape zipper. The native
    C++ interpreter instead stores tape symbols at signed integer addresses,
    with a separate head coordinate and halted flag. This file supplies
    an address-based formal transition system using the SAME checked 184
    transitions, with no host interpreter in the proof.

    Every state/symbol lookup and every fuel-bounded execution of the
    indexed model is equal to the linear-scan model, including malformed
    inputs, halting writes, and negative tape addresses. It also checks
    the published trace independently in address space.

    This is a proof about the abstract address-tape semantics. The actual
    C++ chart-page allocator, compiler and machine code remain separate
    obligations, and no C++ binary-verification claim is made here.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTable MinskyTableData.

Record AddressConfig := {
  a_state : nat;
  a_head : Z;
  a_tape : Z -> nat;
  a_halted : bool
}.

Definition write_at (t : Z -> nat) (head : Z) (symbol : nat) : Z -> nat :=
  fun p => if Z.eqb p head then symbol else t p.

Lemma write_at_head :
  forall t h s, write_at t h s h = s.
Proof.
  intros t h s. unfold write_at.
  rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma write_at_frame :
  forall t h s p, p <> h -> write_at t h s p = t p.
Proof.
  intros t h s p Hne. unfold write_at.
  apply Z.eqb_neq in Hne. rewrite Hne. reflexivity.
Qed.

Definition address_halt (c : AddressConfig) : AddressConfig :=
  {| a_state := a_state c;
     a_head := a_head c;
     a_tape := a_tape c;
     a_halted := true |}.

(** This is the observable transition order in
    [UniversalTuringMachine::step]: read, scan, write, set state, move head,
    then set the halt flag. Missing transitions halt without writing. *)
Definition address_step_with
    (lookup : nat -> nat -> option Entry) (c : AddressConfig) : AddressConfig :=
  if a_halted c then c
  else
    match lookup (a_state c) (a_tape c (a_head c)) with
    | None => address_halt c
    | Some e =>
        {| a_state := e_to e;
           a_head := a_head c + e_move e;
           a_tape := write_at (a_tape c) (a_head c) (e_write e);
           a_halted := e_halt e |}
    end.

Definition address_step_indexed : AddressConfig -> AddressConfig :=
  address_step_with find_entry.

Definition address_step_scanned : AddressConfig -> AddressConfig :=
  address_step_with scan_table.

Theorem address_step_refines :
  forall c, address_step_indexed c = address_step_scanned c.
Proof.
  intros c. unfold address_step_indexed, address_step_scanned,
    address_step_with.
  destruct (a_halted c); [reflexivity |].
  rewrite find_entry_scan_all. reflexivity.
Qed.

Fixpoint address_run (fuel : nat)
    (transition : AddressConfig -> AddressConfig) (c : AddressConfig) :
    AddressConfig :=
  match fuel with
  | 0%nat => c
  | S n =>
      if a_halted c then c
      else address_run n transition (transition c)
  end.

Theorem address_run_refines :
  forall fuel c,
    address_run fuel address_step_indexed c =
    address_run fuel address_step_scanned c.
Proof.
  induction fuel as [|n IH]; intros c; simpl.
  - reflexivity.
  - destruct (a_halted c); [reflexivity |].
    rewrite (address_step_refines c). apply IH.
Qed.

Theorem address_halt_writes_before_flag :
  forall c e,
    a_halted c = false ->
    find_entry (a_state c) (a_tape c (a_head c)) = Some e ->
    e_halt e = true ->
    address_step_indexed c =
      {| a_state := e_to e;
         a_head := a_head c + e_move e;
         a_tape := write_at (a_tape c) (a_head c) (e_write e);
         a_halted := true |}.
Proof.
  intros c e Hrunning Hentry Hhalt.
  unfold address_step_indexed, address_step_with.
  rewrite Hrunning, Hentry, Hhalt. reflexivity.
Qed.

(** Initial memory is the published Minsky tape at absolute positions
    0..72; all other signed positions contain the blank symbol 2. *)
Definition list_tape (cells : list nat) : Z -> nat :=
  fun p => if (p <? 0)%Z then blank
           else nth (Z.to_nat p) cells blank.

Definition initial_address_config : AddressConfig :=
  {| a_state := 5;
     a_head := 38;
     a_tape := list_tape initial_cells;
     a_halted := false |}.

Definition trace_final_ok (c : AddressConfig) : bool :=
  Nat.eqb (a_state c) 2 &&
  Z.eqb (a_head c) 38 &&
  negb (a_halted c) &&
  forallb (fun i : nat =>
    Nat.eqb (a_tape c (Z.of_nat i)) (nth i expected_cells blank))
    (seq 0 73).

(** A second, independent kernel computation of the 100-step reference
    trace, now using signed-address functional tape representation. *)
Theorem address_trace_100 :
  trace_final_ok (address_run 100 address_step_indexed
                    initial_address_config) = true.
Proof. vm_compute. reflexivity. Qed.

Corollary address_trace_100_scanned :
  trace_final_ok (address_run 100 address_step_scanned
                    initial_address_config) = true.
Proof.
  rewrite <- (address_run_refines 100 initial_address_config).
  exact address_trace_100.
Qed.

Print Assumptions address_step_refines.
Print Assumptions address_run_refines.
Print Assumptions address_halt_writes_before_flag.
Print Assumptions address_trace_100.
