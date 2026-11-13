(** * Step-level interpreter refinement

    A small, self-contained model of the C++ [UniversalTuringMachine::step]
    loop: the machine description is a list of transition records, and every
    step scans that list for the current (state, symbol) pair.

    The reference machine is given by an arbitrary transition function
    [delta].  If the list is a graph of [delta], the interpreter and the
    reference machine produce exactly the same configuration after every
    fuel-bounded step.  This is a step-level compiler/interpreter refinement
    theorem, not merely a final-state check.
*)

Require Import List Arith ZArith Bool.
Import ListNotations.
Open Scope Z_scope.

Inductive Move := MoveL | MoveS | MoveR.

Record Trans := {
  t_from : nat;
  t_read : nat;
  t_write : nat;
  t_move : Move;
  t_to : nat;
  t_halt : bool
}.

Definition Tape := Z -> nat.

Record Config := {
  c_state : nat;
  c_head : Z;
  c_tape : Tape
}.

Definition move_head (h : Z) (m : Move) : Z :=
  match m with
  | MoveL => h - 1
  | MoveS => h
  | MoveR => h + 1
  end.

Definition write_tape (tp : Tape) (h : Z) (s : nat) : Tape :=
  fun p => if Z.eqb p h then s else tp p.

Definition find_trans (q s : nat) (d : list Trans) : option Trans :=
  find (fun t => Nat.eqb (t_from t) q && Nat.eqb (t_read t) s) d.

Definition step_with
    (delta : nat -> nat -> option Trans) (c : Config) : option Config :=
  match delta (c_state c) (c_tape c (c_head c)) with
  | None => None
  | Some t =>
      if t_halt t then None
      else Some {|
        c_state := t_to t;
        c_head := move_head (c_head c) (t_move t);
        c_tape := write_tape (c_tape c) (c_head c) (t_write t)
      |}
  end.

Definition utm_step (d : list Trans) (c : Config) : option Config :=
  step_with (fun q s => find_trans q s d) c.

Definition ref_step (delta : nat -> nat -> option Trans) (c : Config) :
    option Config :=
  step_with delta c.

Fixpoint utm_run (fuel : nat) (d : list Trans) (c : Config) :
    option Config :=
  match fuel with
  | 0 => Some c
  | S n =>
      match utm_step d c with
      | None => None
      | Some c' => utm_run n d c'
      end
  end.

Fixpoint ref_run (fuel : nat) (delta : nat -> nat -> option Trans)
    (c : Config) : option Config :=
  match fuel with
  | 0 => Some c
  | S n =>
      match ref_step delta c with
      | None => None
      | Some c' => ref_run n delta c'
      end
  end.

Definition graph_ok (d : list Trans) (delta : nat -> nat -> option Trans) :=
  forall q s, find_trans q s d = delta q s.

Lemma utm_step_refines :
  forall d delta c, graph_ok d delta -> utm_step d c = ref_step delta c.
Proof.
  intros d delta c H. unfold utm_step, ref_step, step_with.
  rewrite H. reflexivity.
Qed.

(** The step-level theorem: every fuel-bounded interpreter run is exactly the
    reference run, for every description that is a graph of [delta]. *)
Theorem utm_run_refines :
  forall fuel d delta c,
    graph_ok d delta ->
    utm_run fuel d c = ref_run fuel delta c.
Proof.
  induction fuel as [| fuel IH]; intros d delta c H; simpl.
  - reflexivity.
  - rewrite (utm_step_refines d delta c H).
    destruct (ref_step delta c) as [c'|] eqn:E; [|reflexivity].
    apply IH. exact H.
Qed.

(** A concrete binary-increment description used by the NaN16 guest gate.
    The reference relation is deliberately a separate function; the proof
    below establishes the graph condition by computation. *)
Definition bin_delta (q s : nat) : option Trans :=
  match q, s with
  | 0, 1 => Some {| t_from := 0; t_read := 1; t_write := 0;
                    t_move := MoveL; t_to := 0; t_halt := false |}
  | 0, 0 => Some {| t_from := 0; t_read := 0; t_write := 1;
                    t_move := MoveS; t_to := 0; t_halt := true |}
  | 0, 2 => Some {| t_from := 0; t_read := 2; t_write := 1;
                    t_move := MoveS; t_to := 0; t_halt := true |}
  | _, _ => None
  end.

Definition bin_desc : list Trans :=
  [ {| t_from := 0; t_read := 1; t_write := 0; t_move := MoveL;
       t_to := 0; t_halt := false |};
    {| t_from := 0; t_read := 0; t_write := 1; t_move := MoveS;
       t_to := 0; t_halt := true |};
    {| t_from := 0; t_read := 2; t_write := 1; t_move := MoveS;
       t_to := 0; t_halt := true |} ].

Lemma bin_graph_ok : graph_ok bin_desc bin_delta.
Proof.
  intros q s. destruct q as [|q]; destruct s as [| [| [|s]]]; reflexivity.
Qed.

(** The concrete description is checked against the same reference function. *)
Corollary bin_run_refines :
  forall fuel c, utm_run fuel bin_desc c = ref_run fuel bin_delta c.
Proof.
  intros. apply utm_run_refines. apply bin_graph_ok.
Qed.

Print Assumptions utm_run_refines.
