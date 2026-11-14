(** * A literal binary-source description for the 23x8 Minsky interpreter

    This is the *source-description* part of the concrete universality
    obligation.  The shipped example uses records of the form

       X q(2) read(1) q'(2) write(1) direction(1)

    where X is symbol 4, the two-bit control states are 0..3, and direction
    0/1 denotes left/right.  An absent row is the source halt condition.
    The parser consumes exactly the requested number of eight-symbol rows.

    The results below prove a genuine, constructive round trip and a
    fuel-independent simulation of the *decoded source interpreter* for all
    finite descriptions in this format, including first-match duplicates.

    They do NOT establish a macro-step simulation by MinskyTable.step and
    do NOT reduce arbitrary Turing machines to this four-state source class.
    Thus they are not a universality theorem for the concrete 23x8 table.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.

Definition source_bit (b : bool) : nat := if b then 1 else 0.

Definition parse_source_bit (n : nat) : option bool :=
  match n with
  | 0 => Some false
  | 1 => Some true
  | _ => None
  end.

Lemma parse_source_bit_roundtrip :
  forall b, parse_source_bit (source_bit b) = Some b.
Proof. intros []; reflexivity. Qed.

Record BinarySourceRow := {
  sr_state_hi : bool;
  sr_state_lo : bool;
  sr_read : bool;
  sr_next_hi : bool;
  sr_next_lo : bool;
  sr_write : bool;
  sr_right : bool
}.

Definition encode_source_row (r : BinarySourceRow) : list nat :=
  [4; source_bit (sr_state_hi r); source_bit (sr_state_lo r);
   source_bit (sr_read r); source_bit (sr_next_hi r);
   source_bit (sr_next_lo r); source_bit (sr_write r);
   source_bit (sr_right r)].

Definition decode_source_row (xs : list nat) : option BinarySourceRow :=
  match xs with
  | [marker; qhi; qlo; scanned; nhi; nlo; written; direction] =>
      if Nat.eqb marker 4 then
        match parse_source_bit qhi, parse_source_bit qlo,
              parse_source_bit scanned, parse_source_bit nhi,
              parse_source_bit nlo, parse_source_bit written,
              parse_source_bit direction with
        | Some a, Some b, Some c, Some d, Some e, Some f, Some g =>
            Some {| sr_state_hi := a; sr_state_lo := b; sr_read := c;
                    sr_next_hi := d; sr_next_lo := e; sr_write := f;
                    sr_right := g |}
        | _, _, _, _, _, _, _ => None
        end
      else None
  | _ => None
  end.

Theorem source_row_roundtrip :
  forall r, decode_source_row (encode_source_row r) = Some r.
Proof.
  intros [a b c d e f g].
  unfold decode_source_row, encode_source_row; simpl.
  now rewrite !parse_source_bit_roundtrip.
Qed.

(** Decode only [count] rows and return the untouched suffix.  This makes
    delimiter handling explicit: the trailing Y is NOT a source instruction. *)
Fixpoint decode_source_prefix (count : nat) (xs : list nat)
    : option (list BinarySourceRow * list nat) :=
  match count with
  | O => Some ([], xs)
  | S n =>
      match xs with
      | marker :: qhi :: qlo :: scanned :: nhi :: nlo :: written ::
          direction :: rest =>
          match decode_source_row
                  [marker; qhi; qlo; scanned; nhi; nlo; written; direction],
                decode_source_prefix n rest with
          | Some row, Some (rows, suffix) => Some (row :: rows, suffix)
          | _, _ => None
          end
      | _ => None
      end
  end.

Definition encode_source_program (rows : list BinarySourceRow) : list nat :=
  concat (map encode_source_row rows).

Lemma decode_source_prefix_cons :
  forall n row xs,
    decode_source_prefix (S n) (encode_source_row row ++ xs) =
      match decode_source_prefix n xs with
      | Some (rows, suffix) => Some (row :: rows, suffix)
      | None => None
      end.
Proof.
  intros n [a b c d e f g] xs.
  unfold encode_source_row; simpl.
  rewrite !parse_source_bit_roundtrip.
  destruct (decode_source_prefix n xs) as [[rows suffix]|]; reflexivity.
Qed.

(** Full-program round trip, with no limit on number of source rows. *)
Theorem source_program_roundtrip :
  forall rows suffix,
    decode_source_prefix (length rows)
      (encode_source_program rows ++ suffix) = Some (rows, suffix).
Proof.
  induction rows as [|row rows IH]; intro suffix.
  - reflexivity.
  - change (decode_source_prefix (S (length rows))
        (encode_source_row row ++ (encode_source_program rows ++ suffix)) =
        Some (row :: rows, suffix)).
    rewrite decode_source_prefix_cons.
    rewrite IH. reflexivity.
Qed.

(** The actual test's descriptor is embedded in a larger tape image:
      0^left ++ data ++ M ++ 0^buffer ++ Y ++ condition ++ rows ++ Y ++ 0^right.
    The present theorem permits any such prefix/suffix without conflating
    the delimiters with instruction bits. *)
Theorem source_program_framed_roundtrip :
  forall prefix rows suffix,
    decode_source_prefix (length rows)
      (skipn (length prefix)
         (prefix ++ encode_source_program rows ++ suffix)) =
    Some (rows, suffix).
Proof.
  intros prefix rows suffix.
  induction prefix as [|p prefix IH]; simpl.
  - apply source_program_roundtrip.
  - exact IH.
Qed.

Definition source_row_matches (r : BinarySourceRow)
    (qhi qlo scanned : bool) : bool :=
  Bool.eqb (sr_state_hi r) qhi &&
  Bool.eqb (sr_state_lo r) qlo && Bool.eqb (sr_read r) scanned.

Definition source_lookup (rows : list BinarySourceRow)
    (qhi qlo scanned : bool) : option BinarySourceRow :=
  find (fun row => source_row_matches row qhi qlo scanned) rows.

(** An unbounded binary working tape and exactly the first-match semantics
    of a deterministic source description.  No fixed-width head assumption. *)
Record BinarySourceConfig := {
  sc_state_hi : bool;
  sc_state_lo : bool;
  sc_head : Z;
  sc_tape : Z -> bool;
  sc_halted : bool
}.

Definition source_write_at (t : Z -> bool) (h : Z) (bit : bool)
    : Z -> bool :=
  fun p => if Z.eqb p h then bit else t p.

Definition source_step (rows : list BinarySourceRow)
    (c : BinarySourceConfig) : BinarySourceConfig :=
  if sc_halted c then c
  else
    match source_lookup rows (sc_state_hi c) (sc_state_lo c)
                             (sc_tape c (sc_head c)) with
    | None => {| sc_state_hi := sc_state_hi c;
                 sc_state_lo := sc_state_lo c;
                 sc_head := sc_head c;
                 sc_tape := sc_tape c;
                 sc_halted := true |}
    | Some row =>
        {| sc_state_hi := sr_next_hi row;
           sc_state_lo := sr_next_lo row;
           sc_head := sc_head c + (if sr_right row then 1 else -1);
           sc_tape := source_write_at (sc_tape c) (sc_head c) (sr_write row);
           sc_halted := false |}
    end.

Fixpoint source_run (fuel : nat) (rows : list BinarySourceRow)
    (c : BinarySourceConfig) : BinarySourceConfig :=
  match fuel with
  | O => c
  | S n => source_run n rows (source_step rows c)
  end.

Definition decoded_source_step (count : nat) (bytes : list nat)
    (c : BinarySourceConfig) : option BinarySourceConfig :=
  match decode_source_prefix count bytes with
  | None => None
  | Some (rows, _) => Some (source_step rows c)
  end.

Fixpoint decoded_source_run (fuel count : nat) (bytes : list nat)
    (c : BinarySourceConfig) : option BinarySourceConfig :=
  match fuel with
  | O => Some c
  | S n =>
      match decoded_source_step count bytes c with
      | None => None
      | Some next => decoded_source_run n count bytes next
      end
  end.

Theorem encoded_source_step_refines :
  forall rows suffix c,
    decoded_source_step (length rows)
      (encode_source_program rows ++ suffix) c =
    Some (source_step rows c).
Proof.
  intros rows suffix c. unfold decoded_source_step.
  now rewrite source_program_roundtrip.
Qed.

Theorem encoded_source_run_refines :
  forall fuel rows suffix c,
    decoded_source_run fuel (length rows)
      (encode_source_program rows ++ suffix) c =
    Some (source_run fuel rows c).
Proof.
  induction fuel as [|n IH]; intros rows suffix c; simpl.
  - reflexivity.
  - rewrite encoded_source_step_refines.
    apply IH.
Qed.

(** The exact two transition words used by the shipped C++ example:
      q0,0 -> q1,1,R; q1,0 -> q2,1,R. *)
Definition source_example_rows : list BinarySourceRow :=
  [{| sr_state_hi := false; sr_state_lo := false; sr_read := false;
      sr_next_hi := false; sr_next_lo := true; sr_write := true;
      sr_right := true |};
   {| sr_state_hi := false; sr_state_lo := true; sr_read := false;
      sr_next_hi := true; sr_next_lo := false; sr_write := true;
      sr_right := true |}].

Example source_example_matches_native_fixture :
  encode_source_program source_example_rows =
    [4; 0; 0; 0; 0; 1; 1; 1;
     4; 0; 1; 0; 1; 0; 1; 1].
Proof. reflexivity. Qed.

Example source_example_parses_with_delimiter :
  decode_source_prefix 2
    (encode_source_program source_example_rows ++ [5; 0; 0; 0]) =
    Some (source_example_rows, [5; 0; 0; 0]).
Proof. reflexivity. Qed.

Print Assumptions source_program_roundtrip.
Print Assumptions encoded_source_run_refines.
