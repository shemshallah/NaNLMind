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

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyActionMacro MinskyCanonicalCopyGeneral
  MinskyCanonicalInstruction
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

(** ** Book-layout q12 -> q5 perform composition

    q12/q14 restores the current record and enters q15 with the record
    marks on the right.  The book q15 perform macro scans those marks,
    q16 restores them, q21/q22 writes the old head, q19 moves to the new
    source cell, and q17/q18 return to q5. *)

From NaNLM Require Import MinskyCanonicalRestore.

Theorem book_q12_restore_to_q5_right :
  forall (s : nat) (remaining tbuffer data : list nat)
         (marked : list nat) (mark : nat) (record_tail : list nat)
         (tags : list nat) (old : bool)
         (dir_head : nat) (dir_remaining : list nat)
         (bit target : bool) (between suffix : list nat),
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    map q14_restore
      (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) =
      source_bit old :: dir_head :: dir_remaining ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    rev (dir_head :: dir_remaining) = source_bit bit :: between ->
    Forall q17_pass between ->
    marked ++ mark :: record_tail =
      rev tags ++ source_bit target :: suffix ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run ((S (length (s :: remaining ++ 5 :: rev tbuffer)) +
          S (length (tbuffer ++ [5] ++ rev remaining ++ [s]))) +
         ((S (length (rev tags)) +
           S (length (tags ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (S (length ([] : list nat)) + S (length between))))
      (cfg_ml 12
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    cfg_ml 5
      (rev between ++ 6 :: source_bit old :: rev data)
      ((if bit then 3 else 2) ::
       4 :: map q16_restore (rev tags) ++
       source_bit target :: suffix).
Proof.
  intros s remaining tbuffer data marked mark record_tail tags
    old dir_head dir_remaining bit target between suffix
    H12 H14 Hrestored H21 Hsplit H17 Hright H15 H16.
  rewrite dispatch_run_add.
  rewrite (canonical_q12_restore_to_q15_mark
    s remaining tbuffer data marked mark record_tail H12 H14).
  rewrite Hrestored, Hright.
  apply (q15_q22_right_to_q5_book tags
    dir_head dir_remaining old target (rev data) suffix
    bit between H15 H16 H21 H17 Hsplit).
Qed.

Print Assumptions book_q12_restore_to_q5_right.


(** ** Book frame vocabulary *)

Definition book_buf (b : nat) : list nat := repeat 0 b.

Definition book_return_rail (init : list bool) (b : nat) : list nat :=
  rev (map source_bit init) ++ [5] ++ rev (book_buf b).

Definition book_q15_rail
    (bits init : list bool) (w : bool) (dir_mark : nat)
    (desc_tail : list nat) : list nat :=
  map match_mark bits ++ map match_mark (init ++ [w]) ++
  [dir_mark] ++ desc_tail.

Definition book_q6_left
    (bits : list bool) (b : nat) (ptape : list nat) : list nat :=
  4 :: rev (map source_bit bits) ++
  5 :: rev (book_buf b) ++ 6 :: rev ptape.

Corollary book_q6_to_q12 :
  forall (bits init : list bool) (w dir : bool)
         (b : nat) (ptape desc_tail : list nat)
         (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    run (copy_all_clock bits (init ++ [w]) [] (map match_mark bits) +
         direction_clock
           (map match_mark bits ++ map match_mark (init ++ [w]))
           (map match_mark (init ++ [w])))
      (entry_config 6
        (book_q6_left bits b ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit dir :: desc_tail ++
         source_bit trailing :: tail)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark (init ++ [w])) ++
       5 :: rev (book_buf b) ++ 6 :: rev ptape)
      ((4 :: (map match_mark bits ++ map match_mark (init ++ [w]))) ++
            (if dir then 3 else 2) :: desc_tail ++
            source_bit trailing :: tail).
Proof.
  intros bits init w dir b ptape desc_tail trailing tail Hlen.
  exact (canonical_q6_copy_direction_to_q12
    bits (init ++ [w]) (book_buf b) ptape dir
    (desc_tail ++ source_bit trailing :: tail) (eq_sym Hlen)).
Qed.

Print Assumptions book_q6_to_q12.
