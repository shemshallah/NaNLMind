(** * Book-layout q15 -> q19 relocation

    The actual Minsky tape layout separates the source tape (left of Y)
    from the condition/description workspace (right of Y).  The q15 rail
    is the marked description record, not the action block.  q16 restores
    the record marks in place; q21/q22 scans the condition/t-buffer side
    and writes the source write bit at the old head; q19 then starts at
    the source side and captures the new head cell.

    This is the general-tag version of the four-prefix q15->q19 lemma. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyDirectionDecision MinskyTaggedHalt.

Theorem q15_q22_right_to_q19_tags :
  forall (tags : list nat) (dir_head : nat) (dir_remaining : list nat)
         (old target : bool) (outer suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (rev tags)) +
         S (length (tags ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev tags ++ source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
       map q16_restore (rev tags) ++
       source_bit target :: suffix).
Proof.
  intros tags dir_head dir_remaining old target outer suffix H15 H16 H21.
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip_local old target tags
    (dir_head :: dir_remaining ++ 3 :: outer) suffix H15 H16).
  rewrite map_q16_restore_four_prefix.
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head ::
       7 :: 4 :: map q16_restore (rev tags) ++
       source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
       map q16_restore (rev tags) ++
       source_bit target :: suffix)).
  rewrite (q21_scan_to_right_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: 4 :: map q16_restore (rev tags) ++
     source_bit target :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Print Assumptions q15_q22_right_to_q19_tags.

(** ** Book-layout q15 -> q5 perform macro

    q15 scans the marked description record, q16 restores it, q21/q22
    scans the condition/t-buffer side and writes the source write bit at
    the old head, q19 moves the head marker to the new source cell, and
    q17/q18 return to q5.  The q15 right rail is the description record
    marks (2/3), not a 6/7 tag rail. *)

From NaNLM Require Import MinskyRelocationMacro.

Theorem q15_q22_right_to_q5_book :
  forall (tags : list nat) (dir_head : nat) (dir_remaining : list nat)
         (old target : bool) (outer suffix : list nat)
         (bit : bool) (between : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass between ->
    rev (dir_head :: dir_remaining) = source_bit bit :: between ->
    run ((S (length (rev tags)) +
          S (length (tags ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (S (length ([] : list nat)) + S (length between)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev tags ++ source_bit target :: suffix)) =
    cfg_ml 5
      (rev between ++ 6 :: source_bit old :: outer)
      ((if bit then 3 else 2) ::
       4 :: map q16_restore (rev tags) ++
       source_bit target :: suffix).
Proof.
  intros tags dir_head dir_remaining old target outer suffix
    bit between H15 H16 H21 H17 Hsplit.
  rewrite dispatch_run_add.
  rewrite (q15_q22_right_to_q19_tags tags dir_head dir_remaining
    old target outer suffix H15 H16 H21).
  rewrite Hsplit.
  replace ((source_bit bit :: between) ++
           7 :: 4 :: map q16_restore (rev tags) ++
           source_bit target :: suffix)
    with (source_bit bit :: between ++
          7 :: 4 :: map q16_restore (rev tags) ++
          source_bit target :: suffix)
    by reflexivity.
  apply (q19_to_q5_relocation [] between bit
    (source_bit old :: outer)
    (4 :: map q16_restore (rev tags) ++
     source_bit target :: suffix) (Forall_nil q15_pass) H17).
Qed.

Print Assumptions q15_q22_right_to_q5_book.
