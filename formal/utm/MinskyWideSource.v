(** * Variable-width binary source records for the unchanged Minsky UTM

    The native p=9 compiler test emits X, p current-state bits, one read
    bit, p next-state bits, one write bit and one direction bit.  Unlike
    the earlier fixed two-bit representation, this format supports any
    finite state width p, provided both state fields have that width.

    The results below certify the variable-width *source format*, not yet
    the 23x8 table's entire instruction-simulation macro.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskySourceEncoding.

Record WideSourceRow := {
  wr_current : list bool;
  wr_read : bool;
  wr_next : list bool;
  wr_write : bool;
  wr_right : bool
}.

Definition wide_row_wellformed (p : nat) (r : WideSourceRow) : Prop :=
  length (wr_current r) = p /\ length (wr_next r) = p.

Definition encode_wide_row (r : WideSourceRow) : list nat :=
  4 :: map source_bit (wr_current r) ++
    [source_bit (wr_read r)] ++
    map source_bit (wr_next r) ++
    [source_bit (wr_write r); source_bit (wr_right r)].

Fixpoint decode_n_bits (n : nat) (xs : list nat)
    : option (list bool * list nat) :=
  match n with
  | O => Some ([], xs)
  | S k =>
      match xs with
      | [] => None
      | x :: rest =>
          match parse_source_bit x, decode_n_bits k rest with
          | Some b, Some (bits, suffix) => Some (b :: bits, suffix)
          | _, _ => None
          end
      end
  end.

(** A constructive prefix parser for an arbitrary number of state bits.
    It consumes exactly n symbols, leaving all subsequent tape symbols
    untouched.  The theorem does not depend on a chosen maximum width. *)
Theorem decode_n_bits_roundtrip :
  forall bits suffix,
    decode_n_bits (length bits) (map source_bit bits ++ suffix) =
    Some (bits, suffix).
Proof.
  induction bits as [|b bits IH]; intro suffix.
  - reflexivity.
  - cbn [length map app decode_n_bits].
    rewrite parse_source_bit_roundtrip.
    now rewrite IH.
Qed.

Theorem decode_n_bits_framed_roundtrip :
  forall prefix bits suffix,
    decode_n_bits (length bits)
      (skipn (length prefix)
        (prefix ++ map source_bit bits ++ suffix)) =
    Some (bits, suffix).
Proof.
  intros prefix bits suffix.
  induction prefix as [|x prefix IH].
  - simpl. apply decode_n_bits_roundtrip.
  - simpl. exact IH.
Qed.

Theorem wide_row_size :
  forall p r,
    wide_row_wellformed p r ->
    length (encode_wide_row r) = 2 * p + 4.
Proof.
  intros p [current scanned next written direction] [Hcurrent Hnext].
  simpl in Hcurrent, Hnext.
  unfold encode_wide_row. simpl.
  repeat rewrite app_length.
  repeat rewrite map_length.
  simpl.
  lia.
Qed.

Definition widen_two_bit_row (r : BinarySourceRow) : WideSourceRow :=
  {| wr_current := [sr_state_hi r; sr_state_lo r];
     wr_read := sr_read r;
     wr_next := [sr_next_hi r; sr_next_lo r];
     wr_write := sr_write r;
     wr_right := sr_right r |}.

(** The original two-state-bit source format is exactly the p=2 case;
    the generalization does not fork or alter that original encoding. *)
Theorem wide_two_bit_compatibility :
  forall r,
    encode_wide_row (widen_two_bit_row r) = encode_source_row r.
Proof.
  intros [a b c d e f g]. reflexivity.
Qed.

Theorem wide_two_bit_is_wellformed :
  forall r, wide_row_wellformed 2 (widen_two_bit_row r).
Proof.
  intros [a b c d e f g]. reflexivity.
Qed.

Definition wide_nine_bit_example : WideSourceRow :=
  {| wr_current := repeat false 9;
     wr_read := true;
     wr_next := repeat false 8 ++ [true];
     wr_write := true;
     wr_right := true |}.

Example wide_nine_bit_example_size :
  length (encode_wide_row wide_nine_bit_example) = 22.
Proof. reflexivity. Qed.

Print Assumptions decode_n_bits_roundtrip.
Print Assumptions decode_n_bits_framed_roundtrip.
Print Assumptions wide_two_bit_compatibility.
