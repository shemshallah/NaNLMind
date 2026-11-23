(** * Concrete left-window check

    The user's configuration:

      head = 2, R = 2, lo = 0, tape all false, state = [false]
      raw_ptape_prefix = [cell0], raw_last = cell1, raw_buf = []

    A left row with write = true and next = [false] moves to head = 1.
    The successor has ptape = [], w_tape = cell0, buf = [true].

    This file checks the frame equality literally.  The apparent
    mismatch is a parameter-reading issue: in

      book_q5_raw_left_frame_eq

    [ptape_prefix] and [w_tape_left] are the *output* q5 ptape and
    w_tape.  The cycle output's input q5 ptape is

      ptape_prefix ++ [source_bit w_tape_left].

    For the input ptape [cell0], the correct split is

      ptape_prefix = [],  w_tape_left = cell0.

    The old q5 w_tape (cell1) is the *read bit* [w_read] in the output,
    not the new w_tape.  Hence the successor encode is

      book_q5_raw [false] [true] false [] false rows tail

    and the frame equality matches exactly. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyActionMacro MinskyHeadMoveMacro MinskyBookLayout MinskyBookCycle
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode.

Definition lg_row : WideSourceRow :=
  {| wr_current := [false]; wr_read := false;
     wr_next := [false]; wr_write := true; wr_right := false |}.

Definition lg_next : WideSourceRow :=
  {| wr_current := [false]; wr_read := false;
     wr_next := [false]; wr_write := false; wr_right := false |}.

Definition lg_rows : list WideSourceRow := [lg_row; lg_next].

Definition lg_start : LeftInfiniteConfig :=
  {| lic_state := [false]; lic_head := 2%Z;
     lic_tape := fun _ => false; lic_R := 2%Z; lic_halted := false |}.

(** Input encode: buffer empty, ptape [cell0], v_tape cell1. *)
Example lg_input_encode :
  lic_q5_encode 0 lg_start (source_rows_to_book lg_rows) [] =
  book_q5_raw [false] [] false [0] false
    (source_rows_to_book lg_rows) [].
Proof. reflexivity. Qed.

(** The left step fields. *)
Example lg_step_fields :
  lic_head (left_infinite_step lg_rows lg_start) = 1%Z /\
  lic_R (left_infinite_step lg_rows lg_start) = 2%Z /\
  lic_tape (left_infinite_step lg_rows lg_start) 0%Z = false /\
  lic_tape (left_infinite_step lg_rows lg_start) 1%Z = false /\
  lic_tape (left_infinite_step lg_rows lg_start) 2%Z = true.
Proof. vm_compute. auto 20. Qed.

(** Successor encode: buffer [true], ptape [], v_tape cell0. *)
Example lg_successor_encode :
  lic_q5_encode 0 (left_infinite_step lg_rows lg_start)
    (source_rows_to_book lg_rows) [] =
  book_q5_raw [false] [1] false [] false
    (source_rows_to_book lg_rows) [].
Proof. vm_compute. reflexivity. Qed.

(** The concrete instance of the left frame equality.  The split is
    [ptape_prefix = []] and [w_tape_left = false] because the input q5
    ptape is [cell0] = [] ++ [cell0]. *)
Example lg_left_frame :
  book_q5_raw [false] [1] false [] false
    (source_rows_to_book lg_rows) []
  = cfg_ml 5
      (rev (source_bit true ::
            rev (book_return_rail_raw [false] [])) ++
       6 :: rev ([] ++ [source_bit false]))
      (match_mark false :: 4 ::
       map q16_restore
         (rev (book_cycle_tags [] ([false] ++ [false])
                (source_row_to_book lg_row))) ++
       source_bit false ::
       book_after_suffix [false] (source_row_to_book lg_next) [] ++
       5 :: []).
Proof.
  apply (book_q5_raw_left_frame_eq [false] [] [] false false []
    (source_row_to_book lg_row) (source_row_to_book lg_next) []
    [false] true false [false] []).
  - reflexivity.
  - reflexivity.
  - reflexivity.
Qed.

(** The successor encode is exactly the frame equality's left side. *)
Example lg_successor_matches_frame :
  lic_q5_encode 0 (left_infinite_step lg_rows lg_start)
    (source_rows_to_book lg_rows) [] =
  cfg_ml 5
      (rev (source_bit true ::
            rev (book_return_rail_raw [false] [])) ++
       6 :: rev ([] ++ [source_bit false]))
      (match_mark false :: 4 ::
       map q16_restore
         (rev (book_cycle_tags [] ([false] ++ [false])
                (source_row_to_book lg_row))) ++
       source_bit false ::
       book_after_suffix [false] (source_row_to_book lg_next) [] ++
       5 :: []).
Proof.
  rewrite lg_successor_encode.
  exact lg_left_frame.
Qed.

Print Assumptions lg_successor_matches_frame.
