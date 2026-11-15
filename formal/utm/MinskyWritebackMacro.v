(** * Concrete action write-back and return-to-X, without new table rules

    The existing q6/q7/q8 development copies an action bit toward the
    Y delimiter.  These theorems cover the literal q9/q10 write followed
    by q11's return to the next X.  Program selection, source-level
    interpretation and universality remain separate obligations.
*)

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskySourceEncoding MinskyActionMacro.

Definition q_write_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q9_pass_step :
  forall s left right,
    q_write_pass s ->
    step (entry_config 9 left (s :: right)) =
    entry_config 9 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | ->]]]]; reflexivity.
Qed.

Lemma q10_pass_step :
  forall s left right,
    q_write_pass s ->
    step (entry_config 10 left (s :: right)) =
    entry_config 10 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | ->]]]]; reflexivity.
Qed.

Lemma q9_write_bit :
  forall b left tail,
    step (entry_config 9 left (source_bit b :: tail)) =
    entry_config 11 (3 :: left) tail.
Proof. intros b left tail; destruct b; reflexivity. Qed.

Lemma q10_write_bit :
  forall b left tail,
    step (entry_config 10 left (source_bit b :: tail)) =
    entry_config 11 (2 :: left) tail.
Proof. intros b left tail; destruct b; reflexivity. Qed.

(** Both write-back states skip arbitrarily many already marked cells,
    overwrite the first raw binary cell, and enter the same q11 return. *)
Theorem q9_scan_write_bit :
  forall scanned bit left tail,
    Forall q_write_pass scanned ->
    run (S (length scanned))
      (entry_config 9 left (scanned ++ source_bit bit :: tail)) =
    entry_config 11 (3 :: rev scanned ++ left) tail.
Proof.
  induction scanned as [|m rest IH]; intros bit left tail Hscan.
  - destruct bit; reflexivity.
  - inversion Hscan as [|? ? Hm Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 9 left
        (m :: rest ++ source_bit bit :: tail))) =
      entry_config 11 (3 :: rev (m :: rest) ++ left) tail).
    rewrite (q9_pass_step m left (rest ++ source_bit bit :: tail) Hm).
    rewrite (IH bit (m :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) m left).
    reflexivity.
Qed.

Theorem q10_scan_write_bit :
  forall scanned bit left tail,
    Forall q_write_pass scanned ->
    run (S (length scanned))
      (entry_config 10 left (scanned ++ source_bit bit :: tail)) =
    entry_config 11 (2 :: rev scanned ++ left) tail.
Proof.
  induction scanned as [|m rest IH]; intros bit left tail Hscan.
  - destruct bit; reflexivity.
  - inversion Hscan as [|? ? Hm Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 10 left
        (m :: rest ++ source_bit bit :: tail))) =
      entry_config 11 (2 :: rev (m :: rest) ++ left) tail).
    rewrite (q10_pass_step m left (rest ++ source_bit bit :: tail) Hm).
    rewrite (IH bit (m :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) m left).
    reflexivity.
Qed.

Definition q11_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q11_pass_step :
  forall s left right,
    q11_pass s ->
    step (entry_config 11 left (s :: right)) =
    entry_config 11 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q11_cross_x :
  forall left tail,
    step (entry_config 11 left (4 :: tail)) =
    entry_config 6 (4 :: left) tail.
Proof. reflexivity. Qed.

Theorem q11_scan_to_x :
  forall scanned left tail,
    Forall q11_pass scanned ->
    run (S (length scanned))
      (entry_config 11 left (scanned ++ 4 :: tail)) =
    entry_config 6 (4 :: rev scanned ++ left) tail.
Proof.
  induction scanned as [|m rest IH]; intros left tail Hscan.
  - reflexivity.
  - inversion Hscan as [|? ? Hm Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 11 left (m :: rest ++ 4 :: tail))) =
      entry_config 6 (4 :: rev (m :: rest) ++ left) tail).
    rewrite (q11_pass_step m left (rest ++ 4 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) m left).
    reflexivity.
Qed.

(** Fuel composition for the actual table interpreter, including halting.
    This is not an assumption about a separate source-level machine. *)
Lemma writeback_run_halted :
  forall fuel c, c_halted c = true -> run fuel c = c.
Proof.
  intros fuel c Hhalt.
  destruct fuel as [|fuel].
  - reflexivity.
  - simpl. now rewrite Hhalt.
Qed.

Lemma writeback_run_add :
  forall a b c, run (a + b) c = run b (run a c).
Proof.
  induction a as [|a IH]; intros b c.
  - reflexivity.
  - change (run (S (a + b)) c = run b (run (S a) c)).
    simpl [run].
    destruct (c_halted c) eqn:Hhalt.
    + symmetry. now apply writeback_run_halted.
    + apply IH.
Qed.

(** One complete action writeback and return-to-X, for any finite scan
    prefix and return segment.  The write input may be either raw bit;
    the state (q9 versus q10) determines the written logical bit. *)
Theorem q9_writeback_return_cycle :
  forall skipped bit returned left tail,
    Forall q_write_pass skipped ->
    Forall q11_pass returned ->
    run (S (length skipped) + S (length returned))
      (entry_config 9 left
        (skipped ++ source_bit bit :: returned ++ 4 :: tail)) =
    entry_config 6 (4 :: rev returned ++ 3 :: rev skipped ++ left) tail.
Proof.
  intros skipped bit returned left tail Hskip Hreturn.
  rewrite writeback_run_add.
  rewrite (q9_scan_write_bit skipped bit left
    (returned ++ 4 :: tail) Hskip).
  rewrite (q11_scan_to_x returned (3 :: rev skipped ++ left) tail Hreturn).
  reflexivity.
Qed.

Theorem q10_writeback_return_cycle :
  forall skipped bit returned left tail,
    Forall q_write_pass skipped ->
    Forall q11_pass returned ->
    run (S (length skipped) + S (length returned))
      (entry_config 10 left
        (skipped ++ source_bit bit :: returned ++ 4 :: tail)) =
    entry_config 6 (4 :: rev returned ++ 2 :: rev skipped ++ left) tail.
Proof.
  intros skipped bit returned left tail Hskip Hreturn.
  rewrite writeback_run_add.
  rewrite (q10_scan_write_bit skipped bit left
    (returned ++ 4 :: tail) Hskip).
  rewrite (q11_scan_to_x returned (2 :: rev skipped ++ left) tail Hreturn).
  reflexivity.
Qed.

(** Three-stage cycles: return left to Y, write the selected action bit,
    then scan right to X and resume q6.  The overlap condition excludes
    raw 0/1 cells in the return segment, which would terminate q9/q10
    early; this restriction is essential, not cosmetic. *)
Theorem q7_writeback_full_cycle :
  forall remaining s skipped bit returned prefix tail,
    Forall q7_pass (s :: remaining) ->
    Forall q_write_pass (rev (s :: remaining) ++ skipped) ->
    Forall q11_pass returned ->
    run (S (length (s :: remaining)) +
      (S (length (rev (s :: remaining) ++ skipped)) +
       S (length returned)))
      (entry_config 7 (remaining ++ 5 :: prefix)
        (s :: skipped ++ source_bit bit :: returned ++ 4 :: tail)) =
    entry_config 6
      (4 :: rev returned ++
       3 :: rev (rev (s :: remaining) ++ skipped) ++ 5 :: prefix) tail.
Proof.
  intros remaining s skipped bit returned prefix tail Hleft Hwrite Hreturn.
  rewrite writeback_run_add.
  rewrite (q7_scan_to_y remaining s prefix
    (skipped ++ source_bit bit :: returned ++ 4 :: tail) Hleft).
  replace (rev (s :: remaining) ++
       (skipped ++ source_bit bit :: returned ++ 4 :: tail))
    with ((rev (s :: remaining) ++ skipped) ++
      source_bit bit :: returned ++ 4 :: tail).
  2:{ rewrite app_assoc. reflexivity. }
  rewrite (q9_writeback_return_cycle
    (rev (s :: remaining) ++ skipped) bit returned
    (5 :: prefix) tail Hwrite Hreturn).
  reflexivity.
Qed.

Theorem q8_writeback_full_cycle :
  forall remaining s skipped bit returned prefix tail,
    Forall q8_pass (s :: remaining) ->
    Forall q_write_pass (rev (s :: remaining) ++ skipped) ->
    Forall q11_pass returned ->
    run (S (length (s :: remaining)) +
      (S (length (rev (s :: remaining) ++ skipped)) +
       S (length returned)))
      (entry_config 8 (remaining ++ 5 :: prefix)
        (s :: skipped ++ source_bit bit :: returned ++ 4 :: tail)) =
    entry_config 6
      (4 :: rev returned ++
       2 :: rev (rev (s :: remaining) ++ skipped) ++ 5 :: prefix) tail.
Proof.
  intros remaining s skipped bit returned prefix tail Hleft Hwrite Hreturn.
  rewrite writeback_run_add.
  rewrite (q8_scan_to_y remaining s prefix
    (skipped ++ source_bit bit :: returned ++ 4 :: tail) Hleft).
  replace (rev (s :: remaining) ++
       (skipped ++ source_bit bit :: returned ++ 4 :: tail))
    with ((rev (s :: remaining) ++ skipped) ++
      source_bit bit :: returned ++ 4 :: tail).
  2:{ rewrite app_assoc. reflexivity. }
  rewrite (q10_writeback_return_cycle
    (rev (s :: remaining) ++ skipped) bit returned
    (5 :: prefix) tail Hwrite Hreturn).
  reflexivity.
Qed.

Print Assumptions q9_scan_write_bit.
Print Assumptions q10_scan_write_bit.
Print Assumptions q11_scan_to_x.
Print Assumptions q9_writeback_return_cycle.
Print Assumptions q10_writeback_return_cycle.
Print Assumptions q7_writeback_full_cycle.
Print Assumptions q8_writeback_full_cycle.
