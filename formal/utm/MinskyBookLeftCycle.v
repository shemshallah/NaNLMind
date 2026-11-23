(** * Book-layout left perform composition q13 -> q5 *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalInstruction MinskyCanonicalDirection MinskyCanonicalRestore MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyRelocationMacro MinskyBookLeft MinskyBookLayout
  MinskyBookCycle.

Theorem book_q13_restore_to_q5_left :
  forall (s : nat) (remaining tbuffer data : list nat)
         (marked : list nat) (mark : nat) (record_tail : list nat)
         (tags : list nat) (restored : list nat)
         (old : bool) (dir_head : nat) (dir_remaining : list nat)
         (target next : bool) (outer suffix : list nat),
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    map q14_restore
      (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) = restored ->
    restored = source_bit old :: dir_head :: dir_remaining ->
    rev data = source_bit target :: outer ->
    marked ++ mark :: record_tail =
      rev tags ++ source_bit next :: suffix ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining)) ->
    run ((S (length (s :: remaining ++ 5 :: rev tbuffer)) +
          S (length (tbuffer ++ [5] ++ rev remaining ++ [s]))) +
         ((S (length (rev tags)) +
           S (length (tags ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (1 + S (length
            (source_bit old :: rev (dir_head :: dir_remaining))))))
      (cfg_ml 13
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros s remaining tbuffer data marked mark record_tail tags
    restored old dir_head dir_remaining target next outer suffix
    H12 H14 Hrestored Hrestored' Hdata Hright H15 H16 H21 Hreturn.
  rewrite dispatch_run_add.
  rewrite (canonical_q13_restore_to_q15_mark
    s remaining tbuffer data marked mark record_tail H12 H14).
  rewrite Hrestored, Hrestored', Hdata, Hright.
  apply (q15_q22_left_to_q5_book tags dir_head dir_remaining
    old next target outer suffix H15 H16 H21 Hreturn).
Qed.

Print Assumptions book_q13_restore_to_q5_left.

