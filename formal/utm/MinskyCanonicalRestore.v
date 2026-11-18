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

(** A direct q15 corollary from the restore frame: the q15 scan consumes
    the marked region plus the direction mark and exposes the next raw
    data bit. *)
Corollary canonical_restore_q15_capture :
  forall marked dir left bit tail,
    Forall q15_pass (marked ++ [dir]) ->
    run (S (length (marked ++ [dir])))
      (entry_config 15 left (marked ++ dir :: source_bit bit :: tail)) =
    cfg_ml 16 (rev (marked ++ [dir]) ++ left) (source_bit bit :: tail).
Proof.
  intros marked dir left bit tail Hscan.
  apply q15_scan_to_raw.
  exact Hscan.
Qed.

(** q16 then scans the q15-marked region and X=4, restores it, writes 7 at
    the previous raw bit, and chooses q21/q22 from that bit. *)
Corollary canonical_restore_q16_decision :
  forall marked dir prefix bit_prev bit tail,
    Forall q16_pass (rev (marked ++ [dir]) ++ [4]) ->
    run (S (length (rev (marked ++ [dir]) ++ [4])))
      (cfg_ml 16
        (rev (marked ++ [dir]) ++ 4 :: source_bit bit_prev :: prefix)
        (source_bit bit :: tail)) =
    cfg_ml (if bit_prev then 22 else 21) prefix
      (7 :: map q16_restore (rev (rev (marked ++ [dir]) ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros marked dir prefix bit_prev bit tail Hscan.
  apply (q16_restore_to_raw (tl (rev (marked ++ [dir]) ++ [4]))
    (hd 2 (rev (marked ++ [dir]) ++ [4])) bit_prev
    prefix (source_bit bit :: tail)).
  exact Hscan.
Qed.

Print Assumptions canonical_restore_q15_capture.
Print Assumptions canonical_restore_q16_decision.
