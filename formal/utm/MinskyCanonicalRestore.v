(** * Canonical q12/q13 restore to q15

    The direction-capture phase leaves a cfg_ml frame in q12 or q13, with
    the remaining record marks on the left, Y=5 and the t-buffer between
    them and M=6, and X=4 on the right.  q12/q13 scan left to M, then q14
    scans right restoring 2->0 and 3->1 until X=4, entering q15.

    This is a macro phase, not a source-step theorem.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalDirection.

Lemma q12_scan1_safe :
  forall m ms tbuffer,
    Forall q12_pass (m :: ms) ->
    Forall q12_pass tbuffer ->
    Forall q12_pass (m :: rev ms ++ 5 :: rev tbuffer).
Proof.
  intros m ms tbuffer Hmarks Hbuf.
  constructor.
  - inversion Hmarks as [|? ? Hm _]; exact Hm.
  - rewrite Forall_app. split.
    + apply Forall_rev. inversion Hmarks as [|? ? _ Hms]; exact Hms.
    + constructor.
      * unfold q12_pass; auto 10.
      * apply Forall_rev. exact Hbuf.
Qed.

Lemma q14_restore_safe :
  forall m ms tbuffer,
    Forall q14_pass (m :: ms) ->
    Forall q14_pass tbuffer ->
    Forall q14_pass (tbuffer ++ [5] ++ ms ++ [m]).
Proof.
  intros m ms tbuffer Hmarks Hbuf.
  rewrite Forall_app. split.
  - exact Hbuf.
  - rewrite Forall_app. split.
    + constructor.
      * unfold q14_pass; auto 10.
      * constructor.
    + rewrite Forall_app. split.
      * inversion Hmarks as [|? ? _ Hms]; exact Hms.
      * constructor.
        -- inversion Hmarks as [|? ? Hm _]; exact Hm.
        -- constructor.
Qed.

Theorem canonical_q12_restore_to_q15 :
  forall m ms tbuffer data marked record_tail,
    Forall q12_pass (m :: ms) ->
    Forall q14_pass (m :: ms) ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    run (S (length (m :: rev ms ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ ms ++ [m])))
      (cfg_ml 12 (rev (m :: ms) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 2 :: record_tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (tbuffer ++ [5] ++ ms ++ [m])) ++ 3 :: rev data)
      (marked ++ 2 :: record_tail).
Proof.
  intros m ms tbuffer data marked record_tail H12 H14 Hbuf12 Hbuf14.
  assert (Hscan1 : Forall q12_pass (m :: rev ms ++ 5 :: rev tbuffer))
    by (apply q12_scan1_safe; assumption).
  assert (Hscan2 : Forall q14_pass (tbuffer ++ [5] ++ ms ++ [m]))
    by (apply q14_restore_safe; assumption).
  rewrite dispatch_run_add.
  change (run (S (length (tbuffer ++ [5] ++ ms ++ [m])))
    (run (S (length (m :: rev ms ++ 5 :: rev tbuffer)))
      (cfg_ml 12 (rev (m :: ms) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 2 :: record_tail))) = _).
  rewrite (q12_scan_to_m (rev ms ++ 5 :: rev tbuffer) m (rev data)
    (4 :: marked ++ 2 :: record_tail) Hscan1).
  rewrite (q14_scan_to_x (tbuffer ++ [5] ++ ms ++ [m])
    (3 :: rev data) (marked ++ 2 :: record_tail) Hscan2).
  reflexivity.
Qed.

Theorem canonical_q13_restore_to_q15 :
  forall m ms tbuffer data marked record_tail,
    Forall q12_pass (m :: ms) ->
    Forall q14_pass (m :: ms) ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    run (S (length (m :: rev ms ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ ms ++ [m])))
      (cfg_ml 13 (rev (m :: ms) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: record_tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (tbuffer ++ [5] ++ ms ++ [m])) ++ 2 :: rev data)
      (marked ++ 3 :: record_tail).
Proof.
  intros m ms tbuffer data marked record_tail H12 H14 Hbuf12 Hbuf14.
  assert (Hscan1 : Forall q12_pass (m :: rev ms ++ 5 :: rev tbuffer))
    by (apply q12_scan1_safe; assumption).
  assert (Hscan2 : Forall q14_pass (tbuffer ++ [5] ++ ms ++ [m]))
    by (apply q14_restore_safe; assumption).
  rewrite dispatch_run_add.
  change (run (S (length (tbuffer ++ [5] ++ ms ++ [m])))
    (run (S (length (m :: rev ms ++ 5 :: rev tbuffer)))
      (cfg_ml 13 (rev (m :: ms) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: record_tail))) = _).
  rewrite (q13_scan_to_m (rev ms ++ 5 :: rev tbuffer) m (rev data)
    (4 :: marked ++ 3 :: record_tail) Hscan1).
  rewrite (q14_scan_to_x (tbuffer ++ [5] ++ ms ++ [m])
    (2 :: rev data) (marked ++ 3 :: record_tail) Hscan2).
  reflexivity.
Qed.

Print Assumptions canonical_q12_restore_to_q15.
Print Assumptions canonical_q13_restore_to_q15.
