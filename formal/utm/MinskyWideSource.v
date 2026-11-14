(** * Variable-width binary source records for the unchanged Minsky UTM

    The native p=9 compiler test emits X, p current-state bits, one read
    bit, p next-state bits, one write bit and one direction bit.  Unlike
    the earlier fixed two-bit representation, this format supports any
    finite state width p, provided both state fields have that width.

    The results below certify the variable-width *source format*, not yet
    the 23x8 table's entire instruction-simulation macro.
*)

From Coq Require Import List Arith Bool Lia ZArith.
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
    now rewrite (IH suffix).
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
  intros [a b c d e f g].
  unfold wide_row_wellformed, widen_two_bit_row; simpl.
  split; reflexivity.
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

(** ** An actual parser for p-bit source instruction streams

    Unlike a fixed two-bit decoder, this consumes the width supplied by
    the source-machine description.  It rejects malformed symbols and
    truncation rather than silently interpreting them as zeros. *)
Definition decode_wide_row (p : nat) (xs : list nat)
    : option (WideSourceRow * list nat) :=
  match xs with
  | 4 :: rest =>
      match decode_n_bits p rest with
      | Some (current, read_token :: after_read) =>
          match parse_source_bit read_token,
                decode_n_bits p after_read with
          | Some scanned, Some (next, write_token :: direction_token :: tail) =>
              match parse_source_bit write_token,
                    parse_source_bit direction_token with
              | Some written, Some direction =>
                  Some ({| wr_current := current; wr_read := scanned;
                           wr_next := next; wr_write := written;
                           wr_right := direction |}, tail)
              | _, _ => None
              end
          | _, _ => None
          end
      | _ => None
      end
  | _ => None
  end.

Lemma decode_wide_row_roundtrip :
  forall p row suffix,
    wide_row_wellformed p row ->
    decode_wide_row p (encode_wide_row row ++ suffix) =
      Some (row, suffix).
Proof.
  intros p [current scanned next written direction] suffix [Hc Hn].
  unfold wide_row_wellformed in *; simpl in Hc, Hn.
  assert (Hp : p = length current) by lia.
  subst p.
  unfold decode_wide_row, encode_wide_row; simpl.
  match goal with |- ?G => idtac "WIDE_DECODE_GOAL:" G end.
  rewrite decode_n_bits_roundtrip.
  simpl.
  rewrite parse_source_bit_roundtrip.
  rewrite <- Hn.
  rewrite decode_n_bits_roundtrip.
  simpl.
  now rewrite !parse_source_bit_roundtrip.
Qed.

Fixpoint decode_wide_prefix (p count : nat) (bytes : list nat)
    : option (list WideSourceRow * list nat) :=
  match count with
  | O => Some ([], bytes)
  | S n =>
      match decode_wide_row p bytes with
      | None => None
      | Some (row, tail) =>
          match decode_wide_prefix p n tail with
          | None => None
          | Some (rows, suffix) => Some (row :: rows, suffix)
          end
      end
  end.

Definition encode_wide_program (rows : list WideSourceRow) : list nat :=
  concat (map encode_wide_row rows).

Theorem wide_program_roundtrip :
  forall p rows suffix,
    Forall (wide_row_wellformed p) rows ->
    decode_wide_prefix p (length rows)
      (encode_wide_program rows ++ suffix) = Some (rows, suffix).
Proof.
  intros p rows; induction rows as [|row rows IH]; intros suffix Hwf.
  - reflexivity.
  - inversion Hwf as [|? ? Hrow Hrest]; subst.
    change (decode_wide_prefix p (S (length rows))
      (encode_wide_row row ++ (encode_wide_program rows ++ suffix)) =
      Some (row :: rows, suffix)).
    simpl [decode_wide_prefix].
    rewrite (decode_wide_row_roundtrip p row
      (encode_wide_program rows ++ suffix) Hrow).
    now rewrite IH.
Qed.

(** ** Unbounded-tape operational semantics for variable-width programs *)

Definition wide_row_matches (r : WideSourceRow)
    (state : list bool) (bit : bool) : bool :=
  if list_eq_dec Bool.bool_dec (wr_current r) state
  then Bool.eqb (wr_read r) bit else false.

Definition wide_source_lookup (rows : list WideSourceRow)
    (state : list bool) (bit : bool) : option WideSourceRow :=
  find (fun row => wide_row_matches row state bit) rows.

Record WideSourceConfig := {
  wc_state : list bool;
  wc_head : Z;
  wc_tape : Z -> bool;
  wc_halted : bool
}.

Definition wide_source_step (rows : list WideSourceRow)
    (c : WideSourceConfig) : WideSourceConfig :=
  if wc_halted c then c else
    match wide_source_lookup rows (wc_state c)
                            (wc_tape c (wc_head c)) with
    | None =>
        {| wc_state := wc_state c; wc_head := wc_head c;
           wc_tape := wc_tape c; wc_halted := true |}
    | Some row =>
        {| wc_state := wr_next row;
           wc_head := (wc_head c + (if wr_right row then 1 else -1))%Z;
           wc_tape := source_write_at (wc_tape c) (wc_head c)
                                      (wr_write row);
           wc_halted := false |}
    end.

Fixpoint wide_source_run (fuel : nat) (rows : list WideSourceRow)
    (c : WideSourceConfig) : WideSourceConfig :=
  match fuel with
  | O => c
  | S n => wide_source_run n rows (wide_source_step rows c)
  end.

Definition decoded_wide_step (p count : nat) (bytes : list nat)
    (c : WideSourceConfig) : option WideSourceConfig :=
  match decode_wide_prefix p count bytes with
  | None => None
  | Some (rows, _) => Some (wide_source_step rows c)
  end.

Fixpoint decoded_wide_run (fuel p count : nat) (bytes : list nat)
    (c : WideSourceConfig) : option WideSourceConfig :=
  match fuel with
  | O => Some c
  | S n =>
      match decoded_wide_step p count bytes c with
      | None => None
      | Some next => decoded_wide_run n p count bytes next
      end
  end.

Theorem encoded_wide_run_refines :
  forall fuel p rows suffix c,
    Forall (wide_row_wellformed p) rows ->
    decoded_wide_run fuel p (length rows)
      (encode_wide_program rows ++ suffix) c =
    Some (wide_source_run fuel rows c).
Proof.
  induction fuel as [|n IH]; intros p rows suffix c Hwf; simpl.
  - reflexivity.
  - unfold decoded_wide_step.
    rewrite (wide_program_roundtrip p rows suffix Hwf).
    apply IH. exact Hwf.
Qed.

(** The previous four-state interpreter is not replaced: the p=2 case
    below refines it exactly, including its first-match and halt rules. *)
Definition lift_binary_config (c : BinarySourceConfig) : WideSourceConfig :=
  {| wc_state := [sc_state_hi c; sc_state_lo c];
     wc_head := sc_head c; wc_tape := sc_tape c;
     wc_halted := sc_halted c |}.

Lemma wide_matches_binary :
  forall r hi lo bit,
    wide_row_matches (widen_two_bit_row r) [hi; lo] bit =
    source_row_matches r hi lo bit.
Proof.
  intros [a b c d e f g] hi lo bit.
  destruct a, b, c, hi, lo, bit; reflexivity.
Qed.

Lemma wide_lookup_binary :
  forall rows hi lo bit,
    wide_source_lookup (map widen_two_bit_row rows) [hi; lo] bit =
    option_map widen_two_bit_row (source_lookup rows hi lo bit).
Proof.
  induction rows as [|row rest IH]; intros hi lo bit; simpl.
  - reflexivity.
  - rewrite wide_matches_binary.
    destruct (source_row_matches row hi lo bit); simpl; auto.
Qed.

Theorem wide_two_bit_step_refines :
  forall rows c,
    wide_source_step (map widen_two_bit_row rows) (lift_binary_config c) =
    lift_binary_config (source_step rows c).
Proof.
  intros rows [hi lo head tape halted].
  unfold wide_source_step, source_step, lift_binary_config; simpl.
  destruct halted; [reflexivity |].
  rewrite wide_lookup_binary.
  destruct (source_lookup rows hi lo (tape head))
    as [row|]; reflexivity.
Qed.

Theorem wide_two_bit_run_refines :
  forall fuel rows c,
    wide_source_run fuel (map widen_two_bit_row rows)
      (lift_binary_config c) =
    lift_binary_config (source_run fuel rows c).
Proof.
  induction fuel as [|n IH]; intros rows c;
    cbn [wide_source_run source_run].
  - reflexivity.
  - rewrite wide_two_bit_step_refines.
    apply IH.
Qed.

Example nine_bit_program_parses :
  decode_wide_prefix 9 1
    (encode_wide_program [wide_nine_bit_example] ++ [5; 2]) =
    Some ([wide_nine_bit_example], [5; 2]).
Proof. reflexivity. Qed.

Print Assumptions wide_program_roundtrip.
Print Assumptions encoded_wide_run_refines.
Print Assumptions wide_two_bit_run_refines.
