(** * Mechanical audit: the book left-perform output is not a zero-buffer frame

    MinskyBookLeftCycle.v proves the literal q6 -> q5 left cycle.  Its
    postcondition is

      cfg_ml 5
        (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
         6 :: outer)
        ...

    Physically the source side is

      rev outer ++ [6] ++ [source_bit w] ++ [0^b] ++ [5] ++ ...

    so the new buffer segment (the cells strictly to the right of the new
    head marker 6) is [source_bit w :: 0^b], of length b+1.  It is not
    the zero-buffer normal form [0^buf] of the locate/steady frames
    unless the write bit is false.  With the write bit true the left
    cycle has no [book_buf] preimage at all.

    The concrete instance below uses

      bits = [false], init = [], w = true, b = 1,
      ptape = [1], target = true, desc_tail = [], tags = [2;3;2].

    The literal run lands on the physical source side

      6 1 0 5 3 4 0 1 0 0

    (M = 6, write bit 1, one blank buffer cell 0, Y = 5, then the next
    read mark 3 and the restored description).  The correct buffer count
    is therefore 2 = b+1, and the correct raw buffer is [1;0], not
    [0;0] and certainly not [0^0] from b-1.

    This file creates no new mathematical assumptions; it only unfolds
    the existing kernel-checked [book_q6_to_q5_left] theorem and compares
    lists. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalInstruction
  MinskyCanonicalDirection MinskyCanonicalRestore MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyRelocationMacro MinskyBookLeft MinskyBookLayout
  MinskyBookCycle MinskyBookLeftCycle.

Lemma rev_book_return_rail :
  forall (init : list bool) (b : nat),
    rev (book_return_rail init b) =
    book_buf b ++ [5] ++ map source_bit init.
Proof.
  intros init b.
  unfold book_return_rail.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  assert (Hbb : rev (rev (book_buf b)) = book_buf b)
    by apply rev_involutive.
  rewrite Hbb.
  assert (Hii : rev (rev (map source_bit init)) = map source_bit init)
    by apply rev_involutive.
  rewrite Hii.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma rev_cons_rev :
  forall (D : list nat) (x : nat),
    rev (x :: rev D) = D ++ [x].
Proof.
  intros D x. cbn [rev]. rewrite rev_involutive. reflexivity.
Qed.

(** ** General physical form of the left output

    The output's physical tape is the reverse of the zipper's left list.
    Under [dir_head :: dir_remaining = book_return_rail init b] this is
    [rev outer, 6, source_bit w, 0^b, Y, init]. *)

Lemma book_left_output_source_frame :
  forall (init : list bool) (w : bool) (b : nat) (outer : list nat)
         (dir_head : nat) (dir_remaining : list nat),
    dir_head :: dir_remaining = book_return_rail init b ->
    rev (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
         6 :: outer)
    = rev outer ++ 6 :: source_bit w :: book_buf b ++
      5 :: map source_bit init.
Proof.
  intros init w b outer dir_head dir_remaining HD.
  rewrite HD.
  rewrite rev_cons_rev.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_book_return_rail.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

(** Specialized to a [true] write bit: the segment after [6] starts with
    [1], so it cannot be a run of zeros. *)
Lemma book_left_output_source_frame_true :
  forall (init : list bool) (b : nat) (outer : list nat)
         (dir_head : nat) (dir_remaining : list nat),
    dir_head :: dir_remaining = book_return_rail init b ->
    rev (rev (source_bit true :: rev (dir_head :: dir_remaining)) ++
         6 :: outer)
    = rev outer ++ 6 :: 1 :: book_buf b ++
      5 :: map source_bit init.
Proof.
  intros init b outer dir_head dir_remaining HD.
  rewrite (book_left_output_source_frame init true b outer
    dir_head dir_remaining HD).
  reflexivity.
Qed.

(** ** The concrete left cycle *)

Definition audit_input : Config :=
  entry_config 6 (book_q6_left [false] 1 [1]) [2;1;0;0].

Definition audit_output : Config :=
  cfg_ml 5 [5;0;1;6]
    (3 :: map q16_restore (rev ([2;3;2] ++ [4])) ++ [0]).

Lemma audit_left_cycle_run :
  run (book_left_clock [false] [] true 1 [] [2;3;2] 5 [0])
    audit_input = audit_output.
Proof.
  unfold audit_input, audit_output.
  apply (book_q6_to_q5_left
    [false] [] true 1 [1] [] false []
    true [] 5 [0] [2;3;2]).
  - reflexivity.
  - lia.
  - reflexivity.
  - reflexivity.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
  - reflexivity.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
Qed.

Lemma audit_output_tape :
  c_tape audit_output =
  {| t_left := [0;1;6];
     t_right := [5;3;4;0;1;0;0] |}.
Proof. vm_compute. reflexivity. Qed.

Lemma audit_output_physical :
  rev (t_left (c_tape audit_output)) ++ t_right (c_tape audit_output)
  = [6;1;0;5;3;4;0;1;0;0].
Proof. vm_compute. reflexivity. Qed.

(** ** No zero-buffer preimage *)

(** The left prefix of a book frame consists of raw source bits [0/1];
    after the unique [6] the zero-buffer normal form has only [0]s up to
    the delimiter [5].  A [1] immediately after [6] excludes it. *)
Lemma zero_buffer_after_marker_ne_true :
  forall (P : list nat) (B : nat) (suffix : list nat),
    Forall (fun x => x = 0 \/ x = 1) P ->
    P ++ 6 :: book_buf B ++ 5 :: suffix
    <> 6 :: 1 :: 0 :: 5 :: suffix.
Proof.
  intros P B suffix HP.
  unfold book_buf in *.
  destruct P as [|p P].
  - destruct B as [|B']; simpl; discriminate.
  - inversion HP as [|x xs Hx Hxs]; subst.
    destruct Hx as [-> | ->]; simpl; discriminate.
Qed.

Theorem audit_left_output_not_zero_buffer_frame :
  forall (P : list nat) (B : nat),
    Forall (fun x => x = 0 \/ x = 1) P ->
    P ++ 6 :: book_buf B ++ 5 :: [3;4;0;1;0;0]
    <> [6;1;0;5;3;4;0;1;0;0].
Proof.
  intros P B HP.
  change (P ++ 6 :: book_buf B ++ 5 :: [3;4;0;1;0;0]
          <> 6 :: 1 :: 0 :: 5 :: [3;4;0;1;0;0]).
  apply zero_buffer_after_marker_ne_true. exact HP.
Qed.

(** Directly: the actual output tape is not in zero-buffer normal form. *)
Corollary audit_left_cycle_output_not_zero_buffer :
  forall (P : list nat) (B : nat),
    Forall (fun x => x = 0 \/ x = 1) P ->
    P ++ 6 :: book_buf B ++ 5 :: [3;4;0;1;0;0]
    <> rev (t_left (c_tape audit_output)) ++
       t_right (c_tape audit_output).
Proof.
  intros P B HP.
  rewrite audit_output_physical.
  apply audit_left_output_not_zero_buffer_frame. exact HP.
Qed.

(** ** The missing count is [b+1], not [b] or [b-1] *)

Lemma left_output_buffer_length :
  forall (w : bool) (b : nat),
    length (source_bit w :: book_buf b) = b + 1.
Proof.
  intros w b. unfold book_buf. cbn [length].
  rewrite repeat_length. lia.
Qed.

(** The concrete input buffer has [b = 1] zero cell; the output buffer
    segment [1;0] has length [2 = b+1]. *)
Example audit_input_buffer_length :
  length (book_buf 1) = 1.
Proof. reflexivity. Qed.

Example audit_output_buffer_length :
  length (1 :: 0 :: []) = 2.
Proof. reflexivity. Qed.

(** If one reuses the left perform's *input* [book_buf (b-1)] as the
    output accounting (as the internal restore clock does), the count is
    [b-1], which is two short of the actual [b+1] for the concrete
    [b = 1] instance. *)
Example audit_input_restore_buffer_length :
  length (book_buf (1 - 1)) = 0.
Proof. reflexivity. Qed.

Print Assumptions audit_left_cycle_run.
Print Assumptions audit_left_cycle_output_not_zero_buffer.
Print Assumptions book_left_output_source_frame.
