(** * Canonical q12/q13 restore to q15

    The direction-capture phase leaves a cfg_ml frame in q12 or q13.  The
    left-hand record marks are decomposed as [s :: remaining], so cfg_ml
    exposes the head [s].  q12/q13 scan left over [s :: remaining], Y=5 and
    the t-buffer to M=6, then q14 scans right restoring 2->0 and 3->1 until
    X=4, entering q15.

    This is a macro phase, not a source-step theorem.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalDirection.

Theorem canonical_q12_restore_to_q15 :
  forall s remaining tbuffer data marked record_tail,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])))
      (cfg_ml 12 (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 2 :: record_tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) ++ 3 :: rev data)
      (marked ++ 2 :: record_tail).
Proof.
  intros s remaining tbuffer data marked record_tail H1 H2.
  rewrite dispatch_run_add.
  cbn [cfg_ml].
  rewrite (q12_scan_to_m (remaining ++ 5 :: rev tbuffer) s (rev data)
    (4 :: marked ++ 2 :: record_tail) H1).
  rewrite (q14_scan_to_x (tbuffer ++ [5] ++ rev remaining ++ [s])
    (3 :: rev data) (marked ++ 2 :: record_tail) H2).
  reflexivity.
Qed.

Theorem canonical_q13_restore_to_q15 :
  forall s remaining tbuffer data marked record_tail,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])))
      (cfg_ml 13 (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: record_tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) ++ 2 :: rev data)
      (marked ++ 3 :: record_tail).
Proof.
  intros s remaining tbuffer data marked record_tail H1 H2.
  rewrite dispatch_run_add.
  cbn [cfg_ml].
  rewrite (q13_scan_to_m (remaining ++ 5 :: rev tbuffer) s (rev data)
    (4 :: marked ++ 3 :: record_tail) H1).
  rewrite (q14_scan_to_x (tbuffer ++ [5] ++ rev remaining ++ [s])
    (2 :: rev data) (marked ++ 3 :: record_tail) H2).
  reflexivity.
Qed.

Print Assumptions canonical_q12_restore_to_q15.
Print Assumptions canonical_q13_restore_to_q15.
