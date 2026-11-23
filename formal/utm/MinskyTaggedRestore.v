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


(** A concrete non-vacuity witness: the leftover 6/7 tags survive after
    the q15 direction marker 3. *)
Example canonical_q12_restore_leftover_witness :
  run (S (length (2 :: [] ++ 5 :: ([] : list nat))) +
       S (length (([] : list nat) ++ [5] ++ rev ([] : list nat) ++ [2])))
    (cfg_ml 12
      (2 :: [] ++ 5 :: ([] : list nat) ++
       6 :: [6; 7] ++ 5 :: rev [0])
      (4 :: [2] ++ 3 :: ([] : list nat))) =
  entry_config 15
    (4 :: map q14_restore
      (rev (([] : list nat) ++ [5] ++ rev ([] : list nat) ++ [2])) ++
     3 :: [6; 7] ++ 5 :: rev [0])
    ([2] ++ 3 :: ([] : list nat)).
Proof.
  apply (canonical_q12_restore_with_leftover 2 [] [] [0] [2] 3 [] [6; 7]).
  - cbn. constructor.
    + unfold q12_pass; auto 12.
    + constructor.
      * unfold q12_pass; auto 12.
      * constructor.
  - cbn. constructor.
    + unfold q14_pass; auto 12.
    + constructor.
      * unfold q14_pass; auto 12.
      * constructor.
Qed.

Print Assumptions canonical_q12_restore_leftover_witness.

(** ** Exact q12 -> tagged q15 interface

    If the encoder can supply the q12 start with a 6/7 tag rail
    [rev tags], a raw target mark, and a restored left prefix of the form
    [source_bit old :: dirs], then q12/q14 land exactly on the tagged q15
    entry used by the movement macros.  The remaining obligation is to
    produce that q12 start from the prefetched q1/q6 phase. *)
Corollary canonical_q12_restore_to_tagged_entry :
  forall s remaining tbuffer data tags dirs old target suffix,
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    map q14_restore
      (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) =
      source_bit old :: dirs ->
    run (S (length (s :: remaining ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev remaining ++ [s])))
      (cfg_ml 12
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: rev tags ++ source_bit target :: suffix)) =
    entry_config 15
      (4 :: source_bit old :: dirs ++ 3 :: rev data)
      (rev tags ++ source_bit target :: suffix).
Proof.
  intros s remaining tbuffer data tags dirs old target suffix
    H12 H14 Hleft.
  pose proof (canonical_q12_restore_to_q15_mark
    s remaining tbuffer data (rev tags) (source_bit target) suffix
    H12 H14) as H.
  rewrite Hleft in H.
  exact H.
Qed.

Print Assumptions canonical_q12_restore_to_tagged_entry.

(** ** Negative guard: restored action bits are never in the q15/q21 pass set

    The q15/q21 movement prefix must consist only of 4/5/6/7.  q14
    restores every marked action bit to raw 0/1, so any nonempty copied
    action block injects a forbidden symbol into that prefix.  This is
    why a pure action-order swap cannot repair the q12 bridge. *)

Definition q15q21_pass (s : nat) : Prop :=
  s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q14_restored_action_not_passable :
  forall (a : list bool),
    a <> [] ->
    exists s,
      In s (map q14_restore (map match_mark a)) /\
      ~ q15q21_pass s.
Proof.
  intros [|b rest] Hne.
  - contradiction.
  - exists (q14_restore (match_mark b)).
    split.
    + left. reflexivity.
    + destruct b; cbn; unfold q15q21_pass;
        intros [H | [H | [H | H]]]; discriminate H.
Qed.

Print Assumptions q14_restored_action_not_passable.
