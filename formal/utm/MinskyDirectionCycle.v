(** * Composed direction dispatch: q12/q13 -> q14 -> q15

    The unchanged 184-entry table first walks left to the source-head M,
    records the selected movement branch (mark 3 from q12, mark 2 from
    q13), then restores and scans right across an arbitrary finite valid
    prefix to the next X.  These theorems include exact microstep clocks
    and arbitrary surrounding tape, but do not yet compose the remaining
    q15..q22 movement phase or prove a source instruction step.
*)

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyActionMacro MinskyWritebackMacro.

Theorem q12_to_q15_direction_cycle :
  forall remaining s skipped prefix tail,
    Forall q12_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    run (S (length (s :: remaining)) +
         S (length (rev (s :: remaining) ++ skipped)))
      (entry_config 12 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 :: tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (rev (s :: remaining) ++ skipped)) ++ 3 :: prefix) tail.
Proof.
  intros remaining s skipped prefix tail Hleft Hrestore.
  rewrite writeback_run_add.
  rewrite (q12_scan_to_m remaining s prefix (skipped ++ 4 :: tail) Hleft).
  replace (rev (s :: remaining) ++ (skipped ++ 4 :: tail))
    with ((rev (s :: remaining) ++ skipped) ++ 4 :: tail).
  2:{ rewrite app_assoc. reflexivity. }
  rewrite (q14_scan_to_x
    (rev (s :: remaining) ++ skipped) (3 :: prefix) tail Hrestore).
  reflexivity.
Qed.

Theorem q13_to_q15_direction_cycle :
  forall remaining s skipped prefix tail,
    Forall q13_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    run (S (length (s :: remaining)) +
         S (length (rev (s :: remaining) ++ skipped)))
      (entry_config 13 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 :: tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (rev (s :: remaining) ++ skipped)) ++ 2 :: prefix) tail.
Proof.
  intros remaining s skipped prefix tail Hleft Hrestore.
  rewrite writeback_run_add.
  rewrite (q13_scan_to_m remaining s prefix (skipped ++ 4 :: tail) Hleft).
  replace (rev (s :: remaining) ++ (skipped ++ 4 :: tail))
    with ((rev (s :: remaining) ++ skipped) ++ 4 :: tail).
  2:{ rewrite app_assoc. reflexivity. }
  rewrite (q14_scan_to_x
    (rev (s :: remaining) ++ skipped) (2 :: prefix) tail Hrestore).
  reflexivity.
Qed.

Print Assumptions q12_to_q15_direction_cycle.
Print Assumptions q13_to_q15_direction_cycle.
