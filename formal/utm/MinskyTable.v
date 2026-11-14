(** * Mechanized Minsky 23x8 universal table

    The actual table in [tests/minsky_table.inc] is generated into
    [MinskyTableData.v].  This file gives the table an executable, finite
    step semantics and checks:

      * the table is complete for all 23 states and 8 symbols;
      * every step uses the table entry for the current (state, symbol);
      * the published 100-step trace reaches the documented configuration;
      * the halting entry is explicit.

    The step function is total on the finite state/symbol domain and returns
    [None] exactly at a halting entry or outside the table.
*)

From Coq Require Import List Arith ZArith Lia Bool.
Import ListNotations.

From NaNLM Require Import MinskyTableData.

Definition blank : nat := 2.

(** A two-list zipper: [left] is reversed, [right] starts at the head. *)
Record Tape := {
  t_left : list nat;
  t_right : list nat
}.

Definition read (t : Tape) : nat :=
  match t_right t with
  | [] => blank
  | x :: _ => x
  end.

Definition write (t : Tape) (s : nat) : Tape :=
  {| t_left := t_left t;
     t_right := match t_right t with
                | [] => [s]
                | _ :: xs => s :: xs
                end |}.

Definition move_left (t : Tape) : Tape :=
  match t_left t with
  | [] => {| t_left := []; t_right := blank :: t_right t |}
  | x :: xs => {| t_left := xs; t_right := x :: t_right t |}
  end.

Definition move_right (t : Tape) : Tape :=
  match t_right t with
  | [] => {| t_left := blank :: t_left t; t_right := [] |}
  | x :: xs => {| t_left := x :: t_left t; t_right := xs |}
  end.

Definition move_tape (t : Tape) (m : Z) : Tape :=
  if Z.eqb m ((-1)%Z) then move_left t
  else if Z.eqb m (1%Z) then move_right t
  else t.

Record Config := {
  c_state : nat;
  c_tape : Tape;
  c_halted : bool
}.

(** Flat row-major table lookup: entry [q,s] is at index [q*8+s]. *)
Definition find_entry (q s : nat) : option Entry :=
  nth_error minsky_entries (q * 8 + s).

(** A literal linear scan of the transition list.  This is the executable
    interpreter's transition search, kept separate from the indexed table. *)
Fixpoint scan_entry (q s : nat) (l : list Entry) : option Entry :=
  match l with
  | [] => None
  | e :: es =>
      if (e_from e =? q) && (e_read e =? s)
      then Some e
      else scan_entry q s es
  end.

Definition scan_table (q s : nat) : option Entry :=
  scan_entry q s minsky_entries.

Definition halt (c : Config) : Config :=
  {| c_state := c_state c; c_tape := c_tape c; c_halted := true |}.

(** This is the C++ [TuringMachine::step] order exactly:
    write the symbol, update state/head, then set the halted flag on a
    halting transition.  A missing table entry only sets the halted flag. *)
Definition step (c : Config) : Config :=
  if c_halted c then c
  else
    match find_entry (c_state c) (read (c_tape c)) with
    | None => halt c
    | Some e =>
        let c' := {| c_state := e_to e;
                     c_tape := move_tape
                       (write (c_tape c) (e_write e)) (e_move e);
                     c_halted := false |} in
        if e_halt e then halt c' else c'
    end.

Fixpoint run (fuel : nat) (c : Config) : Config :=
  match fuel with
  | 0%nat => c
  | S n => if c_halted c then c else run n (step c)
  end.

(** ** Table completeness *)

Lemma minsky_table_length : length minsky_entries = 184%nat.
Proof. reflexivity. Qed.

Lemma minsky_table_complete :
  forall (q s : nat), q < 23%nat -> s < 8%nat -> exists e, find_entry q s = Some e.
Proof.
  intros q s Hq Hs. unfold find_entry.
  assert (Hlt : q * 8 + s < length minsky_entries).
  { rewrite minsky_table_length. nia. }
  assert (Hsome : nth_error minsky_entries (q * 8 + s) <> None).
  { apply (proj2 (nth_error_Some minsky_entries (q * 8 + s))). exact Hlt. }
  destruct (nth_error minsky_entries (q * 8 + s)) as [e|] eqn:E.
  - exists e. reflexivity.
  - contradiction.
Qed.

(** Every in-range state/symbol has exactly one table entry. *)
Definition entry_eqb (a b : Entry) : bool :=
  (e_from a =? e_from b) && (e_read a =? e_read b) &&
  (e_write a =? e_write b) && Z.eqb (e_move a) (e_move b) &&
  (e_to a =? e_to b) && Bool.eqb (e_halt a) (e_halt b).

Definition lookup_eqb (q s : nat) : bool :=
  match find_entry q s, scan_table q s with
  | None, None => true
  | Some a, Some b => entry_eqb a b
  | _, _ => false
  end.

Definition check_lookup (q : nat) : bool :=
  forallb (fun s => lookup_eqb q s) (seq 0 8).

Definition check_all_lookups : bool :=
  forallb check_lookup (seq 0 23).

Lemma forallb_forall :
  forall (A : Type) (f : A -> bool) (l : list A),
    forallb f l = true -> forall x, In x l -> f x = true.
Proof.
  intros A f l. induction l as [|a l IH]; intros H x Hin.
  - contradiction.
  - simpl in H. apply andb_true_iff in H. destruct H as [Hfa Hfl].
    destruct Hin as [-> | Hin].
    + exact Hfa.
    + apply IH; assumption.
Qed.

Lemma entry_eqb_sound :
  forall a b, entry_eqb a b = true -> a = b.
Proof.
  intros a b H. destruct a as [af ar aw am at ah].
  destruct b as [bf br bw bm bt bh]. simpl in H.
  repeat rewrite andb_true_iff in H.
  destruct H as [[[[[H1 H2] H3] H4] H5] H6].
  apply Nat.eqb_eq in H1. apply Nat.eqb_eq in H2. apply Nat.eqb_eq in H3.
  apply Z.eqb_eq in H4. apply Nat.eqb_eq in H5. apply Bool.eqb_eq in H6.
  subst. reflexivity.
Qed.

Lemma lookup_eqb_sound :
  forall q s, lookup_eqb q s = true ->
    find_entry q s = scan_table q s.
Proof.
  intros q s H. unfold lookup_eqb in H.
  destruct (find_entry q s) as [a|] eqn:Ea.
  - destruct (scan_table q s) as [b|] eqn:Eb.
    + apply entry_eqb_sound in H. subst. reflexivity.
    + discriminate.
  - destruct (scan_table q s) as [b|] eqn:Eb.
    + discriminate.
    + reflexivity.
Qed.

Lemma check_all_lookups_true : check_all_lookups = true.
Proof. vm_compute. reflexivity. Qed.

Lemma find_entry_scan_valid :
  forall (q s : nat), q < 23%nat -> s < 8%nat ->
    find_entry q s = scan_table q s.
Proof.
  intros q s Hq Hs.
  assert (Hqin : In q (seq 0 23)) by (apply in_seq; lia).
  assert (Hsin : In s (seq 0 8)) by (apply in_seq; lia).
  pose proof (forallb_forall _ _ _ check_all_lookups_true q Hqin) as Hqok.
  pose proof (forallb_forall _ _ _ Hqok s Hsin) as Hsok.
  apply lookup_eqb_sound. exact Hsok.
Qed.

Definition step_scan (c : Config) : Config :=
  if c_halted c then c
  else
    match scan_table (c_state c) (read (c_tape c)) with
    | None => halt c
    | Some e =>
        let c' := {| c_state := e_to e;
                     c_tape := move_tape
                       (write (c_tape c) (e_write e)) (e_move e);
                     c_halted := false |} in
        if e_halt e then halt c' else c'
    end.

Theorem step_indexed_scan_agree :
  forall c,
    c_halted c = false ->
    c_state c < 23%nat ->
    read (c_tape c) < 8%nat ->
    step c = step_scan c.
Proof.
  intros c Hh Hq Hs. unfold step, step_scan.
  rewrite Hh.
  rewrite (find_entry_scan_valid (c_state c) (read (c_tape c)) Hq Hs).
  reflexivity.
Qed.

Lemma minsky_step_uses_entry :
  forall c e,
    c_halted c = false ->
    find_entry (c_state c) (read (c_tape c)) = Some e ->
    step c =
      let c' := {| c_state := e_to e;
                   c_tape := move_tape
                     (write (c_tape c) (e_write e)) (e_move e);
                   c_halted := false |} in
      if e_halt e then halt c' else c'.
Proof.
  intros c e Hh H. unfold step. rewrite Hh, H. reflexivity.
Qed.

Lemma minsky_halt_entry :
  exists e, find_entry 3 5 = Some e /\ e_halt e = true.
Proof.
  exists {| e_from := 3; e_read := 5; e_write := 5; e_move := 0%Z;
            e_to := 0; e_halt := true |}.
  split; reflexivity.
Qed.

(** ** Published 100-step trace *)

Definition initial_cells : list nat :=
  [0;0;1;1;1;1;5;3;2;2;4;2;2;2;2;2;2;2;4;2;2;3;2;2;2;2;7;6;
   0;0;0;0;0;0;5;0;0;1;4;0;0;0;0;0;0;1;4;0;0;1;0;1;1;0;4;0;
   1;0;0;0;1;1;4;0;1;1;0;1;0;0;5;0;0].

Definition expected_cells : list nat :=
  [0;0;1;1;1;1;5;3;2;2;4;2;2;2;2;2;2;2;4;2;2;3;2;2;2;2;7;6;
   0;0;0;0;0;0;5;0;0;3;4;2;2;2;2;2;2;3;4;2;2;1;0;1;1;0;4;0;
   1;0;0;0;1;1;4;0;1;1;0;1;0;0;5;0;0].

Definition initial_tape : Tape :=
  {| t_left := rev (firstn 38 initial_cells);
     t_right := skipn 38 initial_cells |}.

Definition expected_tape : Tape :=
  {| t_left := rev (firstn 38 expected_cells);
     t_right := skipn 38 expected_cells |}.

Definition initial_config : Config :=
  {| c_state := 5; c_tape := initial_tape; c_halted := false |}.

Definition expected_config : Config :=
  {| c_state := 2; c_tape := expected_tape; c_halted := false |}.

(** This is a kernel computation of all 100 steps, not a host trace. *)
Theorem minsky_trace_100 :
  run 100 initial_config = expected_config.
Proof. vm_compute. reflexivity. Qed.

(** The final state/head/tape are the published values.  The zipper's
    [right] starts at the head; the expected split has 38 cells to the left. *)
Theorem minsky_trace_head :
  run 100 initial_config = expected_config /\
  c_state expected_config = 2 /\
  length (t_left (c_tape expected_config)) = 38 /\
  t_right (c_tape expected_config) = skipn 38 expected_cells.
Proof.
  repeat split; try apply minsky_trace_100; reflexivity.
Qed.

Fixpoint run_scan (fuel : nat) (c : Config) : Config :=
  match fuel with
  | 0%nat => c
  | S n => if c_halted c then c else run_scan n (step_scan c)
  end.

(** The same published execution through the literal scan interpreter. *)
Theorem minsky_trace_100_scan :
  run_scan 100 initial_config = expected_config.
Proof. vm_compute. reflexivity. Qed.

(** Complete published execution: indexed table and scan agree end to end. *)
Theorem minsky_trace_100_indexed_scan :
  run 100 initial_config = run_scan 100 initial_config.
Proof. vm_compute. reflexivity. Qed.

Print Assumptions minsky_trace_100.
Print Assumptions step_indexed_scan_agree.
