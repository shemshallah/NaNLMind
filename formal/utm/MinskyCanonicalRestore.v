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
  MinskyActionMacro MinskyHeadMoveMacro MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection.

Lemma rev_restore_scan :
  forall s remaining tbuffer,
    rev (s :: remaining ++ 5 :: rev tbuffer) =
    tbuffer ++ [5] ++ rev remaining ++ [s].
Proof.
  intros s remaining tbuffer.
  cbn [rev].
  rewrite rev_app_distr.
  cbn [rev].
  rewrite rev_involutive.
  repeat rewrite app_assoc.
  reflexivity.
Qed.

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
  replace (remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
    with ((remaining ++ 5 :: rev tbuffer) ++ 6 :: rev data)
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite (q12_scan_to_m (remaining ++ 5 :: rev tbuffer) s (rev data)
    (4 :: marked ++ 2 :: record_tail) H1).
  rewrite rev_restore_scan.
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
  replace (remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
    with ((remaining ++ 5 :: rev tbuffer) ++ 6 :: rev data)
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite (q13_scan_to_m (remaining ++ 5 :: rev tbuffer) s (rev data)
    (4 :: marked ++ 3 :: record_tail) H1).
  rewrite rev_restore_scan.
  rewrite (q14_scan_to_x (tbuffer ++ [5] ++ rev remaining ++ [s])
    (2 :: rev data) (marked ++ 3 :: record_tail) H2).
  reflexivity.
Qed.

Print Assumptions canonical_q12_restore_to_q15.
Print Assumptions canonical_q13_restore_to_q15.

(** Compose the q12 restore with the q15 capture.  The direction mark 2 is
    crossed by q15, and the first bit of the remaining record follows it. *)
Corollary canonical_restore_q12_q15_capture :
  forall s remaining tbuffer data marked bit tail,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    Forall q15_pass (marked ++ [2]) ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])) +
         S (length (marked ++ [2])))
      (cfg_ml 12
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 2 :: source_bit bit :: tail)) =
    cfg_ml 16
      (rev (marked ++ [2]) ++ 4 ::
       map q14_restore
         (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) ++
       3 :: rev data)
      (source_bit bit :: tail).
Proof.
  intros s remaining tbuffer data marked bit tail H12 H14 H15.
  rewrite dispatch_run_add.
  rewrite (canonical_q12_restore_to_q15 s remaining tbuffer data marked
    (source_bit bit :: tail) H12 H14).
  replace (marked ++ 2 :: source_bit bit :: tail)
    with ((marked ++ [2]) ++ source_bit bit :: tail)
    by (rewrite <- app_assoc; reflexivity).
  apply q15_scan_to_raw.
  exact H15.
Qed.

(** The q13 restore branch, with direction mark 3 and trailing mark 2. *)
Corollary canonical_restore_q13_q15_capture :
  forall s remaining tbuffer data marked bit tail,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    Forall q15_pass (marked ++ [3]) ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])) +
         S (length (marked ++ [3])))
      (cfg_ml 13
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: source_bit bit :: tail)) =
    cfg_ml 16
      (rev (marked ++ [3]) ++ 4 ::
       map q14_restore
         (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) ++
       2 :: rev data)
      (source_bit bit :: tail).
Proof.
  intros s remaining tbuffer data marked bit tail H13 H14 H15.
  rewrite dispatch_run_add.
  rewrite (canonical_q13_restore_to_q15 s remaining tbuffer data marked
    (source_bit bit :: tail) H13 H14).
  replace (marked ++ 3 :: source_bit bit :: tail)
    with ((marked ++ [3]) ++ source_bit bit :: tail)
    by (rewrite <- app_assoc; reflexivity).
  apply q15_scan_to_raw.
  exact H15.
Qed.

(** q16 now scans left across the direction mark, the q15-marked region and
    X=4, restores 2->0 and 3->1, writes 7 at the raw cell behind X=4, and
    selects q21 (bit 0) or q22 (bit 1).  [m] is the direction mark crossed
    by q15 (2 or 3); [4] is X. *)
Corollary canonical_restore_q16_decision :
  forall m marked old prefix bit tail,
    q16_pass m ->
    Forall q16_pass marked ->
    run (S (length (m :: rev marked ++ [4])))
      (cfg_ml 16
        (rev (marked ++ [m]) ++ 4 :: source_bit old :: prefix)
        (source_bit bit :: tail)) =
    cfg_ml (if old then 22 else 21) prefix
      (7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros m marked old prefix bit tail Hm Hmarked.
  replace (rev (marked ++ [m])) with (m :: rev marked).
  2:{
    rewrite rev_app_distr. cbn [rev]. rewrite app_nil_r.
    reflexivity.
  }
  cbn [cfg_ml].
  assert (Hscan : Forall q16_pass (m :: rev marked ++ [4])).
  {
    constructor.
    - exact Hm.
    - rewrite Forall_app. split.
      + apply Forall_rev. exact Hmarked.
      + constructor.
        * unfold q16_pass; auto 10.
        * constructor.
  }
  assert (Hframe :
    rev marked ++ 4 :: source_bit old :: prefix =
    (rev marked ++ [4]) ++ source_bit old :: prefix)
    by (rewrite <- app_assoc; reflexivity).
  rewrite Hframe.
  apply (q16_restore_to_raw (rev marked ++ [4]) m old prefix
    (source_bit bit :: tail) Hscan).
Qed.

Print Assumptions canonical_restore_q12_q15_capture.
Print Assumptions canonical_restore_q13_q15_capture.
Print Assumptions canonical_restore_q16_decision.
