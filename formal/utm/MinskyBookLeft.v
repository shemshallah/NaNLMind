(** * Book-layout left-branch q15 -> q20/q5 (general tags)

    The stable-tag left theorems in [MinskyTaggedHalt] are restricted to
    6/7 control tags.  The book layout uses the marked description record
    (2/3 tags), so this file generalises the left four-prefix theorems to
    arbitrary q15/q16-passable tags. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyDirectionDecision MinskyWritebackMacro MinskyRelocationMacro
  MinskyTaggedHalt.

Theorem q15_q22_left_to_q20_tags :
  forall (tags : list nat) (dir_head : nat) (dir_remaining : list nat)
         (old next target : bool) (outer suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (rev tags)) +
         S (length (tags ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev tags ++ source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros tags dir_head dir_remaining old next target outer suffix
    H15 H16 H21.
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip_local old next tags
    (dir_head :: dir_remaining ++ 2 :: source_bit target :: outer)
    suffix H15 H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 2 :: source_bit target :: outer)
      (dir_head :: 7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix)).
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite (q21_scan_to_left_direction dir_remaining dir_head
    (if old then 22 else 21) (source_bit target :: outer)
    (7 :: map q16_restore (rev (tags ++ [4])) ++
     source_bit next :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Theorem q15_q22_left_to_q5_book :
  forall (tags : list nat) (dir_head : nat) (dir_remaining : list nat)
         (old next target : bool) (outer suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining)) ->
    run ((S (length (rev tags)) +
          S (length (tags ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (1 + S (length
           (source_bit old :: rev (dir_head :: dir_remaining)))))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev tags ++ source_bit next :: suffix)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros tags dir_head dir_remaining old next target outer suffix
    H15 H16 H21 Hreturn.
  rewrite writeback_run_add.
  rewrite (q15_q22_left_to_q20_tags tags dir_head dir_remaining
    old next target outer suffix H15 H16 H21).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix))) = expected)
  end.
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (tags ++ [4])) ++
     source_bit next :: suffix)).
  destruct target.
  - exact (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix) Hreturn).
  - exact (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix) Hreturn).
Qed.

Print Assumptions q15_q22_left_to_q20_tags.
Print Assumptions q15_q22_left_to_q5_book.
