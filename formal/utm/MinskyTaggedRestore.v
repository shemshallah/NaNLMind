(** * q12 restore with arbitrary data after the M delimiter

    The q12/q14 restore scan stops at the first 6, the M delimiter.  Any
    symbols after that delimiter are carried through untouched as the
    q15 frame's outer tape.  This is the representation fact needed when
    a prefetched q1 rail leaves 6/7 tags behind the delimiter: those tags
    do not have to be crossed by q12.

    The theorem is a direct corollary of the checked q12 restore, with
    the data list reinterpreted.  It is a phase lemma, not an encoder.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalMatch MinskyCanonicalCopy
  MinskyCanonicalCopyGeneral MinskyCanonicalRestore MinskyCanonicalDirection.

Theorem canonical_q12_restore_with_leftover :
  forall s remaining tbuffer data marked mark record_tail leftover,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])))
      (cfg_ml 12
        (s :: remaining ++ 5 :: rev tbuffer ++
         6 :: leftover ++ 5 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    entry_config 15
      (4 :: map q14_restore
        (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) ++
       3 :: leftover ++ 5 :: rev data)
      (marked ++ mark :: record_tail).
Proof.
  intros s remaining tbuffer data marked mark record_tail leftover
    H12 H14.
  pose proof (canonical_q12_restore_to_q15_mark
    s remaining tbuffer (rev (leftover ++ 5 :: rev data))
    marked mark record_tail H12 H14) as H.
  rewrite !rev_involutive in H.
  exact H.
Qed.

Print Assumptions canonical_q12_restore_with_leftover.

