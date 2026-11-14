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

From Coq Require Import List Arith ZArith Lia.
Import ListNotations.
Open Scope Z_scope.

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
  if Z.eqb m (-1) then move_left t
  else if Z.eqb m 1 then move_right t
  else t.

Record Config := {
  c_state : nat;
  c_tape : Tape
}.

(** Flat row-major table lookup: entry [q,s] is at index [q*8+s]. *)
Definition find_entry (q s : nat) : option Entry :=
  nth_error minsky_entries (q * 8 + s).

Definition step (c : Config) : option Config :=
  match find_entry (c_state c) (read (c_tape c)) with
  | None => None
  | Some e =>
      if e_halt e then None
      else Some {| c_state := e_to e;
                   c_tape := move_tape
                     (write (c_tape c) (e_write e)) (e_move e) |}
  end.

Fixpoint run (fuel : nat) (c : Config) : option Config :=
  match fuel with
  | 0%nat => Some c
  | S n =>
      match step c with
      | None => None
      | Some c' => run n c'
      end
  end.

(** ** Table completeness *)

Lemma minsky_table_length : length minsky_entries = 184%nat.
Proof. reflexivity. Qed.

Lemma minsky_table_complete :
  forall q s, q < 23 -> s < 8 -> exists e, find_entry q s = Some e.
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
Lemma minsky_step_uses_entry :
  forall c e,
    find_entry (c_state c) (read (c_tape c)) = Some e ->
    step c =
      if e_halt e then None
      else Some {| c_state := e_to e;
                   c_tape := move_tape
                     (write (c_tape c) (e_write e)) (e_move e) |}.
Proof.
  intros c e H. unfold step. rewrite H. reflexivity.
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
  {| c_state := 5; c_tape := initial_tape |}.

Definition expected_config : Config :=
  {| c_state := 2; c_tape := expected_tape |}.

(** This is a kernel computation of all 100 steps, not a host trace. *)
Theorem minsky_trace_100 :
  run 100 initial_config = Some expected_config.
Proof. vm_compute. reflexivity. Qed.

(** The final state/head/tape are the published values.  The zipper's
    [right] starts at the head; the expected split has 38 cells to the left. *)
Theorem minsky_trace_head :
  exists c, run 100 initial_config = Some c /\ c_state c = 2 /\
            length (t_left (c_tape c)) = 38 /\
            t_right (c_tape c) = skipn 38 expected_cells.
Proof.
  exists expected_config. split.
  - apply minsky_trace_100.
  - repeat split; reflexivity.
Qed.

Print Assumptions minsky_trace_100.
