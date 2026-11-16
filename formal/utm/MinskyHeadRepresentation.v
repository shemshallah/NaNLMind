(** * The displaced-head-cell invariant for Minsky's binary source tape

    The symbol M=6 REPLACES the source head cell in the physical data
    region.  Its current 0/1 value is stored separately in the machine
    condition, before the first program X.  M is not a gap that leaves
    the current source symbol adjacent to it.

    This module makes the representation constructive and proves both
    ordinary interior source-head directions preserve the logical tape
    after a write.  It is an encoding theorem, not an assertion that
    q14..q22 have executed those movements.
*)

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskySourceEncoding.

Record DisplacedHead := {
  dh_left_rev : list bool;
  dh_current : bool;
  dh_right : list bool
}.

Definition displaced_physical_data (h : DisplacedHead) : list nat :=
  map source_bit (rev (dh_left_rev h)) ++
  6 :: map source_bit (dh_right h).

Definition displaced_logical_tape (h : DisplacedHead) : list bool :=
  rev (dh_left_rev h) ++ dh_current h :: dh_right h.

Definition displaced_written_tape (written : bool)
    (h : DisplacedHead) : list bool :=
  rev (dh_left_rev h) ++ written :: dh_right h.

Fixpoint split_m_marker (xs : list nat) :
    option (list nat * list nat) :=
  match xs with
  | [] => None
  | 6 :: rest => Some ([], rest)
  | s :: rest =>
      match split_m_marker rest with
      | Some (prefix_bytes, suffix_bytes) => Some (s :: prefix_bytes, suffix_bytes)
      | None => None
      end
  end.

Fixpoint decode_binary_cells (xs : list nat) : option (list bool) :=
  match xs with
  | [] => Some []
  | s :: rest =>
      match parse_source_bit s, decode_binary_cells rest with
      | Some b, Some tail => Some (b :: tail)
      | _, _ => None
      end
  end.

Definition decode_displaced_head
    (current : bool) (physical : list nat) : option DisplacedHead :=
  match split_m_marker physical with
  | None => None
  | Some (before, after) =>
      match decode_binary_cells before, decode_binary_cells after with
      | Some decoded_left, Some decoded_right =>
          Some {| dh_left_rev := rev decoded_left;
                  dh_current := current; dh_right := decoded_right |}
      | _, _ => None
      end
  end.

Lemma split_m_marker_roundtrip :
  forall left right,
    split_m_marker (map source_bit left ++ 6 :: right) =
    Some (map source_bit left, right).
Proof.
  induction left as [|b left IH]; intro right.
  - reflexivity.
  - destruct b; simpl; now rewrite IH.
Qed.

Lemma decode_binary_cells_roundtrip :
  forall cells,
    decode_binary_cells (map source_bit cells) = Some cells.
Proof.
  induction cells as [|b cells IH]; simpl.
  - reflexivity.
  - rewrite parse_source_bit_roundtrip, IH. reflexivity.
Qed.

Theorem displaced_head_roundtrip :
  forall h,
    decode_displaced_head (dh_current h)
      (displaced_physical_data h) = Some h.
Proof.
  intros [left current right].
  unfold decode_displaced_head, displaced_physical_data; simpl.
  rewrite split_m_marker_roundtrip.
  rewrite !decode_binary_cells_roundtrip.
  rewrite rev_involutive.
  reflexivity.
Qed.

(** Finite normal forms extend an absent neighbour with a blank false
    symbol.  A full source semantics can use unbounded signed addresses. *)
Definition displaced_write_left (written : bool)
    (h : DisplacedHead) : DisplacedHead :=
  match dh_left_rev h with
  | [] => {| dh_left_rev := []; dh_current := false;
             dh_right := written :: dh_right h |}
  | b :: remaining_left => {| dh_left_rev := remaining_left; dh_current := b;
                   dh_right := written :: dh_right h |}
  end.

Definition displaced_write_right (written : bool)
    (h : DisplacedHead) : DisplacedHead :=
  match dh_right h with
  | [] => {| dh_left_rev := written :: dh_left_rev h;
             dh_current := false; dh_right := [] |}
  | b :: remaining_right => {| dh_left_rev := written :: dh_left_rev h;
                    dh_current := b; dh_right := remaining_right |}
  end.

Lemma head_singleton_append :
  forall (A : Type) (xs : list A) (x : A) ys,
    (xs ++ [x]) ++ ys = xs ++ x :: ys.
Proof.
  intros A xs x ys.
  induction xs as [|h xs IH]; simpl.
  - reflexivity.
  - now rewrite IH.
Qed.

Lemma displaced_left_marker_layout :
  forall left neighbor current right written,
    displaced_physical_data
      (displaced_write_left written
        {| dh_left_rev := neighbor :: left;
           dh_current := current; dh_right := right |}) =
    map source_bit (rev left) ++
      6 :: source_bit written :: map source_bit right.
Proof. reflexivity. Qed.

Lemma displaced_right_marker_layout :
  forall left current neighbor right written,
    displaced_physical_data
      (displaced_write_right written
        {| dh_left_rev := left;
           dh_current := current; dh_right := neighbor :: right |}) =
    map source_bit (rev left) ++
      source_bit written :: 6 :: map source_bit right.
Proof.
  intros left current neighbor right written.
  unfold displaced_physical_data, displaced_write_right; simpl.
  rewrite map_app.
  simpl.
  rewrite head_singleton_append.
  reflexivity.
Qed.

(** Both internal moves update the logical old head cell with [written],
    without duplicating the displaced bit or confusing it with the new
    source-head symbol. *)
Theorem displaced_left_write_sound :
  forall left neighbor current right written,
    displaced_logical_tape
      (displaced_write_left written
        {| dh_left_rev := neighbor :: left;
           dh_current := current; dh_right := right |}) =
    displaced_written_tape written
      {| dh_left_rev := neighbor :: left;
         dh_current := current; dh_right := right |}.
Proof.
  intros left neighbor current right written.
  unfold displaced_logical_tape, displaced_write_left,
    displaced_written_tape; simpl.
  symmetry.
  rewrite head_singleton_append.
  reflexivity.
Qed.

Theorem displaced_right_write_sound :
  forall left current neighbor right written,
    displaced_logical_tape
      (displaced_write_right written
        {| dh_left_rev := left;
           dh_current := current; dh_right := neighbor :: right |}) =
    displaced_written_tape written
      {| dh_left_rev := left;
         dh_current := current; dh_right := neighbor :: right |}.
Proof.
  intros left current neighbor right written.
  unfold displaced_logical_tape, displaced_write_right,
    displaced_written_tape; simpl.
  rewrite head_singleton_append.
  reflexivity.
Qed.

Print Assumptions displaced_head_roundtrip.
Print Assumptions displaced_left_write_sound.
Print Assumptions displaced_right_write_sound.
