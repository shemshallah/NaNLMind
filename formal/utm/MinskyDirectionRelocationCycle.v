(** * Exact q15--q22 direction and relocation cycles for the frozen 23x8 table

    This module COMPOSES previously certified native transition-table
    lemmas.  The starting tape has a displaced current bit, a nonempty
    marked scan, and a direction marker (2=left, 3=right).

    The two direction-decision theorems run q15, q16 and q21/q22.
    The two relocation theorems continue, respectively, via
      right: q19 -> q17/q18 -> q5,
      left:  q20 -> q17/q18 -> q5.
    All microstep counts are exact, and every scan has a stated Forall
    condition.  These are NOT yet whole-instruction source simulations:
    the source-row matching, halt, and complete encoding invariants must
    still be connected to these entry configurations.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyActionMacro MinskyWritebackMacro
  MinskyHeadMoveMacro MinskyDirectionDecision MinskyRelocationMacro
  MinskyDirectionCycle MinskyWideSource MinskyWideConcreteDispatch.

Definition direction_phase_cost (scan direction_scan : list nat) : nat :=
  S (length (rev scan)) +
    (S (length scan) + S (length direction_scan)).

(** The first raw cell to the right is encountered after the marked
    q15 scan. q16 restores that scan, records the old raw bit as 7,
    and q21/q22 reads the left-side direction marker. *)
Theorem q15_q22_right_to_q19 :
  forall s remaining dir_head dir_remaining old next outer suffix,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (s :: remaining) ++ source_bit next :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix).
Proof.
  intros s remaining dir_head dir_remaining old next outer suffix
    H15 H16 H21.
  unfold direction_phase_cost.
  rewrite writeback_run_add.
  rewrite (q15_scan_to_raw (rev (s :: remaining)) next
    (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
    suffix H15).
  rewrite rev_involutive.
  match goal with
  | |- _ = ?expected =>
    change (run (S (length (s :: remaining)) +
                  S (length (dir_head :: dir_remaining)))
    (entry_config 16
      (remaining ++ source_bit old ::
        dir_head :: dir_remaining ++ 3 :: outer)
      (s :: source_bit next :: suffix)) = expected)
  end.
  rewrite writeback_run_add.
  rewrite (q16_restore_to_raw remaining s old
    (dir_head :: dir_remaining ++ 3 :: outer)
    (source_bit next :: suffix) H16).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head :: 7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix)) = expected)
  end.
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22).
  { destruct old; simpl; auto. }
  rewrite (q21_scan_to_right_direction
    dir_remaining dir_head (if old then 22 else 21) outer
    (7 :: map q16_restore (rev (s :: remaining)) ++
     source_bit next :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Theorem q15_q22_left_to_q20 :
  forall s remaining dir_head dir_remaining old next target outer suffix,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++
          2 :: source_bit target :: outer)
        (rev (s :: remaining) ++ source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix).
Proof.
  intros s remaining dir_head dir_remaining old next target outer suffix
    H15 H16 H21.
  unfold direction_phase_cost.
  rewrite writeback_run_add.
  rewrite (q15_scan_to_raw (rev (s :: remaining)) next
    (source_bit old :: dir_head :: dir_remaining ++
      2 :: source_bit target :: outer) suffix H15).
  rewrite rev_involutive.
  match goal with
  | |- _ = ?expected =>
    change (run (S (length (s :: remaining)) +
                  S (length (dir_head :: dir_remaining)))
    (entry_config 16
      (remaining ++ source_bit old ::
        dir_head :: dir_remaining ++
        2 :: source_bit target :: outer)
      (s :: source_bit next :: suffix)) = expected)
  end.
  rewrite writeback_run_add.
  rewrite (q16_restore_to_raw remaining s old
    (dir_head :: dir_remaining ++ 2 :: source_bit target :: outer)
    (source_bit next :: suffix) H16).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 2 :: source_bit target :: outer)
      (dir_head :: 7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix)) = expected)
  end.
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22).
  { destruct old; simpl; auto. }
  rewrite (q21_scan_to_left_direction
    dir_remaining dir_head (if old then 22 else 21)
    (source_bit target :: outer)
    (7 :: map q16_restore (rev (s :: remaining)) ++
     source_bit next :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

(** The right branch crosses all restored cells until the next raw bit,
    displaces that bit to M=6, and finds a subsequent 7 marker. The
    additional q19-pass premise is essential: q16 may restore 2/3 to
    raw 0/1, in which case q19 would stop earlier. *)
Theorem q15_q22_right_relocates_to_q5 :
  forall s remaining dir_head dir_remaining
         old next outer between final,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (s :: remaining))) ->
    Forall q17_pass between ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining) +
         (S (length
           (rev (dir_head :: dir_remaining) ++
            7 :: map q16_restore (rev (s :: remaining)))) +
          S (length between)))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (s :: remaining) ++
         source_bit next :: between ++ 7 :: final)) =
    cfg_ml 5
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++
            7 :: map q16_restore (rev (s :: remaining))) ++
       source_bit old :: outer)
      ((if next then 3 else 2) :: final).
Proof.
  intros s remaining dir_head dir_remaining old next outer between final
    H15 H16 H21 Hright Hbetween.
  rewrite writeback_run_add.
  rewrite (q15_q22_right_to_q19
    s remaining dir_head dir_remaining old next outer
    (between ++ 7 :: final) H15 H16 H21).
  replace
    (rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (s :: remaining)) ++
     source_bit next :: between ++ 7 :: final)
    with
    ((rev (dir_head :: dir_remaining) ++
      7 :: map q16_restore (rev (s :: remaining))) ++
      source_bit next :: between ++ 7 :: final).
  2:{ cbn [app]. repeat rewrite app_assoc.
      repeat rewrite <- app_assoc. reflexivity. }
  rewrite (q19_to_q5_relocation
    (rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (s :: remaining)))
    between next (source_bit old :: outer) final Hright Hbetween).
  reflexivity.
Qed.

(** For a left move, q20 immediately displaces the left neighbour and
    q17/q18 runs back right to the 7 left by q16. *)
Theorem q15_q22_left_relocates_to_q5 :
  forall s remaining dir_head dir_remaining
         old next target outer suffix,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass (rev (dir_head :: dir_remaining)) ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining) +
         (1 + S (length
           (source_bit old :: rev (dir_head :: dir_remaining)))))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev (s :: remaining) ++ source_bit next :: suffix)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix).
Proof.
  intros s remaining dir_head dir_remaining old next target outer suffix
    H15 H16 H21 Hreturn.
  assert (Hreturn' :
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining))).
  {
    constructor.
    - destruct old; unfold q17_pass, source_bit; simpl;
        [right; left; reflexivity | left; reflexivity].
    - exact Hreturn.
  }
  rewrite writeback_run_add.
  rewrite (q15_q22_left_to_q20
    s remaining dir_head dir_remaining old next target outer
    suffix H15 H16 H21).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix))) = expected)
  end.
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (s :: remaining)) ++
     source_bit next :: suffix)).
  destruct target.
  - exact (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix) Hreturn').
  - exact (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix) Hreturn').
Qed.

(** Exact safety condition for crossing a q16-restored scan in q19.
    Marks 2 and 3 are permitted by q15/q16, but become raw 0 and 1.
    Thus the old all-the-way-to-next-raw relocation premise is strictly
    stronger than the earlier direction-cycle premises. *)

Lemma q19_restored_cell_safe_iff :
  forall symbol,
    q15_pass (q16_restore symbol) <-> 4 <= symbol <= 7.
Proof.
  intros [|[|[|[|[|[|[|[|symbol]]]]]]]];
    unfold q15_pass, q16_restore; simpl; lia.
Qed.

Theorem q19_restored_scan_safe_iff :
  forall scanned,
    Forall q15_pass (map q16_restore scanned) <->
    Forall (fun symbol => 4 <= symbol <= 7) scanned.
Proof.
  induction scanned as [|symbol rest IH]; simpl.
  - split; intro H; constructor.
  - split; intro H.
    + inversion H as [|? ? Hhead Htail]; subst.
      constructor.
      * exact (proj1 (q19_restored_cell_safe_iff symbol) Hhead).
      * exact (proj1 IH Htail).
    + inversion H as [|? ? Hhead Htail]; subst.
      constructor.
      * exact (proj2 (q19_restored_cell_safe_iff symbol) Hhead).
      * exact (proj2 IH Htail).
Qed.

Corollary q19_restoration_two_blocks_full_scan :
  forall scanned,
    In 2 scanned ->
    ~ Forall q15_pass (map q16_restore scanned).
Proof.
  intros scanned Hin Hscan.
  pose proof (proj1 (q19_restored_scan_safe_iff scanned) Hscan)
    as Hsafe.
  rewrite Forall_forall in Hsafe.
  specialize (Hsafe 2 Hin).
  lia.
Qed.

Corollary q19_restoration_three_blocks_full_scan :
  forall scanned,
    In 3 scanned ->
    ~ Forall q15_pass (map q16_restore scanned).
Proof.
  intros scanned Hin Hscan.
  pose proof (proj1 (q19_restored_scan_safe_iff scanned) Hscan)
    as Hsafe.
  rewrite Forall_forall in Hsafe.
  specialize (Hsafe 3 Hin).
  lia.
Qed.

(** The old relocation premise is equivalent to two checkable
    properties: the direction-side cells pass q19, and every cell
    restored by q16 was originally one of 4,5,6,7.  This equivalence
    makes the necessary invariant explicit at the q15->q5 boundary. *)
Theorem q19_right_prefix_safe_iff :
  forall direction scanned,
    Forall q15_pass
      (direction ++ 7 :: map q16_restore scanned) <->
    (Forall q15_pass direction /\
     Forall (fun symbol => 4 <= symbol <= 7) scanned).
Proof.
  intros direction scanned.
  rewrite Forall_app.
  split.
  - intros [Hdirection Htail].
    split; [exact Hdirection |].
    apply (proj1 (q19_restored_scan_safe_iff scanned)).
    inversion Htail as [|? ? _ Hrestored]; subst.
    exact Hrestored.
  - intros [Hdirection Hsafe].
    split; [exact Hdirection |].
    constructor.
    + unfold q15_pass.
      right; right; right; right; right; reflexivity.
    + exact (proj2 (q19_restored_scan_safe_iff scanned) Hsafe).
Qed.

(** A usable source-encoding obligation for the rightward case:
    instead of assuming an opaque q19 scan across the restored region,
    impose the explicit 4..7 constraint and direction-side scan.
    The table, transition counts, and output zipper are unchanged. *)
Theorem q15_q22_right_relocates_with_safe_encoding :
  forall s remaining dir_head dir_remaining
         old next outer between final,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall (fun symbol => 4 <= symbol <= 7)
      (rev (s :: remaining)) ->
    Forall q17_pass between ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining) +
         (S (length
           (rev (dir_head :: dir_remaining) ++
            7 :: map q16_restore (rev (s :: remaining)))) +
          S (length between)))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (s :: remaining) ++
         source_bit next :: between ++ 7 :: final)) =
    cfg_ml 5
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++
            7 :: map q16_restore (rev (s :: remaining))) ++
       source_bit old :: outer)
      ((if next then 3 else 2) :: final).
Proof.
  intros s remaining dir_head dir_remaining
    old next outer between final
    H15 H16 H21 Hdirection Hsafe Hbetween.
  apply (q15_q22_right_relocates_to_q5
    s remaining dir_head dir_remaining old next outer between final
    H15 H16 H21).
  - apply (proj2 (q19_right_prefix_safe_iff
        (rev (dir_head :: dir_remaining))
        (rev (s :: remaining)))).
    split; assumption.
  - exact Hbetween.
Qed.

(** The obstruction is not peculiar to a hand-picked collision example.
    Every encoded source row, even at state width zero, contains a raw
    READ bit.  The q5 marking map changes that bit to 2 or 3; q16
    subsequently restores it to 0 or 1.  Hence the old q19 full-scan
    premise is IMPOSSIBLE if that scan crosses an entire marked source
    row.  This is a conditional obstruction to the naive macro layout,
    not a theorem that the frozen 23x8 machine is nonuniversal. *)

Lemma wide_row_contains_read_bit :
  forall row,
    In (source_bit (wr_read row)) (encode_wide_row row).
Proof.
  intros row.
  unfold encode_wide_row; simpl.
  right.
  apply in_or_app. right.
  simpl. left. reflexivity.
Qed.

Lemma marked_wide_row_not_right_scan_safe :
  forall row suffix,
    ~ Forall (fun symbol => 4 <= symbol <= 7)
      (map entry_rewrite (encode_wide_row row ++ suffix)).
Proof.
  intros row suffix Hsafe.
  rewrite Forall_forall in Hsafe.
  assert (Hin : In (entry_rewrite (source_bit (wr_read row)))
     (map entry_rewrite (encode_wide_row row ++ suffix))).
  {
    apply in_map.
    apply in_or_app. left.
    apply wide_row_contains_read_bit.
  }
  specialize (Hsafe _ Hin).
  destruct (wr_read row); simpl in Hsafe; lia.
Qed.

Theorem marked_wide_program_blocks_q19_full_right_scan :
  forall row rows suffix direction,
    ~ Forall q15_pass
      (direction ++ 7 :: map q16_restore
        (map entry_rewrite
          (encode_wide_program (row :: rows) ++ suffix))).
Proof.
  intros row rows suffix direction Hfull.
  apply (proj1 (q19_right_prefix_safe_iff direction
    (map entry_rewrite
      (encode_wide_program (row :: rows) ++ suffix)))) in Hfull.
  destruct Hfull as [_ Hrestored].
  rewrite encode_wide_program_cons in Hrestored.
  rewrite <- app_assoc in Hrestored.
  exact (marked_wide_row_not_right_scan_safe row
    (encode_wide_program rows ++ suffix) Hrestored).
Qed.

Print Assumptions q19_right_prefix_safe_iff.
Print Assumptions q15_q22_right_relocates_with_safe_encoding.
Print Assumptions marked_wide_program_blocks_q19_full_right_scan.

Print Assumptions q19_restored_scan_safe_iff.
Print Assumptions q19_restoration_two_blocks_full_scan.
Print Assumptions q19_restoration_three_blocks_full_scan.

(** The q16 return is not an opaque encoding operation.  On every
    well-formed source-description symbol it exactly undoes the earlier
    q5 mark.  The statement applies to programs of arbitrary length and
    arbitrary state-bit width, independently of any later source macro. *)
Lemma q16_restores_source_scan :
  forall scanned,
    Forall entry_scan_symbol scanned ->
    map q16_restore (map entry_rewrite scanned) = scanned.
Proof.
  intros scanned Hscan.
  induction Hscan as [|s scanned Hs _ IH].
  - reflexivity.
  - simpl.
    destruct Hs as [-> | [-> | ->]]; simpl; now rewrite IH.
Qed.

Lemma q16_restores_wide_program :
  forall rows,
    map q16_restore
      (map entry_rewrite (encode_wide_program rows)) =
    encode_wide_program rows.
Proof.
  intros rows.
  apply q16_restores_source_scan.
  apply wide_program_scannable.
Qed.

(** Every encoded row starts with X=4 followed by a genuine binary
    symbol.  With nonempty state bits this is the first state bit;
    with width zero it is the read bit.  Either way, q19 cannot cross
    that symbol as though it were a safe 2..7 scan cell. *)
Definition wide_first_payload_bit (row : WideSourceRow) : bool :=
  match wr_current row with
  | [] => wr_read row
  | bit :: _ => bit
  end.

Definition wide_after_first_payload (row : WideSourceRow) : list nat :=
  match wr_current row with
  | [] => map source_bit (wr_next row) ++
      [source_bit (wr_write row); source_bit (wr_right row)]
  | _ :: rest => map source_bit rest ++
      source_bit (wr_read row) :: map source_bit (wr_next row) ++
      [source_bit (wr_write row); source_bit (wr_right row)]
  end.

Lemma wide_row_first_binary_layout :
  forall row,
    encode_wide_row row =
      4 :: source_bit (wide_first_payload_bit row) ::
      wide_after_first_payload row.
Proof.
  intros [current scanned next written direction].
  destruct current as [|head rest]; reflexivity.
Qed.

(** Constructive first-hit result for the literal q19 transition table.
    On a restored nonempty description, q19 crosses only the safe
    direction prefix, 7, and X=4 before marking the FIRST source bit
    as M=6.  The complete remainder is preserved exactly.  No rightward
    whole-program scan premise, source-step hypothesis, or finite-width
    bound is assumed. *)
Theorem q19_wide_program_first_restored_bit :
  forall row rows direction left suffix,
    Forall q15_pass direction ->
    run (S (length (direction ++ [7; 4])))
      (entry_config 19 left
        (direction ++ [7] ++
         map q16_restore
           (map entry_rewrite (encode_wide_program (row :: rows))) ++
         suffix)) =
    entry_config (if wide_first_payload_bit row then 18 else 17)
      (6 :: rev (direction ++ [7; 4]) ++ left)
      (wide_after_first_payload row ++
       encode_wide_program rows ++ suffix).
Proof.
  intros row rows direction left suffix Hdirection.
  rewrite q16_restores_wide_program.
  rewrite encode_wide_program_cons.
  rewrite wide_row_first_binary_layout.
  match goal with
  | |- run _ (entry_config 19 _ ?tape) = _ =>
    replace tape with
      ((direction ++ [7; 4]) ++
       source_bit (wide_first_payload_bit row) ::
       (wide_after_first_payload row ++
        encode_wide_program rows ++ suffix))
  end.
  2:{
    clear Hdirection.
    induction direction as [|d direction IH]; simpl.
    - repeat rewrite app_assoc. reflexivity.
    - now rewrite IH.
  }
  apply q19_scan_to_m.
  rewrite Forall_app.
  split.
  - exact Hdirection.
  - constructor.
    + unfold q15_pass. right; right; right; right; right; reflexivity.
    + constructor.
      * unfold q15_pass. right; right; left; reflexivity.
      * constructor.
Qed.

(** Compose the preceding first-hit result with the *actual* q15--q22
    direction decision.  The strengthened marked-description premise
    identifies the complete q15 scan region with a q5-marked encoded
    program.  This is the exact native outcome when q19 is asked to
    relocate through that region: it marks the first program payload
    bit, not the later source-data bit.  The theorem does not assume an
    abstract source step and does not claim an invariant is preserved. *)
Theorem q15_q22_right_wide_program_first_hit :
  forall s remaining dir_head dir_remaining old next outer
         row rows suffix,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    rev (s :: remaining) =
      map entry_rewrite (encode_wide_program (row :: rows)) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining) +
         S (length (rev (dir_head :: dir_remaining) ++ [7; 4])))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (s :: remaining) ++ source_bit next :: suffix)) =
    entry_config (if wide_first_payload_bit row then 18 else 17)
      (6 :: rev (rev (dir_head :: dir_remaining) ++ [7; 4]) ++
       source_bit old :: outer)
      (wide_after_first_payload row ++
       encode_wide_program rows ++ source_bit next :: suffix).
Proof.
  intros s remaining dir_head dir_remaining old next outer
    row rows suffix H15 H16 H21 Hmarked Hdirection.
  rewrite writeback_run_add.
  rewrite (q15_q22_right_to_q19
    s remaining dir_head dir_remaining old next outer
    suffix H15 H16 H21).
  rewrite Hmarked.
  change
    (run (S (length (rev (dir_head :: dir_remaining) ++ [7; 4])))
       (entry_config 19 (source_bit old :: outer)
         (rev (dir_head :: dir_remaining) ++ [7] ++
          map q16_restore
            (map entry_rewrite (encode_wide_program (row :: rows))) ++
          (source_bit next :: suffix))) =
     entry_config (if wide_first_payload_bit row then 18 else 17)
       (6 :: rev (rev (dir_head :: dir_remaining) ++ [7; 4]) ++
        source_bit old :: outer)
       (wide_after_first_payload row ++
        encode_wide_program rows ++ source_bit next :: suffix)).
  apply q19_wide_program_first_restored_bit.
  exact Hdirection.
Qed.

(** The marked-program premise above is constructive, not an impossible
    side condition.  Every nonempty encoded wide program admits an
    oriented q15 tape satisfying both the forward q15 and reverse q16
    scan restrictions. *)
Lemma q15_marked_source_scan :
  forall symbols,
    Forall entry_scan_symbol symbols ->
    Forall q15_pass (map entry_rewrite symbols).
Proof.
  intros symbols Hscan.
  induction Hscan as [|s rest Hs _ IH]; simpl.
  - constructor.
  - constructor.
    + destruct Hs as [-> | [-> | ->]]; unfold q15_pass;
        simpl; [left | right; left | right; right; left]; reflexivity.
    + exact IH.
Qed.

Lemma q16_marked_source_scan_reverse :
  forall symbols,
    Forall entry_scan_symbol symbols ->
    Forall q16_pass (rev (map entry_rewrite symbols)).
Proof.
  intros symbols Hscan.
  induction Hscan as [|s rest Hs _ IH]; simpl.
  - constructor.
  - rewrite Forall_app.
    split.
    + exact IH.
    + constructor.
      * destruct Hs as [-> | [-> | ->]]; unfold q16_pass;
          simpl; [left | right; left | right; right; left]; reflexivity.
      * constructor.
Qed.

Lemma marked_wide_program_nonempty :
  forall row rows,
    map entry_rewrite (encode_wide_program (row :: rows)) <> [].
Proof.
  intros [current scanned next written direction] rows.
  unfold encode_wide_program, encode_wide_row; simpl.
  discriminate.
Qed.

Theorem marked_wide_program_q15_entry_exists :
  forall row rows,
    exists s remaining,
      rev (s :: remaining) =
        map entry_rewrite (encode_wide_program (row :: rows)) /\
      Forall q15_pass (rev (s :: remaining)) /\
      Forall q16_pass (s :: remaining).
Proof.
  intros row rows.
  destruct (rev (map entry_rewrite
    (encode_wide_program (row :: rows))))
    as [|s remaining] eqn:Hrev.
  - exfalso.
    apply (marked_wide_program_nonempty row rows).
    rewrite <- (rev_involutive
      (map entry_rewrite (encode_wide_program (row :: rows)))).
    now rewrite Hrev.
  - exists s, remaining.
    assert (Hlayout : rev (s :: remaining) =
      map entry_rewrite (encode_wide_program (row :: rows))).
    {
      rewrite <- (rev_involutive
        (map entry_rewrite (encode_wide_program (row :: rows)))).
      now rewrite Hrev.
    }
    split; [exact Hlayout |].
    split.
    + rewrite Hlayout.
      apply q15_marked_source_scan.
      apply wide_program_scannable.
    + rewrite <- Hrev.
      apply q16_marked_source_scan_reverse.
      apply wide_program_scannable.
Qed.

(** An explicit nonvacuous native execution for EVERY nonempty wide
    description.  The 4 direction-side cell satisfies both the q21
    decision scan and the q19 relocation prefix.  The q15 entry zipper
    is constructed from the fully marked program; no arbitrary bound on
    state width or row count is introduced.  It is still an entry-phase
    execution certificate rather than source-step equivalence. *)
Theorem q15_q22_right_first_hit_constructive :
  forall row rows old next outer suffix,
    exists s remaining,
      run (direction_phase_cost (s :: remaining) [4] +
           S (length ([4] ++ [7; 4])))
        (entry_config 15 (source_bit old :: 4 :: 3 :: outer)
          (rev (s :: remaining) ++ source_bit next :: suffix)) =
      entry_config (if wide_first_payload_bit row then 18 else 17)
        (6 :: rev ([4; 7; 4]) ++ source_bit old :: outer)
        (wide_after_first_payload row ++
         encode_wide_program rows ++ source_bit next :: suffix).
Proof.
  intros row rows old next outer suffix.
  destruct (marked_wide_program_q15_entry_exists row rows)
    as [s [remaining [Hmarked [H15 H16]]]].
  exists s, remaining.
  apply (q15_q22_right_wide_program_first_hit
    s remaining 4 [] old next outer row rows suffix).
  - exact H15.
  - exact H16.
  - constructor.
    + unfold q21_pass. right; right; left; reflexivity.
    + constructor.
  - exact Hmarked.
  - simpl. constructor.
    + unfold q15_pass. right; right; left; reflexivity.
    + constructor.
Qed.

(** Every byte remaining after the first encoded payload bit is an
    ordinary 0/1 data bit or X=4.  These are all passable by q17/q18;
    the next 7 marker, not any description byte, terminates the return
    scan.  This fact is uniform in state width and program length. *)
Lemma q17_source_bit_pass :
  forall bit, q17_pass (source_bit bit).
Proof.
  intros []; unfold q17_pass, source_bit; simpl.
  - right; left; reflexivity.
  - left; reflexivity.
Qed.

Lemma q17_source_bits_pass :
  forall bits, Forall q17_pass (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply q17_source_bit_pass | exact IH].
Qed.

Lemma q17_wide_after_first_payload_pass :
  forall row, Forall q17_pass (wide_after_first_payload row).
Proof.
  intros [current scanned next written direction].
  destruct current as [|head remaining]; simpl.
  - induction next as [|bit rest IH]; simpl.
    + constructor; [apply q17_source_bit_pass |].
      constructor; [apply q17_source_bit_pass | constructor].
    + constructor; [apply q17_source_bit_pass | exact IH].
  - induction remaining as [|bit rest IH]; simpl.
    + constructor; [apply q17_source_bit_pass |].
      induction next as [|b tail IHnext]; simpl.
      * constructor; [apply q17_source_bit_pass |].
        constructor; [apply q17_source_bit_pass | constructor].
      * constructor; [apply q17_source_bit_pass | exact IHnext].
    + constructor; [apply q17_source_bit_pass | exact IH].
Qed.

Lemma q17_entry_source_symbol_pass :
  forall symbol,
    entry_scan_symbol symbol -> q17_pass symbol.
Proof.
  intros symbol [-> | [-> | ->]]; unfold q17_pass.
  - left; reflexivity.
  - right; left; reflexivity.
  - right; right; right; right; left; reflexivity.
Qed.

Lemma q17_wide_program_pass :
  forall rows, Forall q17_pass (encode_wide_program rows).
Proof.
  intros rows.
  pose proof (wide_program_scannable rows) as Hscan.
  rewrite Forall_forall in Hscan.
  apply Forall_forall.
  intros symbol Hin.
  apply q17_entry_source_symbol_pass.
  exact (Hscan symbol Hin).
Qed.

Lemma q17_wide_return_scan_pass :
  forall row rows next,
    Forall q17_pass
      (wide_after_first_payload row ++
       encode_wide_program rows ++ [source_bit next]).
Proof.
  intros row rows next.
  repeat rewrite Forall_app.
  repeat split.
  - apply q17_wide_after_first_payload_pass.
  - apply q17_wide_program_pass.
  - constructor; [apply q17_source_bit_pass | constructor].
Qed.

(** The FULL native collision cycle from q15 back to q5.  We construct
    a nonempty marked program with a safe direction marker, follow the
    actual q15/q16/q21/q22/q19 transitions to the FIRST restored source
    bit, then follow q17/q18 across the remaining description and the
    next raw data cell to the first 7.  The resulting displaced M=6 and
    the new 2/3 marker are described exactly; this is *not* the desired
    source-machine head transition in general, and does not certify
    a universal source-step macro. *)
Theorem q15_q22_right_collision_returns_q5 :
  forall row rows old next outer final,
    exists s remaining,
      run ((direction_phase_cost (s :: remaining) [4] +
            S (length ([4; 7; 4]))) +
           S (length
             (wide_after_first_payload row ++
              encode_wide_program rows ++ [source_bit next])))
        (entry_config 15 (source_bit old :: 4 :: 3 :: outer)
          (rev (s :: remaining) ++ source_bit next :: 7 :: final)) =
      cfg_ml 5
        (rev (wide_after_first_payload row ++
              encode_wide_program rows ++ [source_bit next]) ++
         6 :: rev [4; 7; 4] ++ source_bit old :: outer)
        ((if wide_first_payload_bit row then 3 else 2) :: final).
Proof.
  intros row rows old next outer final.
  destruct (q15_q22_right_first_hit_constructive
    row rows old next outer (7 :: final))
    as [s [remaining Hfirst]].
  exists s, remaining.
  rewrite writeback_run_add.
  replace (S (length [4; 7; 4]))
    with (S (length ([4] ++ [7; 4]))) by reflexivity.
  rewrite Hfirst.
  assert (Htail :
    wide_after_first_payload row ++ encode_wide_program rows ++
      source_bit next :: 7 :: final =
    (wide_after_first_payload row ++ encode_wide_program rows ++
      [source_bit next]) ++ 7 :: final).
  { repeat rewrite <- app_assoc; simpl; reflexivity. }
  rewrite Htail.
  change
    (run (S (length (wide_after_first_payload row ++
                    encode_wide_program rows ++ [source_bit next])))
       (entry_config (if wide_first_payload_bit row then 18 else 17)
         (6 :: rev [4; 7; 4] ++ source_bit old :: outer)
         ((wide_after_first_payload row ++
           encode_wide_program rows ++ [source_bit next]) ++
          7 :: final)) =
     cfg_ml 5
       (rev (wide_after_first_payload row ++
             encode_wide_program rows ++ [source_bit next]) ++
        6 :: rev [4; 7; 4] ++ source_bit old :: outer)
       ((if wide_first_payload_bit row then 3 else 2) :: final)).
  destruct (wide_first_payload_bit row); simpl.
  - apply q18_scan_to_marker.
    apply q17_wide_return_scan_pass.
  - apply q17_scan_to_marker.
    apply q17_wide_return_scan_pass.
Qed.

(** Reachable cursor bridge, with no synthetic q15 left-hand prefix.
    The q12/q13-to-q15 theorems produce q15 with X=4 immediately to
    the left. Following that very configuration across an arbitrary
    safe right scan reaches q16.  This gives a genuine composition of
    q12/q13 -> q14 -> q15 -> q16, but does not yet prove a complete
    encoded-source instruction transition or the later q21/q22 branch. *)
Theorem q12_to_q16_reached_cursor :
  forall remaining s skipped prefix scanned next suffix,
    Forall q12_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    run ((S (length (s :: remaining)) +
          S (length (rev (s :: remaining) ++ skipped))) +
         S (length scanned))
      (entry_config 12 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 ::
         (scanned ++ source_bit next :: suffix))) =
    cfg_ml 16
      (rev scanned ++ 4 ::
       map q14_restore (rev (rev (s :: remaining) ++ skipped)) ++
       3 :: prefix)
      (source_bit next :: suffix).
Proof.
  intros remaining s skipped prefix scanned next suffix
    H12 H14 H15.
  rewrite writeback_run_add.
  rewrite (q12_to_q15_direction_cycle
    remaining s skipped prefix
    (scanned ++ source_bit next :: suffix) H12 H14).
  apply q15_scan_to_raw.
  exact H15.
Qed.

Theorem q13_to_q16_reached_cursor :
  forall remaining s skipped prefix scanned next suffix,
    Forall q13_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    run ((S (length (s :: remaining)) +
          S (length (rev (s :: remaining) ++ skipped))) +
         S (length scanned))
      (entry_config 13 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 ::
         (scanned ++ source_bit next :: suffix))) =
    cfg_ml 16
      (rev scanned ++ 4 ::
       map q14_restore (rev (rev (s :: remaining) ++ skipped)) ++
       2 :: prefix)
      (source_bit next :: suffix).
Proof.
  intros remaining s skipped prefix scanned next suffix
    H13 H14 H15.
  rewrite writeback_run_add.
  rewrite (q13_to_q15_direction_cycle
    remaining s skipped prefix
    (scanned ++ source_bit next :: suffix) H13 H14).
  apply q15_scan_to_raw.
  exact H15.
Qed.

(** The cursor produced by q15 has already moved left once.  A nonempty
    backscan therefore needs one step per cell PLUS the transition at the
    first raw bit.  The q21/q22 scan likewise includes its direction-mark
    transition.  Both bounds below count those boundary transitions. *)
Theorem q16_framed_cursor_to_q19 :
  forall backscan dir_head dir_remaining old outer tail,
    backscan <> [] ->
    Forall q16_pass backscan ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length backscan) + S (length (dir_head :: dir_remaining)))
      (cfg_ml 16
        (backscan ++ source_bit old ::
         dir_head :: dir_remaining ++ 3 :: outer) tail) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++ 7 ::
       map q16_restore (rev backscan) ++ tail).
Proof.
  intros [|head rest] dir_head dir_remaining old outer tail
    Hnonempty Hback Hdir.
  - contradiction.
  - match goal with
    | |- _ = ?expected =>
      change
        (run (S (length (head :: rest)) +
              S (length (dir_head :: dir_remaining)))
          (entry_config 16
            (rest ++ source_bit old ::
             dir_head :: dir_remaining ++ 3 :: outer)
            (head :: tail)) = expected)
    end.
    rewrite writeback_run_add.
    rewrite (q16_restore_to_raw rest head old
      (dir_head :: dir_remaining ++ 3 :: outer) tail Hback).
    match goal with
    | |- _ = ?expected =>
      change
        (run (S (length (dir_head :: dir_remaining)))
          (entry_config (if old then 22 else 21)
            (dir_remaining ++ 3 :: outer)
            (dir_head :: 7 ::
             map q16_restore (rev (head :: rest)) ++ tail)) = expected)
    end.
    assert (Hq : (if old then 22 else 21) = 21 \/
                 (if old then 22 else 21) = 22).
    { destruct old; simpl; auto. }
    rewrite (q21_scan_to_right_direction dir_remaining dir_head
      (if old then 22 else 21) outer
      (7 :: map q16_restore (rev (head :: rest)) ++ tail) Hq Hdir).
    destruct old; reflexivity.
Qed.

Theorem q16_framed_cursor_to_q20 :
  forall backscan dir_head dir_remaining old outer tail,
    backscan <> [] ->
    Forall q16_pass backscan ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length backscan) + S (length (dir_head :: dir_remaining)))
      (cfg_ml 16
        (backscan ++ source_bit old ::
         dir_head :: dir_remaining ++ 2 :: outer) tail) =
    cfg_ml 20 outer
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev backscan) ++ tail).
Proof.
  intros [|head rest] dir_head dir_remaining old outer tail
    Hnonempty Hback Hdir.
  - contradiction.
  - match goal with
    | |- _ = ?expected =>
      change
        (run (S (length (head :: rest)) +
              S (length (dir_head :: dir_remaining)))
          (entry_config 16
            (rest ++ source_bit old ::
             dir_head :: dir_remaining ++ 2 :: outer)
            (head :: tail)) = expected)
    end.
    rewrite writeback_run_add.
    rewrite (q16_restore_to_raw rest head old
      (dir_head :: dir_remaining ++ 2 :: outer) tail Hback).
    match goal with
    | |- _ = ?expected =>
      change
        (run (S (length (dir_head :: dir_remaining)))
          (entry_config (if old then 22 else 21)
            (dir_remaining ++ 2 :: outer)
            (dir_head :: 7 ::
             map q16_restore (rev (head :: rest)) ++ tail)) = expected)
    end.
    assert (Hq : (if old then 22 else 21) = 21 \/
                 (if old then 22 else 21) = 22).
    { destruct old; simpl; auto. }
    rewrite (q21_scan_to_left_direction dir_remaining dir_head
      (if old then 22 else 21) outer
      (7 :: map q16_restore (rev (head :: rest)) ++ tail) Hq Hdir).
    destruct old; reflexivity.
Qed.

(** These two theorems use the precise q14-restored tape created by
    q12/q13.  The layout equation identifies the *first* raw bit seen
    by q16; it is an encoding obligation, not a claim that every wide
    source program satisfies this layout.  No q15 left prefix is invented. *)
Definition reached_direction_cost
    (action skipped scanned backscan direction : list nat) : nat :=
  ((S (length action) + S (length (rev action ++ skipped))) +
    S (length scanned)) +
  (S (length backscan) + S (length direction)).

Theorem q12_to_q19_reached_direction :
  forall remaining s skipped prefix scanned next suffix
         before old dir_head dir_remaining,
    Forall q12_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    map q14_restore (rev (rev (s :: remaining) ++ skipped)) =
      before ++ source_bit old :: dir_head :: dir_remaining ->
    Forall q16_pass (rev scanned ++ 4 :: before) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (reached_direction_cost (s :: remaining) skipped scanned
           (rev scanned ++ 4 :: before) (dir_head :: dir_remaining))
      (entry_config 12 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 :: (scanned ++ source_bit next :: suffix))) =
    entry_config 19 (source_bit old :: prefix)
      (rev (dir_head :: dir_remaining) ++ 7 ::
       map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix).
Proof.
  intros remaining s skipped prefix scanned next suffix before
    old dir_head dir_remaining H12 H14 H15 Hlayout H16 Hdir.
  unfold reached_direction_cost.
  rewrite writeback_run_add.
  rewrite (q12_to_q16_reached_cursor remaining s skipped prefix
    scanned next suffix H12 H14 H15).
  replace
    (rev scanned ++ 4 ::
     map q14_restore (rev (rev (s :: remaining) ++ skipped)) ++
     3 :: prefix)
    with ((rev scanned ++ 4 :: before) ++
          source_bit old :: dir_head :: dir_remaining ++ 3 :: prefix).
  2:{
    rewrite Hlayout.
    clear H16.
    remember (rev scanned) as backwards eqn:Heq.
    clear Heq.
    induction backwards as [|symbol backwards IHback]; simpl.
    - repeat rewrite <- app_assoc. reflexivity.
    - rewrite IHback.
      repeat rewrite <- app_assoc.
      reflexivity.
  }
  apply q16_framed_cursor_to_q19.
  - destruct (rev scanned); discriminate.
  - exact H16.
  - exact Hdir.
Qed.

Theorem q13_to_q20_reached_direction :
  forall remaining s skipped prefix scanned next suffix
         before old dir_head dir_remaining,
    Forall q13_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    map q14_restore (rev (rev (s :: remaining) ++ skipped)) =
      before ++ source_bit old :: dir_head :: dir_remaining ->
    Forall q16_pass (rev scanned ++ 4 :: before) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (reached_direction_cost (s :: remaining) skipped scanned
           (rev scanned ++ 4 :: before) (dir_head :: dir_remaining))
      (entry_config 13 (remaining ++ 6 :: prefix)
        (s :: skipped ++ 4 :: (scanned ++ source_bit next :: suffix))) =
    cfg_ml 20 prefix
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix).
Proof.
  intros remaining s skipped prefix scanned next suffix before
    old dir_head dir_remaining H13 H14 H15 Hlayout H16 Hdir.
  unfold reached_direction_cost.
  rewrite writeback_run_add.
  rewrite (q13_to_q16_reached_cursor remaining s skipped prefix
    scanned next suffix H13 H14 H15).
  replace
    (rev scanned ++ 4 ::
     map q14_restore (rev (rev (s :: remaining) ++ skipped)) ++
     2 :: prefix)
    with ((rev scanned ++ 4 :: before) ++
          source_bit old :: dir_head :: dir_remaining ++ 2 :: prefix).
  2:{
    rewrite Hlayout.
    clear H16.
    remember (rev scanned) as backwards eqn:Heq.
    clear Heq.
    induction backwards as [|symbol backwards IHback]; simpl.
    - repeat rewrite <- app_assoc. reflexivity.
    - rewrite IHback.
      repeat rewrite <- app_assoc.
      reflexivity.
  }
  apply q16_framed_cursor_to_q20.
  - destruct (rev scanned); discriminate.
  - exact H16.
  - exact Hdir.
Qed.

(** The actual q13 entry now reaches the end of the LEFT movement macro.
    The left neighbour must be a raw source bit, and the cells between
    that bit and q16's marker must be safe for q17/q18.  Both requirements
    are explicit here; no claim is made that a complete source encoding
    automatically satisfies them. *)
Theorem q13_reached_left_relocates_to_q5 :
  forall remaining s skipped outer scanned next suffix
         before old dir_head dir_remaining target,
    Forall q13_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    map q14_restore (rev (rev (s :: remaining) ++ skipped)) =
      before ++ source_bit old :: dir_head :: dir_remaining ->
    Forall q16_pass (rev scanned ++ 4 :: before) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass (rev (dir_head :: dir_remaining)) ->
    run (reached_direction_cost (s :: remaining) skipped scanned
           (rev scanned ++ 4 :: before) (dir_head :: dir_remaining) +
         (1 + S (length
           (source_bit old :: rev (dir_head :: dir_remaining)))))
      (entry_config 13 (remaining ++ 6 :: source_bit target :: outer)
        (s :: skipped ++ 4 ::
         (scanned ++ source_bit next :: suffix))) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix).
Proof.
  intros remaining s skipped outer scanned next suffix
    before old dir_head dir_remaining target
    H13 H14 H15 Hlayout H16 Hdir Hreturn.
  assert (Hreturn' :
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining))).
  {
    constructor.
    - destruct old; unfold q17_pass, source_bit; simpl;
        [right; left; reflexivity | left; reflexivity].
    - exact Hreturn.
  }
  rewrite writeback_run_add.
  rewrite (q13_to_q20_reached_direction
    remaining s skipped (source_bit target :: outer) scanned next
    suffix before old dir_head dir_remaining
    H13 H14 H15 Hlayout H16 Hdir).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix))) = expected)
  end.
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (rev scanned ++ 4 :: before)) ++
     source_bit next :: suffix)).
  destruct target.
  - exact (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix) Hreturn').
  - exact (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (rev scanned ++ 4 :: before)) ++
       source_bit next :: suffix) Hreturn').
Qed.

Print Assumptions q13_reached_left_relocates_to_q5.

(** Right relocation must use the FIRST raw bit exposed by q16.
    The split of the restored scan is exact, so q19 cannot silently
    pass an earlier 0/1 and relocate a later source-data bit.  The
    stated q15/q17 safety conditions are the additional obligations
    needed to complete the native return to q5. *)
Theorem q12_reached_right_first_hit_returns_q5 :
  forall remaining s skipped outer scanned next between final
         before old dir_head dir_remaining before_hit hit after_hit,
    Forall q12_pass (s :: remaining) ->
    Forall q14_pass (rev (s :: remaining) ++ skipped) ->
    Forall q15_pass scanned ->
    map q14_restore (rev (rev (s :: remaining) ++ skipped)) =
      before ++ source_bit old :: dir_head :: dir_remaining ->
    Forall q16_pass (rev scanned ++ 4 :: before) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    map q16_restore (rev (rev scanned ++ 4 :: before)) =
      before_hit ++ source_bit hit :: after_hit ->
    Forall q15_pass
      (rev (dir_head :: dir_remaining) ++ 7 :: before_hit) ->
    Forall q17_pass (after_hit ++ source_bit next :: between) ->
    run (reached_direction_cost (s :: remaining) skipped scanned
           (rev scanned ++ 4 :: before) (dir_head :: dir_remaining) +
         (S (length
           (rev (dir_head :: dir_remaining) ++ 7 :: before_hit)) +
          S (length (after_hit ++ source_bit next :: between))))
      (entry_config 12 (remaining ++ 6 :: outer)
        (s :: skipped ++ 4 ::
         (scanned ++ source_bit next :: between ++ 7 :: final))) =
    cfg_ml 5
      (rev (after_hit ++ source_bit next :: between) ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: before_hit) ++
       source_bit old :: outer)
      ((if hit then 3 else 2) :: final).
Proof.
  intros remaining s skipped outer scanned next between final
    before old dir_head dir_remaining before_hit hit after_hit
    H12 H14 H15 Hlayout H16 Hdir Hfirst Hsafe Hreturn.
  rewrite writeback_run_add.
  rewrite (q12_to_q19_reached_direction
    remaining s skipped outer scanned next (between ++ 7 :: final)
    before old dir_head dir_remaining
    H12 H14 H15 Hlayout H16 Hdir).
  rewrite Hfirst.
  replace
    (rev (dir_head :: dir_remaining) ++
     7 :: (before_hit ++ source_bit hit :: after_hit) ++
     source_bit next :: between ++ 7 :: final)
    with
    ((rev (dir_head :: dir_remaining) ++ 7 :: before_hit) ++
     source_bit hit ::
       (after_hit ++ source_bit next :: between) ++ 7 :: final).
  2:{ repeat rewrite <- app_assoc; cbn [app].
      repeat rewrite <- app_assoc; cbn [app]. reflexivity. }
  rewrite (q19_to_q5_relocation
    (rev (dir_head :: dir_remaining) ++ 7 :: before_hit)
    (after_hit ++ source_bit next :: between)
    hit (source_bit old :: outer) final Hsafe Hreturn).
  reflexivity.
Qed.

(** Constructive witness: the return marks the earlier q16-restored 0,
    rather than the later raw source-data 0. *)
Example q12_right_first_hit_nineteen_steps :
  run 19 (entry_config 12 [5; 6] [0; 4; 2; 0; 7]) =
  cfg_ml 5 [0; 6; 4; 7; 5; 0] [2].
Proof. reflexivity. Qed.

(** A fully CONSTRUCTED q12 entry containing an arbitrarily long marked
    wide-program description.  All scan conditions are discharged from
    the source encoding rather than assumed.  The actual table moves from
    q12 through q14/q15/q16/q21/q19 and back to q5, but picks the FIRST
    restored source-program payload bit.  This is a native counterexample
    to treating the rightward full-description traversal as if q19 could
    pass through restored 0/1 program data.  It is not a universality
    result and does not identify the returned marker with the intended
    neighbouring source-tape bit. *)
Theorem q12_right_marked_program_collision_at_q5 :
  forall row rows next final,
    let scanned := map entry_rewrite
      (encode_wide_program (row :: rows)) in
    let after_hit := wide_after_first_payload row ++
      encode_wide_program rows in
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length [5; 7; 4; 4]) +
          S (length (after_hit ++ [source_bit next]))))
      (entry_config 12 [5; 6]
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (rev (after_hit ++ [source_bit next]) ++ [6; 4; 4; 7; 5; 0])
      ((if wide_first_payload_bit row then 3 else 2) :: final).
Proof.
  intros row rows next final.
  set (scanned := map entry_rewrite
    (encode_wide_program (row :: rows))).
  set (after_hit := wide_after_first_payload row ++
    encode_wide_program rows).
  assert (H12 : Forall q12_pass [0; 5]).
  { repeat constructor; unfold q12_pass; lia. }
  assert (H14 : Forall q14_pass (rev [0; 5] ++ [])).
  { repeat constructor; unfold q14_pass; lia. }
  assert (H15 : Forall q15_pass scanned).
  {
    unfold scanned.
    apply q15_marked_source_scan.
    apply wide_program_scannable.
  }
  assert (Hlayout :
    map q14_restore (rev (rev [0; 5] ++ [])) =
      [] ++ source_bit false :: 5 :: []) by reflexivity.
  assert (H16 : Forall q16_pass (rev scanned ++ [4])).
  {
    rewrite Forall_app.
    split.
    - unfold scanned.
      apply q16_marked_source_scan_reverse.
      apply wide_program_scannable.
    - constructor; [unfold q16_pass; lia | constructor].
  }
  assert (Hdir : Forall q21_pass [5]).
  { constructor; [unfold q21_pass; lia | constructor]. }
  assert (Hfirst :
    map q16_restore (rev (rev scanned ++ [4])) =
    [4; 4] ++ source_bit (wide_first_payload_bit row) :: after_hit).
  {
    unfold scanned, after_hit.
    rewrite rev_app_distr.
    rewrite rev_involutive.
    change (4 :: map q16_restore scanned =
      [4; 4] ++ source_bit (wide_first_payload_bit row) :: after_hit).
    unfold scanned, after_hit.
    rewrite q16_restores_wide_program.
    rewrite encode_wide_program_cons.
    rewrite wide_row_first_binary_layout.
    simpl.
    repeat rewrite <- app_assoc.
    reflexivity.
  }
  assert (Hsafe : Forall q15_pass [5; 7; 4; 4]).
  { repeat constructor; unfold q15_pass; lia. }
  assert (Hreturn :
    Forall q17_pass (after_hit ++ [source_bit next])).
  {
    unfold after_hit.
    rewrite <- app_assoc.
    apply q17_wide_return_scan_pass.
  }
  pose proof (q12_reached_right_first_hit_returns_q5
    [5] 0 [] [] scanned next [] final
    [] false 5 [] [4; 4] (wide_first_payload_bit row) after_hit
    H12 H14 H15 Hlayout H16 Hdir Hfirst Hsafe Hreturn) as Hrun.
  cbn [rev app source_bit] in Hrun.
  exact Hrun.
Qed.

(** A source-neighbour comparison, without pretending the native q5
    marker is the source instruction's WRITE field.  The intended newly
    visited right-hand data bit is `next`, but this layout selects the
    first restored PROGRAM payload bit.  If the bits differ, the q5
    marker differs.  Both outputs are exact literal-table results. *)
Theorem q12_right_marked_program_target_mismatch :
  forall row rows next final,
    wide_first_payload_bit row <> next ->
    let scanned := map entry_rewrite
      (encode_wide_program (row :: rows)) in
    let after_hit := wide_after_first_payload row ++
      encode_wide_program rows in
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length [5; 7; 4; 4]) +
          S (length (after_hit ++ [source_bit next]))))
      (entry_config 12 [5; 6]
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (rev (after_hit ++ [source_bit next]) ++ [6; 4; 4; 7; 5; 0])
      ((if wide_first_payload_bit row then 3 else 2) :: final) /\
    (if wide_first_payload_bit row then 3 else 2) <>
      (if next then 3 else 2).
Proof.
  intros row rows next final Hdifferent.
  split.
  - apply q12_right_marked_program_collision_at_q5.
  - destruct (wide_first_payload_bit row), next;
      simpl in *; congruence.
Qed.

(** Concrete p=9 mismatch: the first state bit is zero while the
    next source-tape bit is one.  All widths are covered by the theorem. *)
Example nine_bit_right_program_neighbor_mismatch :
  wide_first_payload_bit wide_nine_bit_example <> true /\
  (if wide_first_payload_bit wide_nine_bit_example then 3 else 2) = 2.
Proof. split; [discriminate | reflexivity]. Qed.

(** Every nonempty marked program has SOME data-neighbour value for
    which the constructed q12 rightward relocation is wrong.  Take the
    Boolean complement of the first program payload bit.  This is a
    quantified obstruction to THIS placement of the program on q19's
    movement rail, not a nonuniversality theorem for the 23x8 table. *)
Theorem q12_right_marked_program_unavoidable_bad_neighbor :
  forall row rows final,
    let next := negb (wide_first_payload_bit row) in
    let scanned := map entry_rewrite
      (encode_wide_program (row :: rows)) in
    let after_hit := wide_after_first_payload row ++
      encode_wide_program rows in
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length [5; 7; 4; 4]) +
          S (length (after_hit ++ [source_bit next]))))
      (entry_config 12 [5; 6]
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (rev (after_hit ++ [source_bit next]) ++ [6; 4; 4; 7; 5; 0])
      ((if wide_first_payload_bit row then 3 else 2) :: final) /\
    (if wide_first_payload_bit row then 3 else 2) <>
      (if next then 3 else 2).
Proof.
  intros row rows final.
  apply q12_right_marked_program_target_mismatch.
  destruct (wide_first_payload_bit row); discriminate.
Qed.

Print Assumptions q12_right_marked_program_unavoidable_bad_neighbor.

Print Assumptions q12_right_marked_program_target_mismatch.

Print Assumptions q12_right_marked_program_collision_at_q5.

Print Assumptions q12_reached_right_first_hit_returns_q5.

(** Small real-table witnesses guard against vacuous framed premises. *)
Example q12_right_direction_eleven_steps :
  run 11 (entry_config 12 [0; 6] [0; 4; 0]) =
  entry_config 19 [0] [0; 7; 4; 0].
Proof. reflexivity. Qed.

Example q13_left_direction_eleven_steps :
  run 11 (entry_config 13 [0; 6; 1] [0; 4; 0]) =
  entry_config 20 [] [1; 0; 0; 7; 4; 0].
Proof. reflexivity. Qed.

Print Assumptions q12_to_q19_reached_direction.
Print Assumptions q13_to_q20_reached_direction.

Print Assumptions q16_restores_wide_program.
Print Assumptions q19_wide_program_first_restored_bit.
Print Assumptions q15_q22_right_wide_program_first_hit.
Print Assumptions q15_q22_right_first_hit_constructive.
Print Assumptions q15_q22_right_collision_returns_q5.
Print Assumptions q12_to_q16_reached_cursor.
Print Assumptions q13_to_q16_reached_cursor.

(** The preceding right-move theorem deliberately requires the entire
    restored q16 scan to be free of raw bits.  If an earlier 2 or 3 was
    restored into 0 or 1, q19 instead stops at THAT first binary cell.
    The next theorem describes this exact first-hit behavior, including
    the q17/q18 return to the next 7.  It is a positive native-table
    certificate for the collision case, not a source-step refinement. *)

Theorem q15_q22_right_hits_restored_bit :
  forall s remaining dir_head dir_remaining
         old next outer before hit after between final,
    Forall q15_pass (rev (s :: remaining)) ->
    Forall q16_pass (s :: remaining) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    map q16_restore (rev (s :: remaining)) =
      before ++ source_bit hit :: after ->
    Forall q15_pass
      (rev (dir_head :: dir_remaining) ++ 7 :: before) ->
    Forall q17_pass (after ++ source_bit next :: between) ->
    run (direction_phase_cost (s :: remaining)
           (dir_head :: dir_remaining) +
         (S (length
           (rev (dir_head :: dir_remaining) ++ 7 :: before)) +
          S (length (after ++ source_bit next :: between))))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (s :: remaining) ++
         source_bit next :: between ++ 7 :: final)) =
    cfg_ml 5
      (rev (after ++ source_bit next :: between) ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: before) ++
       source_bit old :: outer)
      ((if hit then 3 else 2) :: final).
Proof.
  intros s remaining dir_head dir_remaining
    old next outer before hit after between final
    H15 H16 H21 Hsplit Hbefore Hafter.
  rewrite writeback_run_add.
  rewrite (q15_q22_right_to_q19
    s remaining dir_head dir_remaining old next outer
    (between ++ 7 :: final) H15 H16 H21).
  rewrite Hsplit.
  replace
    (rev (dir_head :: dir_remaining) ++
     7 :: (before ++ source_bit hit :: after) ++
     source_bit next :: between ++ 7 :: final)
    with
    ((rev (dir_head :: dir_remaining) ++ 7 :: before) ++
     source_bit hit ::
       (after ++ source_bit next :: between) ++ 7 :: final).
  2:{ repeat rewrite <- app_assoc; cbn [app].
      repeat rewrite <- app_assoc; cbn [app]. reflexivity. }
  rewrite (q19_to_q5_relocation
    (rev (dir_head :: dir_remaining) ++ 7 :: before)
    (after ++ source_bit next :: between)
    hit (source_bit old :: outer) final Hbefore Hafter).
  reflexivity.
Qed.

(** A concrete collision witness: after q16 restores the 2 to raw 0,
    q19 selects that restored 0, not the later original source 0.
    The 11 steps below use only the frozen table. *)
Example restored_bit_preempts_next_raw :
  run 11 (entry_config 15 [0; 4; 3] [2; 0; 7]) =
  cfg_ml 5 [0; 6; 7; 4; 0] [2].
Proof. reflexivity. Qed.

Example restore_two_exposes_raw_zero :
  q16_restore 2 = source_bit false.
Proof. reflexivity. Qed.

Example restore_three_exposes_raw_one :
  q16_restore 3 = source_bit true.
Proof. reflexivity. Qed.

Print Assumptions q15_q22_right_hits_restored_bit.

Print Assumptions q15_q22_right_to_q19.
Print Assumptions q15_q22_left_to_q20.
Print Assumptions q15_q22_right_relocates_to_q5.
Print Assumptions q15_q22_left_relocates_to_q5.


(** The two possible right-hand data neighbours yield the SAME q5
    marker on this marked-program layout, even though their final tape
    contents differ.  This is a paired-trace noninterference result for
    the q5 marker, not a claim that the two complete tapes are equal.
    The construction quantifies over every nonempty encoded program and
    over every untouched final suffix. *)
Theorem q12_right_marked_program_paired_neighbor_traces :
  forall row rows final,
    let scanned := map entry_rewrite
      (encode_wide_program (row :: rows)) in
    let after_hit := wide_after_first_payload row ++
      encode_wide_program rows in
    (run (reached_direction_cost [0; 5] [] scanned
            (rev scanned ++ [4]) [5] +
          (S (length [5; 7; 4; 4]) +
           S (length (after_hit ++ [source_bit false]))))
       (entry_config 12 [5; 6]
         (0 :: 4 :: (scanned ++ source_bit false :: 7 :: final))) =
     cfg_ml 5
       (rev (after_hit ++ [source_bit false]) ++ [6; 4; 4; 7; 5; 0])
       ((if wide_first_payload_bit row then 3 else 2) :: final)) /\
    (run (reached_direction_cost [0; 5] [] scanned
            (rev scanned ++ [4]) [5] +
          (S (length [5; 7; 4; 4]) +
           S (length (after_hit ++ [source_bit true]))))
       (entry_config 12 [5; 6]
         (0 :: 4 :: (scanned ++ source_bit true :: 7 :: final))) =
     cfg_ml 5
       (rev (after_hit ++ [source_bit true]) ++ [6; 4; 4; 7; 5; 0])
       ((if wide_first_payload_bit row then 3 else 2) :: final)).
Proof.
  intros row rows final.
  split; apply q12_right_marked_program_collision_at_q5.
Qed.

(** Exact correctness condition for the neighbour marker.  Because the
    q5 result depends only on the first restored program payload, it can
    agree with at most one of the two possible target neighbours. *)
Theorem q12_right_marked_program_marker_correct_iff :
  forall row (next : bool),
    (if wide_first_payload_bit row then 3 else 2) =
      (if next then 3 else 2) <->
    wide_first_payload_bit row = next.
Proof.
  intros row next.
  destruct (wide_first_payload_bit row), next; simpl;
    split; intro H; try discriminate; reflexivity.
Qed.

(** Positive literal-table control for a safe q19 rail.  The single
    marked 4 restores to 4, so q19 can pass it and select the actual
    right-hand raw data neighbour.  This is a constructed q12-entry
    demonstration, NOT a complete-program source-step simulation. *)
Theorem q12_right_guarded_cell_relocates_neighbor :
  forall next final,
    run 19
      (entry_config 12 [5; 6]
        (0 :: 4 :: 4 :: source_bit next :: 7 :: final)) =
    cfg_ml 5 [6; 4; 4; 7; 5; 0]
      ((if next then 3 else 2) :: final).
Proof.
  intros [|] final; reflexivity.
Qed.

Print Assumptions q12_right_marked_program_paired_neighbor_traces.
Print Assumptions q12_right_marked_program_marker_correct_iff.
Print Assumptions q12_right_guarded_cell_relocates_neighbor.


(** A computable safety contract for a rightward q19 rail.  The Boolean
    check is independent of source-state width, scan length, and the
    neighbouring source-data bit. *)
Definition q19_guarded_railb (scanned : list nat) : bool :=
  forallb (fun symbol => Nat.leb 4 symbol && Nat.leb symbol 7) scanned.

Theorem q19_guarded_railb_spec :
  forall scanned,
    q19_guarded_railb scanned = true <->
    Forall (fun symbol => 4 <= symbol <= 7) scanned.
Proof.
  induction scanned as [|symbol rest IH]; simpl.
  - split; intro H; constructor.
  - split.
    + intro H.
      apply andb_true_iff in H.
      destruct H as [Hsymbol Hrest].
      constructor.
      * apply andb_true_iff in Hsymbol.
        destruct Hsymbol as [Hlo Hhi].
        split; apply Nat.leb_le; assumption.
      * apply (proj1 IH) in Hrest.
        exact Hrest.
    + intro H.
      inversion H as [|? ? Hsymbol Hrest]; subst.
      apply andb_true_iff.
      split.
      * apply andb_true_iff.
        destruct Hsymbol as [Hlo Hhi].
        split.
        -- apply (proj2 (Nat.leb_le 4 symbol)). exact Hlo.
        -- apply (proj2 (Nat.leb_le symbol 7)). exact Hhi.
      * apply (proj2 IH).
        exact Hrest.
Qed.

Lemma q19_guarded_rail_q15 :
  forall scanned,
    Forall (fun symbol => 4 <= symbol <= 7) scanned ->
    Forall q15_pass scanned.
Proof.
  intros scanned H.
  induction H as [|symbol rest Hsymbol Hrest IH].
  - constructor.
  - constructor.
    + unfold q15_pass; lia.
    + exact IH.
Qed.

Lemma q19_guarded_rail_rev_q16 :
  forall scanned,
    Forall (fun symbol => 4 <= symbol <= 7) scanned ->
    Forall q16_pass (rev scanned).
Proof.
  intros scanned H.
  induction H as [|symbol rest Hsymbol Hrest IH].
  - constructor.
  - simpl.
    rewrite Forall_app.
    split.
    + exact IH.
    + constructor.
      * unfold q16_pass; lia.
      * constructor.
Qed.

(** A complete and exact q12-entry RIGHT relocation theorem for
    arbitrary scan lengths.  The preconditions expose the needed
    q15 scan, reverse q16 scan and restored q19 passage separately.
    Unlike the collided wide-program layout, here the returned q5
    marker is the ACTUAL neighbouring source-data bit. *)
Theorem q12_right_guarded_scan_relocates_neighbor :
  forall scanned next final,
    Forall q15_pass scanned ->
    Forall q16_pass (rev scanned ++ [4]) ->
    Forall q15_pass
      ([5; 7] ++
       map q16_restore (rev (rev scanned ++ [4]))) ->
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length
           ([5; 7] ++
             map q16_restore (rev (rev scanned ++ [4])))) + 1))
      (entry_config 12 [5; 6]
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (6 :: rev
        ([5; 7] ++
          map q16_restore (rev (rev scanned ++ [4]))) ++ [0])
      ((if next then 3 else 2) :: final).
Proof.
  intros scanned next final Hscan Hback Hsafe.
  assert (H12 : Forall q12_pass [0; 5]).
  { repeat constructor; unfold q12_pass; lia. }
  assert (H14 : Forall q14_pass (rev [0; 5] ++ [])).
  { repeat constructor; unfold q14_pass; lia. }
  assert (Hlayout :
    map q14_restore (rev (rev [0; 5] ++ [])) =
      [] ++ source_bit false :: 5 :: []) by reflexivity.
  assert (Hdir : Forall q21_pass [5]).
  { constructor; [unfold q21_pass; lia | constructor]. }
  assert (Hreturn : Forall q17_pass []) by constructor.
  rewrite writeback_run_add.
  pose proof (q12_to_q19_reached_direction
    [5] 0 [] [] scanned next (7 :: final)
    [] false 5 [] H12 H14 Hscan Hlayout Hback Hdir) as Hstage.
  cbn [app] in Hstage.
  rewrite Hstage.
  replace
    (rev [5] ++
      7 :: map q16_restore (rev (rev scanned ++ 4 :: [])) ++
      source_bit next :: 7 :: final)
    with
    (([5; 7] ++
       map q16_restore (rev (rev scanned ++ [4]))) ++
      source_bit next :: [] ++ 7 :: final).
  2:{ cbn [rev app]. reflexivity. }
  pose proof (q19_to_q5_relocation
    ([5; 7] ++
      map q16_restore (rev (rev scanned ++ [4])))
    [] next [0] final Hsafe Hreturn) as Hfinish.
  cbn [app] in Hfinish.
  exact Hfinish.
Qed.

(** A successful checked rail gives all three premises automatically.
    This is a useful compiler/representation interface: construction of
    a safe rail is the only remaining layout-specific condition. *)
Theorem q12_right_guarded_railb_sound :
  forall scanned next final,
    q19_guarded_railb scanned = true ->
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length
           ([5; 7] ++
             map q16_restore (rev (rev scanned ++ [4])))) + 1))
      (entry_config 12 [5; 6]
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (6 :: rev
        ([5; 7] ++
          map q16_restore (rev (rev scanned ++ [4]))) ++ [0])
      ((if next then 3 else 2) :: final).
Proof.
  intros scanned next final Hcheck.
  apply q19_guarded_railb_spec in Hcheck.
  apply q12_right_guarded_scan_relocates_neighbor.
  - apply q19_guarded_rail_q15; exact Hcheck.
  - rewrite Forall_app.
    split.
    + apply q19_guarded_rail_rev_q16; exact Hcheck.
    + constructor; [unfold q16_pass; lia | constructor].
  - replace
      ([5; 7] ++
        map q16_restore (rev (rev scanned ++ [4])))
      with (5 :: 7 :: 4 :: map q16_restore scanned).
    2:{ rewrite rev_app_distr.
        simpl.
        rewrite rev_involutive.
        reflexivity. }
    constructor; [unfold q15_pass; lia |].
    constructor; [unfold q15_pass; lia |].
    constructor; [unfold q15_pass; lia |].
    apply (proj2 (q19_restored_scan_safe_iff scanned)).
    exact Hcheck.
Qed.

(** Every nonempty, conventionally marked wide-program rail FAILS
    the executable safety check, independent of source-state width.
    A repair must reroute or encode the payload off q19's raw-bit rail. *)
Theorem q19_guarded_railb_rejects_marked_wide_program :
  forall row rows,
    q19_guarded_railb
      (map entry_rewrite (encode_wide_program (row :: rows))) = false.
Proof.
  intros row rows.
  destruct (q19_guarded_railb
    (map entry_rewrite (encode_wide_program (row :: rows))))
    eqn:Hcheck; [|reflexivity].
  apply q19_guarded_railb_spec in Hcheck.
  rewrite encode_wide_program_cons in Hcheck.
  exfalso.
  exact (marked_wide_row_not_right_scan_safe row
    (encode_wide_program rows) Hcheck).
Qed.

Print Assumptions q19_guarded_railb_spec.
Print Assumptions q12_right_guarded_scan_relocates_neighbor.
Print Assumptions q12_right_guarded_railb_sound.
Print Assumptions q19_guarded_railb_rejects_marked_wide_program.

(** A second, stronger placement invariant: the entire program vault can
    sit on the LEFT of the displaced old data bit while the RIGHT rail
    is guarded.  The literal 23x8 machine returns the correct next-data
    marker and preserves the vault verbatim.  It is a q12-entry framed
    execution, NOT a claim that the canonical q5 source encoding reaches
    this entry or that q5 subsequently selects the correct source row. *)
Theorem q12_right_guarded_preserves_program_vault :
  forall scanned stored next final,
    q19_guarded_railb scanned = true ->
    run (reached_direction_cost [0; 5] [] scanned
           (rev scanned ++ [4]) [5] +
         (S (length
           ([5; 7] ++
             map q16_restore (rev (rev scanned ++ [4])))) + 1))
      (entry_config 12 ([5; 6] ++ stored)
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (6 :: rev
        ([5; 7] ++
          map q16_restore (rev (rev scanned ++ [4]))) ++
       0 :: stored)
      ((if next then 3 else 2) :: final).
Proof.
  intros scanned stored next final Hcheck.
  pose proof (proj1 (q19_guarded_railb_spec scanned) Hcheck)
    as Hguard.
  assert (Hscan : Forall q15_pass scanned).
  { apply q19_guarded_rail_q15; exact Hguard. }
  assert (Hback : Forall q16_pass (rev scanned ++ [4])).
  {
    rewrite Forall_app.
    split.
    - apply q19_guarded_rail_rev_q16; exact Hguard.
    - constructor; [unfold q16_pass; lia | constructor].
  }
  assert (Hsafe : Forall q15_pass
    ([5; 7] ++ map q16_restore (rev (rev scanned ++ [4])))).
  {
    replace
      ([5; 7] ++ map q16_restore (rev (rev scanned ++ [4])))
      with (5 :: 7 :: 4 :: map q16_restore scanned).
    2:{ rewrite rev_app_distr.
        simpl.
        rewrite rev_involutive.
        reflexivity. }
    constructor; [unfold q15_pass; lia |].
    constructor; [unfold q15_pass; lia |].
    constructor; [unfold q15_pass; lia |].
    apply (proj2 (q19_restored_scan_safe_iff scanned)).
    exact Hguard.
  }
  assert (H12 : Forall q12_pass [0; 5]).
  { repeat constructor; unfold q12_pass; lia. }
  assert (H14 : Forall q14_pass (rev [0; 5] ++ [])).
  { repeat constructor; unfold q14_pass; lia. }
  assert (Hlayout :
    map q14_restore (rev (rev [0; 5] ++ [])) =
      [] ++ source_bit false :: 5 :: []) by reflexivity.
  assert (Hdir : Forall q21_pass [5]).
  { constructor; [unfold q21_pass; lia | constructor]. }
  assert (Hreturn : Forall q17_pass []) by constructor.
  rewrite writeback_run_add.
  pose proof (q12_to_q19_reached_direction
    [5] 0 [] stored scanned next (7 :: final)
    [] false 5 [] H12 H14 Hscan Hlayout Hback Hdir) as Hstage.
  cbn [app] in Hstage.
  cbn [app].
  rewrite Hstage.
  replace
    (rev [5] ++
      7 :: map q16_restore (rev (rev scanned ++ 4 :: [])) ++
      source_bit next :: 7 :: final)
    with
    (([5; 7] ++
       map q16_restore (rev (rev scanned ++ [4]))) ++
      source_bit next :: [] ++ 7 :: final).
  2:{ cbn [rev app]. reflexivity. }
  pose proof (q19_to_q5_relocation
    ([5; 7] ++
      map q16_restore (rev (rev scanned ++ [4])))
    [] next (0 :: stored) final Hsafe Hreturn) as Hfinish.
  cbn [app] in Hfinish.
  exact Hfinish.
Qed.

Print Assumptions q12_right_guarded_preserves_program_vault.

(** The complete guarded q12 -> q5 relocation has an EXACT linear
    native microstep clock: three transitions per guarded scan cell,
    plus sixteen setup/return transitions. *)
Lemma q12_right_guarded_linear_clock :
  forall scanned,
    reached_direction_cost [0; 5] [] scanned
      (rev scanned ++ [4]) [5] +
    (S (length
      ([5; 7] ++
        map q16_restore (rev (rev scanned ++ [4])))) + 1) =
    3 * length scanned + 16.
Proof.
  intros scanned.
  unfold reached_direction_cost.
  repeat (rewrite length_app ||
          rewrite rev_length ||
          rewrite map_length).
  simpl [length].
  lia.
Qed.

Theorem q12_right_guarded_program_vault_linear :
  forall scanned stored next final,
    q19_guarded_railb scanned = true ->
    run (3 * length scanned + 16)
      (entry_config 12 ([5; 6] ++ stored)
        (0 :: 4 :: (scanned ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (6 :: rev
        ([5; 7] ++
          map q16_restore (rev (rev scanned ++ [4]))) ++
       0 :: stored)
      ((if next then 3 else 2) :: final).
Proof.
  intros scanned stored next final Hsafe.
  rewrite <- (q12_right_guarded_linear_clock scanned).
  apply q12_right_guarded_preserves_program_vault.
  exact Hsafe.
Qed.

Lemma q19_guarded_repeat_four :
  forall n, q19_guarded_railb (repeat 4 n) = true.
Proof.
  induction n as [|n IH]; simpl.
  - reflexivity.
  - exact IH.
Qed.

(** An unbounded, fully CONSTRUCTED family: any nonempty wide program,
    kept in the left-side vault, is preserved while the q12->q5 right
    transition crosses n safe 4-cells and marks the actual data bit.
    This proves a possible local tape placement, not its q5 reachability
    nor correct subsequent instruction lookup. *)
Theorem q12_right_unbounded_program_vault :
  forall n row rows next final,
    run (3 * n + 16)
      (entry_config 12
        ([5; 6] ++ encode_wide_program (row :: rows))
        (0 :: 4 ::
          (repeat 4 n ++ source_bit next :: 7 :: final))) =
    cfg_ml 5
      (6 :: rev
        ([5; 7] ++
          map q16_restore
            (rev (rev (repeat 4 n) ++ [4]))) ++
       0 :: encode_wide_program (row :: rows))
      ((if next then 3 else 2) :: final).
Proof.
  intros n row rows next final.
  replace (3 * n + 16)
    with (3 * length (repeat 4 n) + 16).
  2:{ rewrite repeat_length. reflexivity. }
  apply q12_right_guarded_program_vault_linear.
  apply q19_guarded_repeat_four.
Qed.

Print Assumptions q12_right_guarded_linear_clock.
Print Assumptions q12_right_guarded_program_vault_linear.
Print Assumptions q12_right_unbounded_program_vault.


(** q5's actual return alphabet is broader than the historical
    entry_scan_symbol predicate: 2, 3, 6, and 7 are also traversed,
    whereas 5 is the unique return delimiter. *)
Definition q5_return_pass (symbol : nat) : Prop :=
  symbol = 0 \/ symbol = 1 \/ symbol = 2 \/ symbol = 3 \/
  symbol = 4 \/ symbol = 6 \/ symbol = 7.

Lemma q5_return_pass_step :
  forall symbol next left right,
    q5_return_pass symbol ->
    step (entry_config 5 (next :: left) (symbol :: right)) =
    entry_config 5 left (next :: entry_rewrite symbol :: right).
Proof.
  intros symbol next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

(** Full q5 right-to-left return over the literal frozen table.
    The scan can contain any non-5 symbol in the actual alphabet. *)
Theorem q5_return_scan_to_first_five :
  forall remaining symbol prefix suffix,
    Forall q5_return_pass (symbol :: remaining) ->
    run (S (length (symbol :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix)
        (symbol :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (symbol :: remaining)) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros symbol prefix suffix Hscan.
  - inversion Hscan as [|? ? Hsymbol _]; subst.
    destruct Hsymbol as
      [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion Hscan as [|? ? Hsymbol Hrest]; subst.
    change (run (S (S (length (next :: rest))))
        (entry_config 5 (next :: (rest ++ 5 :: prefix))
          (symbol :: suffix)) =
      entry_config 1 (5 :: prefix)
        (map entry_rewrite (rev (symbol :: next :: rest)) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q5_return_pass_step symbol next
      (rest ++ 5 :: prefix) suffix Hsymbol).
    rewrite (IH next prefix (entry_rewrite symbol :: suffix) Hrest).
    cbn [rev].
    repeat rewrite map_app.
    cbn [map].
    rewrite (append_singleton_assoc
      (map entry_rewrite (rev rest) ++ [entry_rewrite next])
      (entry_rewrite symbol) suffix).
    reflexivity.
Qed.

(** A two-direction rail must ALSO avoid q5's stop delimiter.
    This checked contract accepts exactly 4, 6 and 7. *)
Definition q19_q5_roundtrip_railb (scanned : list nat) : bool :=
  forallb
    (fun symbol =>
      (Nat.leb 4 symbol && Nat.leb symbol 7) &&
      negb (Nat.eqb symbol 5)) scanned.

Theorem q19_q5_roundtrip_railb_spec :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true <->
    Forall (fun symbol =>
      symbol = 4 \/ symbol = 6 \/ symbol = 7) scanned.
Proof.
  induction scanned as [|symbol rest IH]; simpl.
  - split; intro H; constructor.
  - split.
    + intro H.
      apply andb_true_iff in H.
      destruct H as [Hsymbol Hrest].
      apply andb_true_iff in Hsymbol.
      destruct Hsymbol as [Hbound Hnotfive].
      apply andb_true_iff in Hbound.
      destruct Hbound as [Hlo Hhi].
      change (Nat.leb 4 symbol = true) in Hlo.
      change (Nat.leb symbol 7 = true) in Hhi.
      change (negb (Nat.eqb symbol 5) = true) in Hnotfive.
      apply Nat.leb_le in Hlo.
      apply Nat.leb_le in Hhi.
      apply negb_true_iff in Hnotfive.
      apply Nat.eqb_neq in Hnotfive.
      constructor.
      * assert (symbol = 4 \/ symbol = 6 \/ symbol = 7) by lia.
        assumption.
      * apply (proj1 IH); exact Hrest.
    + intro H.
      inversion H as [|? ? Hsymbol Hrest]; subst.
      apply (proj2 IH) in Hrest.
      destruct Hsymbol as [-> | [-> | ->]];
        simpl; exact Hrest.
Qed.

Lemma q19_q5_roundtrip_railb_q19 :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true ->
    q19_guarded_railb scanned = true.
Proof.
  intros scanned H.
  apply (proj2 (q19_guarded_railb_spec scanned)).
  apply (proj1 (q19_q5_roundtrip_railb_spec scanned)) in H.
  induction H as [|symbol rest Hsymbol Hrest IH].
  - constructor.
  - constructor; [destruct Hsymbol as [-> | [-> | ->]]; lia | exact IH].
Qed.

Example q19_guarded_railb_allows_q5_delimiter :
  q19_guarded_railb [5] = true /\
  q19_q5_roundtrip_railb [5] = false.
Proof. split; reflexivity. Qed.

Print Assumptions q5_return_scan_to_first_five.
Print Assumptions q19_q5_roundtrip_railb_spec.
Print Assumptions q19_q5_roundtrip_railb_q19.


(** The dual guard is fixed by both native restoration and q5 return
    rewriting: on 4,6,7 neither phase changes the cell value. *)
Lemma q19_q5_roundtrip_fixed_maps :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true ->
    map q16_restore scanned = scanned /\
    map entry_rewrite scanned = scanned.
Proof.
  intros scanned H.
  apply (proj1 (q19_q5_roundtrip_railb_spec scanned)) in H.
  induction H as [|symbol rest Hsymbol Hrest IH].
  - split; reflexivity.
  - destruct IH as [IHrestore IHentry].
    destruct Hsymbol as [-> | [-> | ->]]; simpl;
      rewrite IHrestore, IHentry; split; reflexivity.
Qed.

Lemma q19_q5_roundtrip_return_safe :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true ->
    Forall q5_return_pass (6 :: rev scanned ++ [4; 7]).
Proof.
  intros scanned H.
  apply (proj1 (q19_q5_roundtrip_railb_spec scanned)) in H.
  assert (Hrev : Forall q5_return_pass (rev scanned)).
  {
    induction H as [|symbol rest Hsymbol Hrest IH].
    - constructor.
    - simpl.
      rewrite Forall_app.
      split.
      + exact IH.
      + constructor.
        * destruct Hsymbol as [-> | [-> | ->]];
            unfold q5_return_pass; auto 10.
        * constructor.
  }
  constructor.
  - unfold q5_return_pass; auto 10.
  - rewrite Forall_app.
    split.
    + exact Hrev.
    + constructor.
      * unfold q5_return_pass; auto 10.
      * constructor.
        -- unfold q5_return_pass; auto 10.
        -- constructor.
Qed.

(** The actual q5 return moves left across 6, the restored dual-safe
    rail, the 4 and 7 sentinels, and enters q1 at the FIRST 5.
    The program remains to the left of the 0-boundary. *)
Theorem q5_roundtrip_program_vault_return :
  forall scanned stored (next : bool) final,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 4)
      (cfg_ml 5
        (6 :: rev ([5; 7; 4] ++ scanned) ++ 0 :: stored)
        ((if next then 3 else 2) :: final)) =
    entry_config 1 (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2] ++ final).
Proof.
  intros scanned stored next final Hguard.
  pose proof (q19_q5_roundtrip_return_safe scanned Hguard)
    as Hsafe.
  pose proof (proj2 (q19_q5_roundtrip_fixed_maps
    scanned Hguard)) as Hrewrite.
  pose proof (q5_return_scan_to_first_five
    (rev scanned ++ [4; 7]) 6
    (0 :: stored)
    ((if next then 3 else 2) :: final) Hsafe) as Hreturn.
  replace (S (length (6 :: rev scanned ++ [4; 7])))
    with (length scanned + 4) in Hreturn.
  2:{
    cbn [length].
    repeat (rewrite app_length || rewrite rev_length).
    cbn [length].
    lia.
  }
  assert (Hshape :
    cfg_ml 5
      (6 :: rev ([5; 7; 4] ++ scanned) ++ 0 :: stored)
      ((if next then 3 else 2) :: final) =
    entry_config 5
      ((rev scanned ++ [4; 7]) ++ 5 :: 0 :: stored)
      (6 :: (if next then 3 else 2) :: final)).
  {
    unfold cfg_ml.
    rewrite rev_app_distr.
    cbn [rev].
    repeat (rewrite app_nil_r || rewrite <- app_assoc).
    reflexivity.
  }
  rewrite Hshape.
  rewrite Hreturn.
  cbn [rev].
  rewrite rev_app_distr.
  cbn [rev].
  rewrite rev_involutive.
  repeat rewrite map_app.
  cbn [map entry_rewrite].
  rewrite Hrewrite.
  repeat (rewrite app_nil_l || rewrite app_nil_r ||
          rewrite <- app_assoc).
  reflexivity.
Qed.

(** Exact end-to-end native q12->q1 trace, for ANY stored source code
    and ANY finite dual-safe right rail.  Source-level dispatch and
    source-step simulation remain separate, unproved obligations. *)
Theorem q12_right_roundtrip_program_vault_to_q1 :
  forall scanned stored next final,
    q19_q5_roundtrip_railb scanned = true ->
    run (4 * length scanned + 20)
      (entry_config 12 ([5; 6] ++ stored)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 :: final))) =
    entry_config 1 (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2] ++ final).
Proof.
  intros scanned stored next final Hguard.
  pose proof (q19_q5_roundtrip_railb_q19
    scanned Hguard) as H19.
  pose proof (proj1 (q19_q5_roundtrip_fixed_maps
    scanned Hguard)) as Hrestore.
  replace (4 * length scanned + 20)
    with ((3 * length scanned + 16) + (length scanned + 4))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_right_guarded_program_vault_linear
    scanned stored next final H19).
  replace (map q16_restore (rev (rev scanned ++ [4])))
    with (4 :: scanned).
  2:{
    rewrite rev_app_distr.
    rewrite rev_involutive.
    rewrite map_app.
    rewrite Hrestore.
    reflexivity.
  }
  change
    (run (length scanned + 4)
      (cfg_ml 5
        (6 :: rev ([5; 7; 4] ++ scanned) ++ 0 :: stored)
        ((if next then 3 else 2) :: final)) =
     entry_config 1 (5 :: 0 :: stored)
       ([7; 4] ++ scanned ++
        [6; if next then 3 else 2] ++ final)).
  apply q5_roundtrip_program_vault_return.
  exact Hguard.
Qed.

Print Assumptions q19_q5_roundtrip_fixed_maps.
Print Assumptions q5_roundtrip_program_vault_return.
Print Assumptions q12_right_roundtrip_program_vault_to_q1.

(** On the exact q5 return frame, the first two q1 transitions
    move right over 7 and then 4, selecting q6.  The stored program
    remains untouched on the far side of the two delimiters. *)
Lemma q1_returned_vault_enters_q6 :
  forall scanned stored (next : bool) final,
    run 2
      (entry_config 1 (5 :: 0 :: stored)
        ([7; 4] ++ scanned ++
         [6; if next then 3 else 2] ++ final)) =
    entry_config 6 (4 :: 7 :: 5 :: 0 :: stored)
      (scanned ++ [6; if next then 3 else 2] ++ final).
Proof. intros scanned stored next final; reflexivity. Qed.

Theorem q12_right_roundtrip_program_vault_to_q6 :
  forall scanned stored (next : bool) final,
    q19_q5_roundtrip_railb scanned = true ->
    run (4 * length scanned + 22)
      (entry_config 12 ([5; 6] ++ stored)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 :: final))) =
    entry_config 6 (4 :: 7 :: 5 :: 0 :: stored)
      (scanned ++ [6; if next then 3 else 2] ++ final).
Proof.
  intros scanned stored next final Hguard.
  replace (4 * length scanned + 22)
    with ((4 * length scanned + 20) + 2) by lia.
  rewrite writeback_run_add.
  rewrite (q12_right_roundtrip_program_vault_to_q1
    scanned stored next final Hguard).
  apply q1_returned_vault_enters_q6.
Qed.

Print Assumptions q12_right_roundtrip_program_vault_to_q6.

(** A separate negative-control invariant: q12 and q13 scan left,
    preserving every non-6 symbol, and cannot reach their 6-triggered
    q14 exit if their entire left frontier is 6-free.  At the left
    edge of the finite tape, the blank is symbol 2 and is also safe. *)
Theorem q12_six_free_left_stays_q12 :
  forall fuel left head right,
    Forall q12_pass left ->
    q12_pass head ->
    c_state (run fuel (entry_config 12 left (head :: right))) = 12.
Proof.
  induction fuel as [|fuel IH]; intros left head right Hleft Hhead.
  - reflexivity.
  - rewrite entry_run_successor.
    destruct left as [|next rest].
    + assert (Hempty :
        step (entry_config 12 [] (head :: right)) =
        entry_config 12 [] (2 :: head :: right)).
      {
        unfold q12_pass in Hhead.
        destruct Hhead as
          [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
          reflexivity.
      }
      rewrite Hempty.
      apply IH.
      * constructor.
      * unfold q12_pass; auto 10.
    + inversion Hleft as [|? ? Hnext Hrest]; subst.
      rewrite (q12_pass_step head next rest right Hhead).
      apply IH; assumption.
Qed.

Theorem q13_six_free_left_stays_q13 :
  forall fuel left head right,
    Forall q13_pass left ->
    q13_pass head ->
    c_state (run fuel (entry_config 13 left (head :: right))) = 13.
Proof.
  induction fuel as [|fuel IH]; intros left head right Hleft Hhead.
  - reflexivity.
  - rewrite entry_run_successor.
    destruct left as [|next rest].
    + assert (Hempty :
        step (entry_config 13 [] (head :: right)) =
        entry_config 13 [] (2 :: head :: right)).
      {
        unfold q13_pass, q12_pass in Hhead.
        destruct Hhead as
          [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
          reflexivity.
      }
      rewrite Hempty.
      apply IH.
      * constructor.
      * unfold q13_pass, q12_pass; auto 10.
    + inversion Hleft as [|? ? Hnext Hrest]; subst.
      rewrite (q13_pass_step head next rest right Hhead).
      apply IH; assumption.
Qed.

Print Assumptions q12_six_free_left_stays_q12.
Print Assumptions q13_six_free_left_stays_q13.

Lemma q12_source_bit_safe :
  forall bit, q12_pass (source_bit bit).
Proof. intros []; unfold q12_pass; simpl; auto 10. Qed.

Lemma q12_source_bits_safe :
  forall bits, Forall q12_pass (map source_bit bits).
Proof.
  induction bits as [|bit bits IH]; simpl.
  - constructor.
  - constructor; [apply q12_source_bit_safe | exact IH].
Qed.

(** Ordinary wide-program records use only 4, 0 and 1.  In particular,
    unlike a real q12 direction frame they never contain the return
    trigger 6. *)
Lemma q12_wide_row_safe :
  forall row, Forall q12_pass (encode_wide_row row).
Proof.
  intros row.
  unfold encode_wide_row.
  constructor.
  - unfold q12_pass; auto 10.
  - repeat rewrite Forall_app.
    repeat split;
      try apply q12_source_bits_safe;
      repeat (constructor; try apply q12_source_bit_safe).
Qed.

Lemma q12_wide_program_safe :
  forall rows, Forall q12_pass (encode_wide_program rows).
Proof.
  induction rows as [|row rows IH].
  - constructor.
  - rewrite encode_wide_program_cons.
    rewrite Forall_app.
    split; [apply q12_wide_row_safe | exact IH].
Qed.

Theorem q12_wide_vault_without_six_cannot_exit :
  forall fuel rows final,
    c_state (run fuel
      (entry_config 12 (5 :: 0 :: encode_wide_program rows)
        (7 :: final))) = 12.
Proof.
  intros fuel rows final.
  apply q12_six_free_left_stays_q12.
  - constructor.
    + unfold q12_pass; auto 10.
    + constructor.
      * unfold q12_pass; auto 10.
      * apply q12_wide_program_safe.
  - unfold q12_pass; auto 10.
Qed.

Theorem q13_wide_vault_without_six_cannot_exit :
  forall fuel rows final,
    c_state (run fuel
      (entry_config 13 (5 :: 0 :: encode_wide_program rows)
        (7 :: final))) = 13.
Proof.
  intros fuel rows final.
  apply q13_six_free_left_stays_q13.
  - constructor.
    + unfold q13_pass, q12_pass; auto 10.
    + constructor.
      * unfold q13_pass, q12_pass; auto 10.
      * change (Forall q12_pass (encode_wide_program rows)).
        apply q12_wide_program_safe.
  - unfold q13_pass, q12_pass; auto 10.
Qed.

Print Assumptions q12_wide_vault_without_six_cannot_exit.
Print Assumptions q13_wide_vault_without_six_cannot_exit.


(** The next return obligations are proved against the same literal table,
    not an idealized source-level interpreter.  In q6 a 2/3 marker is
    *not* a raw bit: only 0 and 1 select q8 and q7 respectively. *)
Definition q6_nonraw (symbol : nat) : Prop :=
  symbol = 2 \/ symbol = 3 \/ symbol = 4 \/
  symbol = 5 \/ symbol = 6 \/ symbol = 7.

Lemma q6_nonraw_step :
  forall symbol left right,
    q6_nonraw symbol ->
    step (entry_config 6 left (symbol :: right)) =
    entry_config 6 (symbol :: left) right.
Proof.
  intros symbol left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q6_guarded_rail_safe :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true ->
    Forall q6_nonraw scanned.
Proof.
  intros scanned H.
  apply (proj1 (q19_q5_roundtrip_railb_spec scanned)) in H.
  induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [destruct Hs as [-> | [-> | ->]];
      unfold q6_nonraw; auto 10 | exact IH].
Qed.

Theorem q6_all_fuel_nonraw_right_stays_q6 :
  forall fuel left right,
    Forall q6_nonraw right ->
    c_state (run fuel (entry_config 6 left right)) = 6.
Proof.
  induction fuel as [|fuel IH]; intros left right Hright.
  - reflexivity.
  - destruct right as [|symbol rest].
    + change
        (c_state (run fuel (entry_config 6 (2 :: left) [])) = 6).
      apply IH; constructor.
    + inversion Hright as [|? ? Hsymbol Hrest]; subst.
      rewrite entry_run_successor.
      rewrite (q6_nonraw_step symbol left rest Hsymbol).
      apply IH; exact Hrest.
Qed.

(** If the returned vault has no further unmarked 0/1 to its right,
    q6 is a permanent sink, including when it reaches finite-tape blank. *)
Theorem q12_roundtrip_no_raw_suffix_stalls_q6 :
  forall scanned rows next fuel,
    q19_q5_roundtrip_railb scanned = true ->
    c_state (run (4 * length scanned + 22 + fuel)
      (entry_config 12 ([5; 6] ++ encode_wide_program rows)
        (0 :: 4 :: (scanned ++ source_bit next :: [7])))) = 6.
Proof.
  intros scanned rows next fuel Hguard.
  rewrite writeback_run_add.
  rewrite (q12_right_roundtrip_program_vault_to_q6
    scanned (encode_wide_program rows) next [] Hguard).
  apply q6_all_fuel_nonraw_right_stays_q6.
  rewrite Forall_app.
  split.
  - apply q6_guarded_rail_safe; exact Hguard.
  - constructor.
    + unfold q6_nonraw; auto 10.
    + constructor.
      * destruct next; unfold q6_nonraw; simpl; auto 10.
      * constructor.
Qed.

(** q6 makes one step per safe rightward cell before its first raw bit.
    The left zipper is reversed exactly, with no invented delimiters. *)
Lemma q6_nonraw_scan :
  forall scanned left tail,
    Forall q6_nonraw scanned ->
    run (length scanned)
      (entry_config 6 left (scanned ++ tail)) =
    entry_config 6 (rev scanned ++ left) tail.
Proof.
  induction scanned as [|symbol rest IH];
    intros left tail Hscan.
  - reflexivity.
  - inversion Hscan as [|? ? Hsymbol Hrest]; subst.
    cbn [length app].
    rewrite entry_run_successor.
    rewrite (q6_nonraw_step symbol left (rest ++ tail) Hsymbol).
    rewrite (IH (symbol :: left) tail Hrest).
    cbn [rev].
    rewrite append_singleton_assoc.
    reflexivity.
Qed.

Theorem q6_guarded_rail_to_q7_or_q8 :
  forall scanned stored (next extra : bool) tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 3)
      (entry_config 6 (4 :: 7 :: 5 :: 0 :: stored)
        (scanned ++ 6 :: (if next then 3 else 2) ::
         source_bit extra :: tail)) =
    entry_config (if extra then 7 else 8)
      (6 :: rev scanned ++ 4 :: 7 :: 5 :: 0 :: stored)
      ((if next then 3 else 2) ::
       (if extra then 3 else 2) :: tail).
Proof.
  intros scanned stored next extra tail Hguard.
  rewrite writeback_run_add.
  rewrite (q6_nonraw_scan scanned
    (4 :: 7 :: 5 :: 0 :: stored)
    (6 :: (if next then 3 else 2) :: source_bit extra :: tail)).
  - destruct next, extra; reflexivity.
  - apply q6_guarded_rail_safe; exact Hguard.
Qed.

(** q7 and q8 cross every non-5 cell unchanged; the first 5 selects
    q9 and q10 and advances back to the right. *)
Lemma q78_pass_step :
  forall q symbol next left right,
    (q = 7 \/ q = 8) ->
    q5_return_pass symbol ->
    step (entry_config q (next :: left) (symbol :: right)) =
    entry_config q left (next :: symbol :: right).
Proof.
  intros q symbol next left right Hq Hsymbol.
  destruct Hq as [-> | ->];
    destruct Hsymbol as
      [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Theorem q78_scan_back_to_first_five :
  forall remaining symbol outer suffix q,
    (q = 7 \/ q = 8) ->
    Forall q5_return_pass (symbol :: remaining) ->
    run (S (length (symbol :: remaining)))
      (entry_config q (remaining ++ 5 :: outer)
        (symbol :: suffix)) =
    entry_config (if Nat.eqb q 7 then 9 else 10) (5 :: outer)
      (rev (symbol :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros symbol outer suffix q Hq Hsafe.
  - inversion Hsafe as [|? ? Hsymbol _]; subst.
    destruct Hq as [-> | ->];
      destruct Hsymbol as
        [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion Hsafe as [|? ? Hsymbol Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config q (next :: (rest ++ 5 :: outer))
        (symbol :: suffix)) =
      entry_config (if Nat.eqb q 7 then 9 else 10) (5 :: outer)
        (rev (symbol :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q78_pass_step q symbol next
      (rest ++ 5 :: outer) suffix Hq Hsymbol).
    rewrite (IH next outer (symbol :: suffix) q Hq Hrest).
    cbn [rev].
    repeat rewrite append_singleton_assoc.
    reflexivity.
Qed.

Print Assumptions q12_roundtrip_no_raw_suffix_stalls_q6.
Print Assumptions q6_guarded_rail_to_q7_or_q8.
Print Assumptions q78_scan_back_to_first_five.


(** q7/q8 encounter the first 5 on their left after passing the
    newly marked bit, the 6 return marker, the dual-safe rail, 4 and 7. *)
Lemma q78_return_rail_safe :
  forall scanned (next : bool),
    q19_q5_roundtrip_railb scanned = true ->
    Forall q5_return_pass
      ((if next then 3 else 2) :: 6 :: rev scanned ++ [4; 7]).
Proof.
  intros scanned next Hguard.
  pose proof (proj1 (q19_q5_roundtrip_railb_spec scanned)
    Hguard) as Hrail.
  clear Hguard.
  assert (Hrev : Forall q5_return_pass (rev scanned)).
  {
    induction Hrail as [|s rest Hs Hrest IH].
    - constructor.
    - cbn [rev].
      rewrite Forall_app.
      split.
      + exact IH.
      + constructor.
        * destruct Hs as [-> | [-> | ->]];
            unfold q5_return_pass; auto 10.
        * constructor.
  }
  constructor.
  - destruct next; unfold q5_return_pass; simpl; auto 10.
  - constructor.
    + unfold q5_return_pass; auto 10.
    + rewrite Forall_app.
      split.
      * exact Hrev.
      * constructor.
        -- unfold q5_return_pass; auto 10.
        -- constructor.
           ++ unfold q5_return_pass; auto 10.
           ++ constructor.
Qed.

Theorem q78_returned_vault_to_q9_or_q10 :
  forall scanned stored (next extra : bool) tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 5)
      (entry_config (if extra then 7 else 8)
        (6 :: rev scanned ++ 4 :: 7 :: 5 :: 0 :: stored)
        ((if next then 3 else 2) ::
         (if extra then 3 else 2) :: tail)) =
    entry_config (if extra then 9 else 10) (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail Hguard.
  replace (length scanned + 5)
    with (S (length
      ((if next then 3 else 2) :: 6 :: rev scanned ++ [4; 7]))).
  2:{
    cbn [length].
    repeat rewrite app_length.
    rewrite rev_length.
    cbn [length].
    lia.
  }
  replace (6 :: rev scanned ++ 4 :: 7 :: 5 :: 0 :: stored)
    with ((6 :: rev scanned ++ [4; 7]) ++ 5 :: 0 :: stored).
  2:{
    change (6 :: ((rev scanned ++ [4; 7]) ++ (5 :: 0 :: stored)) =
            6 :: (rev scanned ++ ([4; 7] ++ (5 :: 0 :: stored)))).
    f_equal.
    symmetry; apply app_assoc.
  }
  assert (Hq : (if extra then 7 else 8) = 7 \/
               (if extra then 7 else 8) = 8).
  { destruct extra; simpl; auto. }
  rewrite (q78_scan_back_to_first_five
    (6 :: rev scanned ++ [4; 7]) (if next then 3 else 2)
    (0 :: stored) ((if extra then 3 else 2) :: tail)
    (if extra then 7 else 8) Hq
    (q78_return_rail_safe scanned next Hguard)).
  destruct next, extra; simpl.
  all: repeat rewrite rev_app_distr;
    cbn [rev];
    rewrite rev_involutive;
    repeat rewrite <- app_assoc;
    cbn [app];
    reflexivity.
Qed.

(** Literal q9/q10 reads 7, then reads 4 and turns back left:
    q9 selects q12, q10 selects q13.  The head is on 7 again. *)
Lemma q910_restored_four_to_q12_or_q13 :
  forall scanned stored (next extra : bool) tail,
    run 2
      (entry_config (if extra then 9 else 10) (5 :: 0 :: stored)
        ([7; 4] ++ scanned ++
         [6; if next then 3 else 2; if extra then 3 else 2] ++ tail)) =
    entry_config (if extra then 12 else 13) (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail.
  destruct extra; reflexivity.
Qed.

(** Complete post-q6 return along a suffix beginning with one raw bit.
    This is not a claim about every possible suffix: q6 needs that bit
    to leave its rightward scan. *)
Theorem q6_complete_return_to_q12_or_q13 :
  forall scanned stored (next extra : bool) tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (2 * length scanned + 10)
      (entry_config 6 (4 :: 7 :: 5 :: 0 :: stored)
        (scanned ++ 6 :: (if next then 3 else 2) ::
         source_bit extra :: tail)) =
    entry_config (if extra then 12 else 13) (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail Hguard.
  replace (2 * length scanned + 10)
    with ((length scanned + 3) + ((length scanned + 5) + 2))
    by lia.
  rewrite writeback_run_add.
  rewrite (q6_guarded_rail_to_q7_or_q8
    scanned stored next extra tail Hguard).
  rewrite writeback_run_add.
  rewrite (q78_returned_vault_to_q9_or_q10
    scanned stored next extra tail Hguard).
  apply q910_restored_four_to_q12_or_q13.
Qed.

(** The complete native q12->q6->q7/q8->q9/q10->q12/q13
    cycle has an exact affine step count, with the stored program intact.
    The final raw bit is provided by the explicit post-7 suffix. *)
Theorem q12_complete_return_into_six_free_vault :
  forall scanned rows next extra tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (6 * length scanned + 32)
      (entry_config 12 ([5; 6] ++ encode_wide_program rows)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 :: source_bit extra :: tail))) =
    entry_config (if extra then 12 else 13)
      (5 :: 0 :: encode_wide_program rows)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned rows next extra tail Hguard.
  replace (6 * length scanned + 32)
    with ((4 * length scanned + 22) + (2 * length scanned + 10))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_right_roundtrip_program_vault_to_q6
    scanned (encode_wide_program rows) next
    (source_bit extra :: tail) Hguard).
  apply q6_complete_return_to_q12_or_q13.
  exact Hguard.
Qed.

(** Main all-fuel consequence: after the complete native return,
    there is no 6 anywhere to the left of the q12/q13 head.
    Neither state can escape, for any additional finite fuel. *)
Theorem q12_complete_vault_cycle_cannot_resume :
  forall scanned rows next extra tail fuel,
    q19_q5_roundtrip_railb scanned = true ->
    c_state (run (6 * length scanned + 32 + fuel)
      (entry_config 12 ([5; 6] ++ encode_wide_program rows)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 :: source_bit extra :: tail)))) =
    if extra then 12 else 13.
Proof.
  intros scanned rows next extra tail fuel Hguard.
  rewrite writeback_run_add.
  rewrite (q12_complete_return_into_six_free_vault
    scanned rows next extra tail Hguard).
  destruct extra.
  - change (c_state (run fuel
      (entry_config 12 (5 :: 0 :: encode_wide_program rows)
        (7 :: (4 :: scanned ++
          6 :: (if next then 3 else 2) :: 3 :: tail)))) = 12).
    apply q12_wide_vault_without_six_cannot_exit.
  - change (c_state (run fuel
      (entry_config 13 (5 :: 0 :: encode_wide_program rows)
        (7 :: (4 :: scanned ++
          6 :: (if next then 3 else 2) :: 2 :: tail)))) = 13).
    apply q13_wide_vault_without_six_cannot_exit.
Qed.

Print Assumptions q12_complete_return_into_six_free_vault.
Print Assumptions q12_complete_vault_cycle_cannot_resume.


(** A constructive delimiter repair.  The earlier obstruction consumes the
    sole 6 to the left of the current q12 head.  Here the stored vault
    starts with an additional protected 6, before any wide source rows.
    The frozen 23x8 table is unchanged. *)

(** Generalize the exact q12 return over an arbitrary stored suffix.
    The wide-program encoding will be instantiated only at the next step. *)
Theorem q12_complete_return_with_arbitrary_stored :
  forall scanned stored next extra tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (6 * length scanned + 32)
      (entry_config 12 ([5; 6] ++ stored)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 :: source_bit extra :: tail))) =
    entry_config (if extra then 12 else 13) (5 :: 0 :: stored)
      ([7; 4] ++ scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail Hguard.
  replace (6 * length scanned + 32)
    with ((4 * length scanned + 22) + (2 * length scanned + 10))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_right_roundtrip_program_vault_to_q6
    scanned stored next (source_bit extra :: tail) Hguard).
  apply q6_complete_return_to_q12_or_q13.
  exact Hguard.
Qed.

(** q12/q13 return left across 7,5,0; the protected 6 selects q14.
    q14 immediately crosses 0,5,7,4 and enters q15.  Every transition
    here is executable by reflexive reduction of the frozen table. *)
Lemma q12q13_protected_six_reopens_q15 :
  forall scanned stored (next extra : bool) tail,
    run 8
      (entry_config (if extra then 12 else 13)
        (5 :: 0 :: 6 :: stored)
        ([7; 4] ++ scanned ++
         [6; if next then 3 else 2; if extra then 3 else 2] ++ tail)) =
    entry_config 15
      (4 :: 7 :: 5 :: 0 :: (if extra then 3 else 2) :: stored)
      (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail.
  destruct extra; reflexivity.
Qed.

(** The program is now behind a surviving 2/3 direction mark; no source
    row is edited by the eight-step reentry.  Exact cost: 6n+40. *)
Theorem q12_protected_second_six_reenters_q15 :
  forall scanned rows next extra tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (6 * length scanned + 40)
      (entry_config 12
        ([5; 6] ++ 6 :: encode_wide_program rows)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 :: source_bit extra :: tail))) =
    entry_config 15
      (4 :: 7 :: 5 :: 0 ::
       (if extra then 3 else 2) :: encode_wide_program rows)
      (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned rows next extra tail Hguard.
  replace (6 * length scanned + 40)
    with ((6 * length scanned + 32) + 8) by lia.
  rewrite writeback_run_add.
  rewrite (q12_complete_return_with_arbitrary_stored
    scanned (6 :: encode_wide_program rows) next extra tail Hguard).
  apply q12q13_protected_six_reopens_q15.
Qed.

Lemma q15_returned_rail_is_safe :
  forall scanned (next extra : bool),
    q19_q5_roundtrip_railb scanned = true ->
    Forall q15_pass
      (scanned ++ [6; if next then 3 else 2;
                       if extra then 3 else 2]).
Proof.
  intros scanned next extra Hguard.
  pose proof (q6_guarded_rail_safe scanned Hguard) as Hsafe.
  clear Hguard.
  assert (Hrail : Forall q15_pass scanned).
  {
    induction Hsafe as [|s rest Hs Hrest IH].
    - constructor.
    - constructor.
      + unfold q6_nonraw in Hs.
        unfold q15_pass.
        tauto.
      + exact IH.
  }
  rewrite Forall_app.
  split.
  - exact Hrail.
  - constructor.
    + unfold q15_pass; auto 10.
    + constructor.
      * destruct next; unfold q15_pass; simpl; auto 10.
      * constructor.
        -- destruct extra; unfold q15_pass; simpl; auto 10.
        -- constructor.
Qed.

(** With another unmarked data bit available to q15, the second sentinel
    enables a complete native reentry to q16.  Cost: 7n+44.  This does
    NOT by itself identify a simulated source instruction or prove
    that the new vault encoding is globally invariant. *)
Theorem q12_protected_second_six_reenters_q16 :
  forall scanned rows next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (7 * length scanned + 44)
      (entry_config 12
        ([5; 6] ++ 6 :: encode_wide_program rows)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 ::
          source_bit extra :: source_bit target :: tail))) =
    cfg_ml 16
      (rev (scanned ++
        [6; if next then 3 else 2; if extra then 3 else 2]) ++
       4 :: 7 :: 5 :: 0 ::
       (if extra then 3 else 2) :: encode_wide_program rows)
      (source_bit target :: tail).
Proof.
  intros scanned rows next extra target tail Hguard.
  replace (7 * length scanned + 44)
    with ((6 * length scanned + 40) +
          S (length (scanned ++
            [6; if next then 3 else 2; if extra then 3 else 2]))).
  2:{
    rewrite app_length.
    cbn [length].
    lia.
  }
  rewrite writeback_run_add.
  rewrite (q12_protected_second_six_reenters_q15
    scanned rows next extra (source_bit target :: tail) Hguard).
  replace
    (scanned ++
     [6; if next then 3 else 2; if extra then 3 else 2] ++
     source_bit target :: tail)
    with
    ((scanned ++
      [6; if next then 3 else 2; if extra then 3 else 2]) ++
      source_bit target :: tail).
  2:{
    rewrite <- app_assoc.
    reflexivity.
  }
  apply q15_scan_to_raw.
  apply q15_returned_rail_is_safe; exact Hguard.
Qed.

Print Assumptions q12_protected_second_six_reenters_q15.
Print Assumptions q12_protected_second_six_reenters_q16.


(** Certified continuation beyond the q16 entry.  The entire restore
    scan, including the return-control cells, is made explicit.  The
    remaining program is arbitrary and untouched by this segment. *)

Definition protected_q16_backscan
    (scanned : list nat) (next extra : bool) : list nat :=
  rev (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2]) ++
  [4; 7; 5].

Lemma protected_q16_backscan_nonempty :
  forall scanned next extra,
    protected_q16_backscan scanned next extra <> [].
Proof.
  intros scanned next extra.
  unfold protected_q16_backscan.
  destruct (rev (scanned ++
    [6; if next then 3 else 2; if extra then 3 else 2]));
    discriminate.
Qed.

Lemma protected_q16_backscan_length :
  forall scanned next extra,
    length (protected_q16_backscan scanned next extra) =
    length scanned + 6.
Proof.
  intros scanned next extra.
  unfold protected_q16_backscan.
  repeat rewrite app_length.
  rewrite rev_length.
  repeat rewrite app_length.
  cbn [length].
  lia.
Qed.

Lemma protected_q16_backscan_safe :
  forall scanned next extra,
    q19_q5_roundtrip_railb scanned = true ->
    Forall q16_pass (protected_q16_backscan scanned next extra).
Proof.
  intros scanned next extra Hguard.
  pose proof
    (q15_returned_rail_is_safe scanned next extra Hguard) as Hrail.
  change (Forall q16_pass
    (scanned ++
      [6; if next then 3 else 2; if extra then 3 else 2])) in Hrail.
  assert (Hrev : forall l, Forall q16_pass l ->
                            Forall q16_pass (rev l)).
  {
    intros l Hsafe.
    induction Hsafe as [|x xs Hx Hxs IH].
    - constructor.
    - cbn [rev].
      rewrite Forall_app.
      split.
      + exact IH.
      + constructor; [exact Hx | constructor].
  }
  unfold protected_q16_backscan.
  rewrite Forall_app.
  split.
  - apply Hrev; exact Hrail.
  - constructor.
    + unfold q16_pass; auto 10.
    + constructor.
      * unfold q16_pass; auto 10.
      * constructor.
        -- unfold q16_pass; auto 10.
        -- constructor.
Qed.

(** A q16 traversal consumes precisely one native step for each restored
    symbol, plus the raw 0, which it rewrites to a 7. *)
Lemma q16_backscan_crosses_raw_zero :
  forall backscan mark stored target tail,
    backscan <> [] ->
    Forall q16_pass backscan ->
    run (S (length backscan))
      (cfg_ml 16 (backscan ++ 0 :: mark :: stored)
        (source_bit target :: tail)) =
    cfg_ml 21 (mark :: stored)
      (7 :: map q16_restore (rev backscan) ++
       source_bit target :: tail).
Proof.
  intros [|s rest] mark stored target tail Hnonempty Hsafe.
  - contradiction Hnonempty; reflexivity.
  - change
      (run (S (length (s :: rest)))
        (entry_config 16 (rest ++ 0 :: mark :: stored)
          (s :: source_bit target :: tail)) =
       cfg_ml 21 (mark :: stored)
         (7 :: map q16_restore (rev (s :: rest)) ++
          source_bit target :: tail)).
    exact (q16_restore_to_raw rest s false
      (mark :: stored) (source_bit target :: tail) Hsafe).
Qed.

(** The frozen table, not an abstract branch oracle, selects 19/20.
    In the left case cfg_ml accounts for the newly exposed outer cell. *)
Lemma q21_protected_direction_mark :
  forall (extra : bool) stored rest,
    step (cfg_ml 21 ((if extra then 3 else 2) :: stored)
      (7 :: rest)) =
    if extra
    then entry_config 19 (0 :: stored) (7 :: rest)
    else cfg_ml 20 stored (0 :: 7 :: rest).
Proof.
  intros extra stored rest.
  destruct extra; destruct stored; reflexivity.
Qed.

Theorem q16_protected_backscan_selects_native_branch :
  forall scanned stored next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 8)
      (cfg_ml 16
        (protected_q16_backscan scanned next extra ++
         0 :: (if extra then 3 else 2) :: stored)
        (source_bit target :: tail)) =
    if extra
    then entry_config 19 (0 :: stored)
      (7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail)
    else cfg_ml 20 stored
      (0 :: 7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail).
Proof.
  intros scanned stored next extra target tail Hguard.
  replace (length scanned + 8)
    with (S (length (protected_q16_backscan scanned next extra)) + 1).
  2:{
    rewrite protected_q16_backscan_length.
    lia.
  }
  rewrite writeback_run_add.
  rewrite (q16_backscan_crosses_raw_zero
    (protected_q16_backscan scanned next extra)
    (if extra then 3 else 2) stored target tail
    (protected_q16_backscan_nonempty scanned next extra)
    (protected_q16_backscan_safe scanned next extra Hguard)).
  cbn [run].
  apply q21_protected_direction_mark.
Qed.

(** Full exact native continuation: for every guarded rail, every
    encoded wide program, and all three unconstrained data bits,
    the protected-vault return reaches q19 on the marked-right branch
    or q20 on the marked-left branch after 8n+52 transitions. *)
Theorem q12_protected_second_six_selects_q19_or_q20 :
  forall scanned rows next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 52)
      (entry_config 12
        ([5; 6] ++ 6 :: encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit extra :: source_bit target :: tail))) =
    if extra
    then entry_config 19 (0 :: encode_wide_program rows)
      (7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail)
    else cfg_ml 20 (encode_wide_program rows)
      (0 :: 7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail).
Proof.
  intros scanned rows next extra target tail Hguard.
  replace (8 * length scanned + 52)
    with ((7 * length scanned + 44) + (length scanned + 8))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_second_six_reenters_q16
    scanned rows next extra target tail Hguard).
  replace
    (rev (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2]) ++
     4 :: 7 :: 5 :: 0 ::
     (if extra then 3 else 2) :: encode_wide_program rows)
    with
    (protected_q16_backscan scanned next extra ++
     0 :: (if extra then 3 else 2) :: encode_wide_program rows).
  2:{
    unfold protected_q16_backscan.
    rewrite <- app_assoc.
    reflexivity.
  }
  apply q16_protected_backscan_selects_native_branch.
  exact Hguard.
Qed.

Print Assumptions q12_protected_second_six_selects_q19_or_q20.


(** Independent left-branch vault corruption witness.  Every nonempty
    wide program has a 4 row delimiter immediately followed by a raw
    source bit, even when its current-state bit list is empty. *)
Lemma nonempty_wide_vault_exposes_raw_bit :
  forall row rows,
    exists bit suffix,
      encode_wide_program (row :: rows) =
      4 :: source_bit bit :: suffix.
Proof.
  intros row rows.
  rewrite encode_wide_program_cons.
  unfold encode_wide_row.
  destruct (wr_current row) as [|bit remaining].
  - exists (wr_read row).
    eexists; reflexivity.
  - exists bit.
    eexists; reflexivity.
Qed.

(** q20 passes the row marker 4, then consumes and overwrites the
    *first stored program bit* with 6.  This fact is unconditional over
    the program fields and the surrounding tape. *)
Theorem q20_nonempty_wide_vault_overwrites_program_bit :
  forall row rows rest,
    exists (bit : bool) (suffix : list nat),
      run 2 (cfg_ml 20 (encode_wide_program (row :: rows))
        (0 :: rest)) =
      entry_config (if bit then 18 else 17)
        (6 :: suffix) (4 :: 0 :: rest).
Proof.
  intros row rows rest.
  destruct (nonempty_wide_vault_exposes_raw_bit row rows)
    as [bit [suffix Hshape]].
  rewrite Hshape.
  exists bit, suffix.
  destruct bit; reflexivity.
Qed.

(** The original q12 entry therefore reaches a concrete source-vault
    overwrite in exactly 8n+54 native transitions on the left branch.
    The theorem is existential only in the value of the first encoded
    program bit; it is universal in row contents, tape tail, and rail. *)
Theorem q12_protected_vault_left_branch_overwrites_program_bit :
  forall scanned row rows next target tail,
    q19_q5_roundtrip_railb scanned = true ->
    exists (bit : bool) (suffix : list nat),
      run (8 * length scanned + 54)
        (entry_config 12
          ([5; 6] ++ 6 :: encode_wide_program (row :: rows))
          (0 :: 4 ::
            (scanned ++ source_bit next :: 7 ::
             source_bit false :: source_bit target :: tail))) =
      entry_config (if bit then 18 else 17)
        (6 :: suffix)
        (4 :: 0 :: 7 :: map q16_restore
          (rev (protected_q16_backscan scanned next false)) ++
          source_bit target :: tail).
Proof.
  intros scanned row rows next target tail Hguard.
  replace (8 * length scanned + 54)
    with ((8 * length scanned + 52) + 2) by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_second_six_selects_q19_or_q20
    scanned (row :: rows) next false target tail Hguard).
  destruct (q20_nonempty_wide_vault_overwrites_program_bit
    row rows
    (7 :: map q16_restore
      (rev (protected_q16_backscan scanned next false)) ++
      source_bit target :: tail))
    as [bit [suffix Hoverwrite]].
  exists bit, suffix.
  exact Hoverwrite.
Qed.

Print Assumptions q12_protected_vault_left_branch_overwrites_program_bit.


(** Independent right-branch collision: the q16 restoration maps the
    two 2/3 control marks back to *raw bits*.  Thus q19 sees the old
    [next] mark before the supplied [target] bit. *)
Lemma q16_restore_guarded_scanned_identity :
  forall scanned,
    q19_q5_roundtrip_railb scanned = true ->
    map q16_restore scanned = scanned.
Proof.
  intros scanned Hguard.
  pose proof
    (proj1 (q19_q5_roundtrip_railb_spec scanned) Hguard)
      as Hrail.
  clear Hguard.
  induction Hrail as [|symbol rest Hsymbol Hrest IH].
  - reflexivity.
  - destruct Hsymbol as [-> | [-> | ->]];
      simpl; f_equal; exact IH.
Qed.

Lemma protected_q16_restored_control_shape :
  forall scanned next extra,
    q19_q5_roundtrip_railb scanned = true ->
    map q16_restore
      (rev (protected_q16_backscan scanned next extra)) =
    [5; 7; 4] ++ scanned ++
      [6; source_bit next; source_bit extra].
Proof.
  intros scanned next extra Hguard.
  unfold protected_q16_backscan.
  rewrite rev_app_distr.
  rewrite rev_involutive.
  cbn [rev].
  repeat rewrite map_app.
  rewrite (q16_restore_guarded_scanned_identity scanned Hguard).
  destruct next, extra; reflexivity.
Qed.

Definition protected_q19_control_prefix (scanned : list nat) : list nat :=
  [7; 5; 7; 4] ++ scanned ++ [6].

Lemma protected_q19_control_prefix_length :
  forall scanned,
    length (protected_q19_control_prefix scanned) =
    length scanned + 5.
Proof.
  intro scanned.
  unfold protected_q19_control_prefix.
  repeat rewrite app_length.
  cbn [length].
  lia.
Qed.

Lemma protected_q19_control_prefix_safe :
  forall scanned (next extra : bool),
    q19_q5_roundtrip_railb scanned = true ->
    Forall q15_pass (protected_q19_control_prefix scanned).
Proof.
  intros scanned next extra Hguard.
  pose proof
    (q15_returned_rail_is_safe scanned next extra Hguard)
    as Hrail.
  rewrite Forall_app in Hrail.
  destruct Hrail as [Hscan _].
  unfold protected_q19_control_prefix.
  rewrite Forall_app.
  split.
  - constructor.
    + unfold q15_pass; auto 10.
    + constructor.
      * unfold q15_pass; auto 10.
      * constructor.
        -- unfold q15_pass; auto 10.
        -- constructor.
           ++ unfold q15_pass; auto 10.
           ++ constructor.
  - rewrite Forall_app.
    split.
    + exact Hscan.
    + constructor.
      * unfold q15_pass; auto 10.
      * constructor.
Qed.

Lemma q19_control_frame_exact :
  forall scanned next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    (7 :: map q16_restore
       (rev (protected_q16_backscan scanned next extra)) ++
       source_bit target :: tail) =
    protected_q19_control_prefix scanned ++
      source_bit next :: source_bit extra :: source_bit target :: tail.
Proof.
  intros scanned next extra target tail Hguard.
  rewrite (protected_q16_restored_control_shape
    scanned next extra Hguard).
  unfold protected_q19_control_prefix.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

(** After n+6 additional transitions q19 consumes the *earlier* control
    bit and enters q17/q18.  The intended target remains on the right
    tape: it was never reached. *)
Theorem q19_protected_return_consumes_control_not_target :
  forall scanned stored next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 6)
      (entry_config 19 (0 :: stored)
        (7 :: map q16_restore
          (rev (protected_q16_backscan scanned next extra)) ++
          source_bit target :: tail)) =
    entry_config (if next then 18 else 17)
      (6 :: rev (protected_q19_control_prefix scanned) ++ 0 :: stored)
      (source_bit extra :: source_bit target :: tail).
Proof.
  intros scanned stored next extra target tail Hguard.
  replace (length scanned + 6)
    with (S (length (protected_q19_control_prefix scanned))).
  2:{
    rewrite protected_q19_control_prefix_length.
    lia.
  }
  rewrite (q19_control_frame_exact
    scanned next extra target tail Hguard).
  apply q19_scan_to_m.
  apply (protected_q19_control_prefix_safe scanned next extra).
  exact Hguard.
Qed.

(** In the full protected-vault cycle, the marked-right path reaches
    this wrong raw-bit relocation in exactly 9n+58 native steps. *)
Theorem q12_protected_vault_right_branch_consumes_control_bit :
  forall scanned rows next target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (9 * length scanned + 58)
      (entry_config 12
        ([5; 6] ++ 6 :: encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit true :: source_bit target :: tail))) =
    entry_config (if next then 18 else 17)
      (6 :: rev (protected_q19_control_prefix scanned) ++
       0 :: encode_wide_program rows)
      (source_bit true :: source_bit target :: tail).
Proof.
  intros scanned rows next target tail Hguard.
  replace (9 * length scanned + 58)
    with ((8 * length scanned + 52) + (length scanned + 6))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_second_six_selects_q19_or_q20
    scanned rows next true target tail Hguard).
  apply q19_protected_return_consumes_control_not_target.
  exact Hguard.
Qed.

Print Assumptions q12_protected_vault_right_branch_consumes_control_bit.


(** A stronger layout obstruction independent of the q12 return clock.
    Inserting any finite spacer of q20-passable 2..7 symbols between
    the returned head and an ordinary wide program does not shield the
    program's first raw bit.  q20 passes every spacer cell. *)

Lemma q20_cfg_ml_passable_prefix_to_first_raw :
  forall prefix bit stored rest,
    prefix <> [] ->
    Forall q15_pass prefix ->
    run (S (length prefix))
      (cfg_ml 20 (prefix ++ source_bit bit :: stored) rest) =
    entry_config (if bit then 18 else 17)
      (6 :: stored) (rev prefix ++ rest).
Proof.
  intros [|s remaining] bit stored rest Hnonempty Hpass.
  - contradiction Hnonempty; reflexivity.
  - change
      (run (S (length (s :: remaining)))
        (entry_config 20
          (remaining ++ source_bit bit :: stored) (s :: rest)) =
       entry_config (if bit then 18 else 17)
         (6 :: stored) (rev (s :: remaining) ++ rest)).
    exact (q20_scan_to_m remaining s bit stored rest Hpass).
Qed.

Theorem q20_any_finite_passable_spacer_still_hits_program :
  forall spacer row rows rest,
    Forall q15_pass spacer ->
    exists (bit : bool) (suffix : list nat),
      run (length spacer + 2)
        (cfg_ml 20
          (spacer ++ encode_wide_program (row :: rows))
          (0 :: rest)) =
      entry_config (if bit then 18 else 17)
        (6 :: suffix)
        (rev (spacer ++ [4]) ++ 0 :: rest).
Proof.
  intros spacer row rows rest Hspacer.
  destruct (nonempty_wide_vault_exposes_raw_bit row rows)
    as [bit [suffix Hshape]].
  exists bit, suffix.
  rewrite Hshape.
  replace (length spacer + 2)
    with (S (length (spacer ++ [4]))).
  2:{
    rewrite app_length.
    cbn [length].
    lia.
  }
  replace (spacer ++ 4 :: source_bit bit :: suffix)
    with ((spacer ++ [4]) ++ source_bit bit :: suffix).
  2:{
    rewrite <- app_assoc.
    reflexivity.
  }
  apply q20_cfg_ml_passable_prefix_to_first_raw.
  - destruct spacer; discriminate.
  - rewrite Forall_app.
    split.
    + exact Hspacer.
    + constructor.
      * unfold q15_pass; auto 10.
      * constructor.
Qed.

Print Assumptions q20_any_finite_passable_spacer_still_hits_program.


(** Constructive boundary: unlike a passable spacer, a sacrificial raw
    stop can terminate the q20 scan before it enters the stored wide
    program.  First generalize the already checked return over arbitrary
    stored material, preserving the 23x8 native transition table. *)

Theorem q12_protected_return_to_q15_arbitrary_stored :
  forall scanned stored next extra tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (6 * length scanned + 40)
      (entry_config 12 ([5; 6] ++ 6 :: stored)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 :: source_bit extra :: tail))) =
    entry_config 15
      (4 :: 7 :: 5 :: 0 :: (if extra then 3 else 2) :: stored)
      (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2] ++ tail).
Proof.
  intros scanned stored next extra tail Hguard.
  replace (6 * length scanned + 40)
    with ((6 * length scanned + 32) + 8) by lia.
  rewrite writeback_run_add.
  rewrite (q12_complete_return_with_arbitrary_stored
    scanned (6 :: stored) next extra tail Hguard).
  apply q12q13_protected_six_reopens_q15.
Qed.

Theorem q12_protected_return_to_q16_arbitrary_stored :
  forall scanned stored next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (7 * length scanned + 44)
      (entry_config 12 ([5; 6] ++ 6 :: stored)
        (0 :: 4 ::
         (scanned ++ source_bit next :: 7 ::
          source_bit extra :: source_bit target :: tail))) =
    cfg_ml 16
      (rev (scanned ++
        [6; if next then 3 else 2; if extra then 3 else 2]) ++
       4 :: 7 :: 5 :: 0 ::
       (if extra then 3 else 2) :: stored)
      (source_bit target :: tail).
Proof.
  intros scanned stored next extra target tail Hguard.
  replace (7 * length scanned + 44)
    with ((6 * length scanned + 40) +
          S (length (scanned ++
            [6; if next then 3 else 2; if extra then 3 else 2]))).
  2:{
    rewrite app_length.
    cbn [length].
    lia.
  }
  rewrite writeback_run_add.
  rewrite (q12_protected_return_to_q15_arbitrary_stored
    scanned stored next extra (source_bit target :: tail) Hguard).
  replace
    (scanned ++
     [6; if next then 3 else 2; if extra then 3 else 2] ++
     source_bit target :: tail)
    with
    ((scanned ++
      [6; if next then 3 else 2; if extra then 3 else 2]) ++
      source_bit target :: tail).
  2:{
    rewrite <- app_assoc.
    reflexivity.
  }
  apply q15_scan_to_raw.
  apply q15_returned_rail_is_safe; exact Hguard.
Qed.

Theorem q12_protected_selects_branch_arbitrary_stored :
  forall scanned stored next extra target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 52)
      (entry_config 12 ([5; 6] ++ 6 :: stored)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit extra :: source_bit target :: tail))) =
    if extra
    then entry_config 19 (0 :: stored)
      (7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail)
    else cfg_ml 20 stored
      (0 :: 7 :: map q16_restore
        (rev (protected_q16_backscan scanned next extra)) ++
        source_bit target :: tail).
Proof.
  intros scanned stored next extra target tail Hguard.
  replace (8 * length scanned + 52)
    with ((7 * length scanned + 44) + (length scanned + 8))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_return_to_q16_arbitrary_stored
    scanned stored next extra target tail Hguard).
  replace
    (rev (scanned ++
       [6; if next then 3 else 2; if extra then 3 else 2]) ++
     4 :: 7 :: 5 :: 0 ::
     (if extra then 3 else 2) :: stored)
    with
    (protected_q16_backscan scanned next extra ++
     0 :: (if extra then 3 else 2) :: stored).
  2:{
    unfold protected_q16_backscan.
    rewrite <- app_assoc.
    reflexivity.
  }
  apply q16_protected_backscan_selects_native_branch.
  exact Hguard.
Qed.

(** A sacrificial raw bit is consumed instead of the stored instruction,
    and the encoded program survives unchanged as the tail behind 6.
    This is a ONE-BRANCH, ONE-RETURN prefix property, not a complete
    source-machine instruction simulation. *)
Theorem q12_sacrificial_raw_stop_preserves_left_program :
  forall scanned rows next sacrificial target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 53)
      (entry_config 12
        ([5; 6] ++ 6 :: source_bit sacrificial ::
          encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit false :: source_bit target :: tail))) =
    entry_config (if sacrificial then 18 else 17)
      (6 :: encode_wide_program rows)
      (0 :: 7 :: map q16_restore
        (rev (protected_q16_backscan scanned next false)) ++
        source_bit target :: tail).
Proof.
  intros scanned rows next sacrificial target tail Hguard.
  replace (8 * length scanned + 53)
    with ((8 * length scanned + 52) + 1) by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_selects_branch_arbitrary_stored
    scanned (source_bit sacrificial :: encode_wide_program rows)
    next false target tail Hguard).
  destruct sacrificial; reflexivity.
Qed.

Print Assumptions q12_sacrificial_raw_stop_preserves_left_program.


(** An additional protected Y=5 between the sacrificial raw stop and the
    wide-program vault can terminate the ensuing q5 return before q5
    visits any stored source-row bit.  The following are strictly native
    transition-table results, not a full source-instruction simulation. *)

Theorem q12_sacrificial_stop_arbitrary_suffix :
  forall scanned stored next sacrificial target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 53)
      (entry_config 12
        ([5; 6] ++ 6 :: source_bit sacrificial :: stored)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit false :: source_bit target :: tail))) =
    entry_config (if sacrificial then 18 else 17)
      (6 :: stored)
      (0 :: 7 :: map q16_restore
        (rev (protected_q16_backscan scanned next false)) ++
        source_bit target :: tail).
Proof.
  intros scanned stored next sacrificial target tail Hguard.
  replace (8 * length scanned + 53)
    with ((8 * length scanned + 52) + 1) by lia.
  rewrite writeback_run_add.
  rewrite (q12_protected_selects_branch_arbitrary_stored
    scanned (source_bit sacrificial :: stored)
    next false target tail Hguard).
  destruct sacrificial; reflexivity.
Qed.

Lemma q1718_sacrificial_five_guard_enters_q1 :
  forall (sacrificial : bool) stored tail,
    run 5
      (entry_config (if sacrificial then 18 else 17)
        (6 :: 5 :: stored) (0 :: 7 :: tail)) =
    entry_config 1 (5 :: stored)
      (6 :: 2 :: (if sacrificial then 3 else 2) :: tail).
Proof.
  intros sacrificial stored tail.
  destruct sacrificial; reflexivity.
Qed.

Theorem q12_sacrificial_five_guard_preserves_program_to_q1 :
  forall scanned rows next sacrificial target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 58)
      (entry_config 12
        ([5; 6] ++
         6 :: source_bit sacrificial :: 5 ::
         encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit false :: source_bit target :: tail))) =
    entry_config 1 (5 :: encode_wide_program rows)
      (6 :: 2 :: (if sacrificial then 3 else 2) ::
       map q16_restore
         (rev (protected_q16_backscan scanned next false)) ++
       source_bit target :: tail).
Proof.
  intros scanned rows next sacrificial target tail Hguard.
  replace (8 * length scanned + 58)
    with ((8 * length scanned + 53) + 5) by lia.
  rewrite writeback_run_add.
  rewrite (q12_sacrificial_stop_arbitrary_suffix
    scanned (5 :: encode_wide_program rows)
    next sacrificial target tail Hguard).
  apply q1718_sacrificial_five_guard_enters_q1.
Qed.

Print Assumptions q12_sacrificial_five_guard_preserves_program_to_q1.


(** The protected five guard returns through q1 by two further native
    transitions: q1 reads 6, then 2, writes 0 and enters q0.  The
    stored wide program remains an untouched suffix. *)
Lemma q1_guarded_return_two_steps_to_q0 :
  forall (sacrificial : bool) stored suffix,
    run 2
      (entry_config 1 (5 :: stored)
        (6 :: 2 :: (if sacrificial then 3 else 2) :: suffix)) =
    entry_config 0 (0 :: 6 :: 5 :: stored)
      ((if sacrificial then 3 else 2) :: suffix).
Proof.
  intros sacrificial stored suffix.
  destruct sacrificial; reflexivity.
Qed.

Theorem q12_sacrificial_five_guard_reenters_q0 :
  forall scanned rows next sacrificial target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (8 * length scanned + 60)
      (entry_config 12
        ([5; 6] ++
         6 :: source_bit sacrificial :: 5 ::
         encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit false :: source_bit target :: tail))) =
    entry_config 0 (0 :: 6 :: 5 :: encode_wide_program rows)
      ((if sacrificial then 3 else 2) ::
       map q16_restore
         (rev (protected_q16_backscan scanned next false)) ++
       source_bit target :: tail).
Proof.
  intros scanned rows next sacrificial target tail Hguard.
  replace (8 * length scanned + 60)
    with ((8 * length scanned + 58) + 2) by lia.
  rewrite writeback_run_add.
  rewrite (q12_sacrificial_five_guard_preserves_program_to_q1
    scanned rows next sacrificial target tail Hguard).
  apply q1_guarded_return_two_steps_to_q0.
Qed.

Print Assumptions q12_sacrificial_five_guard_reenters_q0.


(** The backscan restores a forward rail whose NEXT control bit occurs
    before the TARGET source bit.  The following proof identifies exactly
    where the native q0 matcher actually branches; it keeps both q0
    outcomes and the untouched stored-program suffix explicit. *)
Definition q0_protected_prefix (scanned : list nat)
    (sacrificial : bool) : list nat :=
  [if sacrificial then 3 else 2; 5; 7; 4] ++
  map q16_restore scanned ++ [6].

Lemma q0_protected_prefix_length :
  forall scanned sacrificial,
    length (q0_protected_prefix scanned sacrificial) =
      length scanned + 5.
Proof.
  intros scanned sacrificial.
  unfold q0_protected_prefix.
  repeat rewrite app_length.
  rewrite map_length.
  cbn [length].
  lia.
Qed.

Lemma q0_protected_prefix_safe :
  forall scanned sacrificial,
    q19_q5_roundtrip_railb scanned = true ->
    Forall q0_pass (q0_protected_prefix scanned sacrificial).
Proof.
  intros scanned sacrificial Hguard.
  unfold q0_protected_prefix.
  repeat rewrite Forall_app.
  split.
  - destruct sacrificial;
      repeat (constructor; try (unfold q0_pass; auto 12)).
  - split.
    + apply q19_q5_roundtrip_railb_spec in Hguard.
      induction Hguard as [|symbol rest Hsymbol Hrest IH].
      * constructor.
      * constructor.
        -- destruct Hsymbol as [-> | [-> | ->]];
             unfold q0_pass, q16_restore; auto 12.
        -- exact IH.
    + constructor.
      * unfold q0_pass; auto 12.
      * constructor.
Qed.

Lemma q0_protected_restore_forward :
  forall scanned next,
    map q16_restore
      (rev (protected_q16_backscan scanned next false)) =
    [5; 7; 4] ++ map q16_restore scanned ++
      [6; source_bit next; 0].
Proof.
  intros scanned next.
  destruct next;
    unfold protected_q16_backscan;
    rewrite rev_app_distr;
    rewrite rev_involutive;
    repeat rewrite map_app;
    simpl;
    reflexivity.
Qed.

Lemma q0_protected_restored_tape_shape :
  forall (scanned : list nat) (next sacrificial target : bool)
         (tail : list nat),
    (if sacrificial then 3 else 2) ::
      map q16_restore
        (rev (protected_q16_backscan scanned next false)) ++
      source_bit target :: tail =
    q0_protected_prefix scanned sacrificial ++
      source_bit next :: 0 :: source_bit target :: tail.
Proof.
  intros scanned next sacrificial target tail.
  rewrite q0_protected_restore_forward.
  unfold q0_protected_prefix.
  simpl.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Theorem q0_protected_dispatches_next_before_target :
  forall scanned next sacrificial stored target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 6)
      (entry_config 0 (0 :: 6 :: 5 :: stored)
        (q0_protected_prefix scanned sacrificial ++
         source_bit next :: 0 :: source_bit target :: tail)) =
    if next
    then entry_config 3
      (3 :: rev (q0_protected_prefix scanned sacrificial) ++
       0 :: 6 :: 5 :: stored)
      (0 :: source_bit target :: tail)
    else cfg_ml 2
      (rev (q0_protected_prefix scanned sacrificial) ++
       0 :: 6 :: 5 :: stored)
      (2 :: 0 :: source_bit target :: tail).
Proof.
  intros scanned next sacrificial stored target tail Hguard.
  replace (length scanned + 6)
    with (S (length (q0_protected_prefix scanned sacrificial))).
  2:{ rewrite q0_protected_prefix_length; lia. }
  destruct next.
  - apply q0_scan_one.
    apply q0_protected_prefix_safe; exact Hguard.
  - apply q0_scan_zero.
    apply q0_protected_prefix_safe; exact Hguard.
Qed.

Theorem q12_sacrificial_guard_dispatches_early_next :
  forall scanned rows next sacrificial target tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (9 * length scanned + 66)
      (entry_config 12
        ([5; 6] ++
         6 :: source_bit sacrificial :: 5 ::
         encode_wide_program rows)
        (0 :: 4 ::
          (scanned ++ source_bit next :: 7 ::
           source_bit false :: source_bit target :: tail))) =
    if next
    then entry_config 3
      (3 :: rev (q0_protected_prefix scanned sacrificial) ++
       0 :: 6 :: 5 :: encode_wide_program rows)
      (0 :: source_bit target :: tail)
    else cfg_ml 2
      (rev (q0_protected_prefix scanned sacrificial) ++
       0 :: 6 :: 5 :: encode_wide_program rows)
      (2 :: 0 :: source_bit target :: tail).
Proof.
  intros scanned rows next sacrificial target tail Hguard.
  replace (9 * length scanned + 66)
    with ((8 * length scanned + 60) + (length scanned + 6))
    by lia.
  rewrite writeback_run_add.
  rewrite (q12_sacrificial_five_guard_reenters_q0
    scanned rows next sacrificial target tail Hguard).
  rewrite (q0_protected_restored_tape_shape
    scanned next sacrificial target tail).
  apply q0_protected_dispatches_next_before_target.
  exact Hguard.
Qed.

Print Assumptions q12_sacrificial_guard_dispatches_early_next.


(** A general no-passable-spacer principle for the q0 read phase.
    Regardless of the finite passable prefix, q0 dispatches at the first
    raw next/control bit.  Any later raw target remains in the tape.
    This is a literal table theorem, independent of the protected-vault
    special case. *)
Theorem q0_any_finite_passable_spacer_still_reads_first_raw :
  forall (spacer : list nat) (next target : bool)
         (left tail : list nat),
    Forall q0_pass spacer ->
    run (S (length spacer))
      (entry_config 0 left
        (spacer ++ source_bit next :: source_bit target :: tail)) =
    if next
    then entry_config 3
      (3 :: rev spacer ++ left)
      (source_bit target :: tail)
    else cfg_ml 2 (rev spacer ++ left)
      (2 :: source_bit target :: tail).
Proof.
  intros spacer next target left tail Hpass.
  destruct next.
  - apply q0_scan_one; exact Hpass.
  - apply q0_scan_zero; exact Hpass.
Qed.

Print Assumptions q0_any_finite_passable_spacer_still_reads_first_raw.


(** A constructive q0-LOCAL replacement for the failed raw-control rail:
    store BOTH control bits in q0-passable, q16-stable symbols 6/7.
    This changes the proposed entry layout, not the frozen machine.
    It proves the q0 target dispatch once this entry configuration is
    supplied, but does NOT prove that the earlier q12/q16 cycle creates it. *)
Definition q0_stable_control_tag (b : bool) : nat :=
  if b then 7 else 6.

Lemma q0_stable_control_tag_pass :
  forall b, q0_pass (q0_stable_control_tag b).
Proof.
  intros []; unfold q0_pass, q0_stable_control_tag; auto 12.
Qed.

Lemma q0_two_stable_control_tags_pass :
  forall next extra,
    Forall q0_pass
      [q0_stable_control_tag next; q0_stable_control_tag extra].
Proof.
  intros next extra.
  constructor.
  - apply q0_stable_control_tag_pass.
  - constructor.
    + apply q0_stable_control_tag_pass.
    + constructor.
Qed.

Theorem q0_tagged_control_pair_dispatches_target :
  forall (prefix left tail : list nat) (next extra target : bool),
    Forall q0_pass prefix ->
    run (length prefix + 3)
      (entry_config 0 left
        (prefix ++
         [q0_stable_control_tag next;
          q0_stable_control_tag extra] ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (prefix ++
        [q0_stable_control_tag next;
         q0_stable_control_tag extra]) ++ left) tail
    else cfg_ml 2
      (rev (prefix ++
        [q0_stable_control_tag next;
         q0_stable_control_tag extra]) ++ left) (2 :: tail).
Proof.
  intros prefix left tail next extra target Hprefix.
  assert (Htagged :
    Forall q0_pass
      (prefix ++
       [q0_stable_control_tag next;
        q0_stable_control_tag extra])).
  {
    rewrite Forall_app.
    split.
    - exact Hprefix.
    - apply q0_two_stable_control_tags_pass.
  }
  replace (length prefix + 3)
    with (S (length
      (prefix ++
       [q0_stable_control_tag next;
        q0_stable_control_tag extra]))).
  2:{ rewrite app_length. cbn [length]. lia. }
  rewrite app_assoc.
  destruct target.
  - apply q0_scan_one; exact Htagged.
  - apply q0_scan_zero; exact Htagged.
Qed.

Theorem q0_protected_prefix_with_tagged_controls_reads_target :
  forall scanned sacrificial next extra target stored tail,
    q19_q5_roundtrip_railb scanned = true ->
    run (length scanned + 8)
      (entry_config 0 (0 :: 6 :: 5 :: stored)
        (q0_protected_prefix scanned sacrificial ++
         [q0_stable_control_tag next;
          q0_stable_control_tag extra] ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (q0_protected_prefix scanned sacrificial ++
        [q0_stable_control_tag next;
         q0_stable_control_tag extra]) ++
       0 :: 6 :: 5 :: stored) tail
    else cfg_ml 2
      (rev (q0_protected_prefix scanned sacrificial ++
        [q0_stable_control_tag next;
         q0_stable_control_tag extra]) ++
       0 :: 6 :: 5 :: stored) (2 :: tail).
Proof.
  intros scanned sacrificial next extra target stored tail Hguard.
  replace (length scanned + 8)
    with (length (q0_protected_prefix scanned sacrificial) + 3).
  2:{ rewrite q0_protected_prefix_length; lia. }
  apply q0_tagged_control_pair_dispatches_target.
  apply q0_protected_prefix_safe; exact Hguard.
Qed.

Print Assumptions q0_protected_prefix_with_tagged_controls_reads_target.


(** Upstream-compatible local property: q16 scans arbitrary finite
    6/7-tagged control rails without rewriting their information.
    The final transition to q21/q22 still depends on a separate raw
    delimiter to the left.  This does not establish that q12 can
    construct the tagged rail, nor a whole-instruction simulation. *)
Lemma q16_stable_control_tag_pass :
  forall b, q16_pass (q0_stable_control_tag b).
Proof.
  intros []; unfold q16_pass, q0_stable_control_tag; auto 12.
Qed.

Lemma q16_stable_control_rail_safe :
  forall bits,
    Forall q16_pass (map q0_stable_control_tag bits).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - constructor.
    + apply q16_stable_control_tag_pass.
    + exact IH.
Qed.

Lemma q16_stable_control_tag_restore :
  forall b,
    q16_restore (q0_stable_control_tag b) =
    q0_stable_control_tag b.
Proof.
  intros []; reflexivity.
Qed.

Theorem q16_stable_control_rail_restore_identity :
  forall bits,
    map q16_restore (map q0_stable_control_tag bits) =
    map q0_stable_control_tag bits.
Proof.
  induction bits as [|b rest IH].
  - reflexivity.
  - simpl.
    rewrite q16_stable_control_tag_restore.
    rewrite IH.
    reflexivity.
Qed.

Lemma q16_stable_control_rail_reverse_restore :
  forall bits,
    map q16_restore (rev (map q0_stable_control_tag bits)) =
    rev (map q0_stable_control_tag bits).
Proof.
  intro bits.
  rewrite map_rev.
  rewrite q16_stable_control_rail_restore_identity.
  reflexivity.
Qed.

Theorem q16_native_tagged_backscan_preserves_control_rail :
  forall (first : bool) (rest : list bool)
         (old : bool) (left suffix : list nat),
    run (S (length
      (q0_stable_control_tag first ::
       map q0_stable_control_tag rest)))
      (entry_config 16
        (map q0_stable_control_tag rest ++
         source_bit old :: left)
        (q0_stable_control_tag first :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: rev (map q0_stable_control_tag (first :: rest)) ++
       suffix).
Proof.
  intros first rest old left suffix.
  rewrite (q16_restore_to_raw
    (map q0_stable_control_tag rest)
    (q0_stable_control_tag first)
    old left suffix).
  - rewrite map_rev.
    cbn [map].
    rewrite q16_stable_control_tag_restore.
    rewrite q16_stable_control_rail_restore_identity.
    reflexivity.
  - constructor.
    + apply q16_stable_control_tag_pass.
    + apply q16_stable_control_rail_safe.
Qed.

Print Assumptions q16_native_tagged_backscan_preserves_control_rail.


(** Exact adjacent q15/q16 native roundtrip on a tagged control rail.
    The tagged rail is supplied as the starting configuration; this
    theorem does not assert that q12 constructs it.  q15 sees the
    target raw bit at the right end, and q16 reaches the old raw bit
    on the left without erasing the stable 6/7 control information. *)
Lemma q15_stable_control_tag_pass :
  forall b, q15_pass (q0_stable_control_tag b).
Proof.
  intros []; unfold q15_pass, q0_stable_control_tag; auto 12.
Qed.

Lemma q15_stable_control_rail_reverse_safe :
  forall bits,
    Forall q15_pass (rev (map q0_stable_control_tag bits)).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - cbn [map rev].
    rewrite Forall_app.
    split.
    + exact IH.
    + constructor.
      * apply q15_stable_control_tag_pass.
      * constructor.
Qed.

Theorem q15_q16_native_tagged_control_rail_roundtrip :
  forall (first : bool) (rest : list bool)
         (old target : bool) (left suffix : list nat),
    run (S (length (rev
           (map q0_stable_control_tag (first :: rest)))) +
         S (length
           (map q0_stable_control_tag (first :: rest))))
      (entry_config 15 (source_bit old :: left)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit target :: suffix).
Proof.
  intros first rest old target left suffix.
  rewrite writeback_run_add.
  rewrite (q15_scan_to_raw
    (rev (map q0_stable_control_tag (first :: rest)))
    target (source_bit old :: left) suffix).
  2:{ apply q15_stable_control_rail_reverse_safe. }
  rewrite rev_involutive.
  change (run (S (length
      (q0_stable_control_tag first ::
       map q0_stable_control_tag rest)))
    (entry_config 16
      (map q0_stable_control_tag rest ++
       source_bit old :: left)
      (q0_stable_control_tag first ::
       source_bit target :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit target :: suffix)).
  apply q16_native_tagged_backscan_preserves_control_rail.
Qed.

Print Assumptions q15_q16_native_tagged_control_rail_roundtrip.


(** The tagged rail also passes through the certified q21/q22
    direction-selection phase.  Both directional outcomes are stated;
    the tag-rail preservation follows from its 6/7 restore identity. *)
Theorem tagged_rail_q15_q22_right_to_q19 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (direction_phase_cost
      (map q0_stable_control_tag (first :: rest))
      (dir_head :: dir_remaining))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit target :: suffix).
Proof.
  intros first rest dir_head dir_remaining old target outer suffix H21.
  eapply eq_trans.
  - apply (q15_q22_right_to_q19
      (q0_stable_control_tag first)
      (map q0_stable_control_tag rest)
      dir_head dir_remaining old target outer suffix).
    + change (Forall q15_pass
        (rev (map q0_stable_control_tag (first :: rest)))).
      apply q15_stable_control_rail_reverse_safe.
    + constructor.
      * apply q16_stable_control_tag_pass.
      * apply q16_stable_control_rail_safe.
    + exact H21.
  - rewrite map_rev.
    cbn [map].
    rewrite q16_stable_control_tag_restore.
    rewrite q16_stable_control_rail_restore_identity.
    reflexivity.
Qed.

Theorem tagged_rail_q15_q22_left_to_q20 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old next target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (direction_phase_cost
      (map q0_stable_control_tag (first :: rest))
      (dir_head :: dir_remaining))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit next :: suffix).
Proof.
  intros first rest dir_head dir_remaining old next target outer suffix H21.
  eapply eq_trans.
  - apply (q15_q22_left_to_q20
      (q0_stable_control_tag first)
      (map q0_stable_control_tag rest)
      dir_head dir_remaining old next target outer suffix).
    + change (Forall q15_pass
        (rev (map q0_stable_control_tag (first :: rest)))).
      apply q15_stable_control_rail_reverse_safe.
    + constructor.
      * apply q16_stable_control_tag_pass.
      * apply q16_stable_control_rail_safe.
    + exact H21.
  - rewrite map_rev.
    cbn [map].
    rewrite q16_stable_control_tag_restore.
    rewrite q16_stable_control_rail_restore_identity.
    reflexivity.
Qed.

Print Assumptions tagged_rail_q15_q22_right_to_q19.
Print Assumptions tagged_rail_q15_q22_left_to_q20.


(** At the relocation stage, every stable 6/7 tag remains q19-passable.
    The q19 hypothesis on the direction rail must be stated separately:
    q21 may pass raw 0/1 controls that would stop q19 too early. *)
Lemma q16_tagged_scan_restore_cons :
  forall (first : bool) (rest : list bool),
    map q16_restore
      (rev (q0_stable_control_tag first ::
            map q0_stable_control_tag rest)) =
    rev (map q0_stable_control_tag (first :: rest)).
Proof.
  intros first rest.
  rewrite map_rev.
  cbn [map].
  rewrite q16_stable_control_tag_restore.
  rewrite q16_stable_control_rail_restore_identity.
  reflexivity.
Qed.

Theorem tagged_rail_right_relocates_to_q5 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target outer between final,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    run (direction_phase_cost
           (map q0_stable_control_tag (first :: rest))
           (dir_head :: dir_remaining) +
         (S (length
           (rev (dir_head :: dir_remaining) ++
            7 :: rev (map q0_stable_control_tag (first :: rest)))) +
          S (length between)))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 :: final)) =
    cfg_ml 5
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++
            7 :: rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit old :: outer)
      ((if target then 3 else 2) :: final).
Proof.
  intros first rest dir_head dir_remaining old target outer between final
    H21 Hdir Hbetween.
  replace
    (rev (dir_head :: dir_remaining) ++
     7 :: rev (map q0_stable_control_tag (first :: rest)))
    with
    (rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore
       (rev (q0_stable_control_tag first ::
             map q0_stable_control_tag rest))).
  2:{ rewrite q16_tagged_scan_restore_cons. reflexivity. }
  apply (q15_q22_right_relocates_to_q5
      (q0_stable_control_tag first)
      (map q0_stable_control_tag rest)
      dir_head dir_remaining old target outer between final).
    + change (Forall q15_pass
        (rev (map q0_stable_control_tag (first :: rest)))).
      apply q15_stable_control_rail_reverse_safe.
    + constructor.
      * apply q16_stable_control_tag_pass.
      * apply q16_stable_control_rail_safe.
    + exact H21.
    + rewrite q16_tagged_scan_restore_cons.
      rewrite Forall_app.
      split.
      * exact Hdir.
      * constructor.
        -- unfold q15_pass; auto 12.
        -- apply q15_stable_control_rail_reverse_safe.
    + exact Hbetween.
Qed.

Theorem tagged_rail_left_relocates_to_q5 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old next target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass (rev (dir_head :: dir_remaining)) ->
    run (direction_phase_cost
           (map q0_stable_control_tag (first :: rest))
           (dir_head :: dir_remaining) +
         (1 + S (length
           (source_bit old :: rev (dir_head :: dir_remaining)))))
      (entry_config 15
        (source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit next :: suffix)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit next :: suffix).
Proof.
  intros first rest dir_head dir_remaining old next target outer suffix
    H21 Hreturn.
  eapply eq_trans.
  - apply (q15_q22_left_relocates_to_q5
      (q0_stable_control_tag first)
      (map q0_stable_control_tag rest)
      dir_head dir_remaining old next target outer suffix).
    + change (Forall q15_pass
        (rev (map q0_stable_control_tag (first :: rest)))).
      apply q15_stable_control_rail_reverse_safe.
    + constructor.
      * apply q16_stable_control_tag_pass.
      * apply q16_stable_control_rail_safe.
    + exact H21.
    + exact Hreturn.
  - rewrite q16_tagged_scan_restore_cons.
    reflexivity.
Qed.

Print Assumptions tagged_rail_right_relocates_to_q5.
Print Assumptions tagged_rail_left_relocates_to_q5.


(** Closing the local tag-preservation audit at q5.  This theorem
    requires the distinguished left-side 5 delimiter and begins in q5;
    it does not assert that the preceding q19/q20 branches produce this
    exact zipper shape for a complete encoded instruction. *)
Lemma q5_stable_control_tag_pass :
  forall b, q5_return_pass (q0_stable_control_tag b).
Proof.
  intros []; unfold q5_return_pass, q0_stable_control_tag; auto 12.
Qed.

Lemma q5_stable_control_rail_safe :
  forall bits,
    Forall q5_return_pass (map q0_stable_control_tag bits).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - constructor.
    + apply q5_stable_control_tag_pass.
    + exact IH.
Qed.

Lemma q5_stable_control_tag_restore :
  forall b,
    entry_rewrite (q0_stable_control_tag b) =
    q0_stable_control_tag b.
Proof.
  intros []; reflexivity.
Qed.

Lemma q5_stable_control_rail_restore_identity :
  forall bits,
    map entry_rewrite (map q0_stable_control_tag bits) =
    map q0_stable_control_tag bits.
Proof.
  induction bits as [|b rest IH].
  - reflexivity.
  - simpl.
    rewrite q5_stable_control_tag_restore.
    rewrite IH.
    reflexivity.
Qed.

Theorem q5_native_tagged_return_preserves_control_rail :
  forall (first : bool) (rest : list bool)
         (prefix suffix : list nat),
    run (S (length
      (q0_stable_control_tag first ::
       map q0_stable_control_tag rest)))
      (entry_config 5
        (map q0_stable_control_tag rest ++ 5 :: prefix)
        (q0_stable_control_tag first :: suffix)) =
    entry_config 1 (5 :: prefix)
      (rev (map q0_stable_control_tag (first :: rest)) ++ suffix).
Proof.
  intros first rest prefix suffix.
  rewrite (q5_return_scan_to_first_five
    (map q0_stable_control_tag rest)
    (q0_stable_control_tag first) prefix suffix).
  - rewrite map_rev.
    cbn [map].
    rewrite q5_stable_control_tag_restore.
    rewrite q5_stable_control_rail_restore_identity.
    reflexivity.
  - constructor.
    + apply q5_stable_control_tag_pass.
    + apply q5_stable_control_rail_safe.
Qed.

Print Assumptions q5_native_tagged_return_preserves_control_rail.


(** q1, too, copies 6/7 tags while moving right.  Hence the tagged
    rail emitted by the preceding q5 return can be traversed by q1
    before it encounters the explicit 6,2 return gate. *)
Definition q1_tagged_pass (symbol : nat) : Prop :=
  symbol = 6 \/ symbol = 7.

Lemma q1_tagged_pass_step :
  forall symbol left suffix,
    q1_tagged_pass symbol ->
    step (entry_config 1 left (symbol :: suffix)) =
    entry_config 1 (symbol :: left) suffix.
Proof.
  intros symbol left suffix [-> | ->]; reflexivity.
Qed.

Theorem q1_scan_tagged_rail :
  forall scanned left suffix,
    Forall q1_tagged_pass scanned ->
    run (length scanned)
      (entry_config 1 left (scanned ++ suffix)) =
    entry_config 1 (rev scanned ++ left) suffix.
Proof.
  induction scanned as [|symbol rest IH];
    intros left suffix Hsafe.
  - reflexivity.
  - inversion Hsafe as [|? ? Hsymbol Hrest]; subst.
    change (run (length rest)
      (step (entry_config 1 left
        (symbol :: rest ++ suffix))) =
      entry_config 1 (rev (symbol :: rest) ++ left) suffix).
    rewrite (q1_tagged_pass_step symbol left
      (rest ++ suffix) Hsymbol).
    rewrite (IH (symbol :: left) suffix Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) symbol left).
    reflexivity.
Qed.

Lemma q1_stable_control_tag_pass :
  forall b, q1_tagged_pass (q0_stable_control_tag b).
Proof.
  intros []; unfold q1_tagged_pass, q0_stable_control_tag; auto.
Qed.

Lemma q1_stable_control_rail_reverse_safe :
  forall bits,
    Forall q1_tagged_pass
      (rev (map q0_stable_control_tag bits)).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - cbn [map rev].
    rewrite Forall_app.
    split.
    + exact IH.
    + constructor.
      * apply q1_stable_control_tag_pass.
      * constructor.
Qed.

Theorem q5_q1_native_tagged_return_reenters_q0 :
  forall (first : bool) (rest : list bool)
         (sacrificial : bool) (stored suffix : list nat),
    run (S (length (map q0_stable_control_tag (first :: rest))) +
         (length (map q0_stable_control_tag (first :: rest)) + 2))
      (entry_config 5
        (map q0_stable_control_tag rest ++ 5 :: stored)
        (q0_stable_control_tag first ::
         6 :: 2 :: (if sacrificial then 3 else 2) :: suffix)) =
    entry_config 0
      (0 :: 6 :: map q0_stable_control_tag (first :: rest) ++
       5 :: stored)
      ((if sacrificial then 3 else 2) :: suffix).
Proof.
  intros first rest sacrificial stored suffix.
  rewrite writeback_run_add.
  replace (S (length
    (map q0_stable_control_tag (first :: rest))))
    with (S (length
      (q0_stable_control_tag first ::
       map q0_stable_control_tag rest))) by reflexivity.
  rewrite (q5_native_tagged_return_preserves_control_rail
    first rest stored
    (6 :: 2 :: (if sacrificial then 3 else 2) :: suffix)).
  rewrite writeback_run_add.
  replace (length (map q0_stable_control_tag (first :: rest)))
    with (length (rev (map q0_stable_control_tag (first :: rest)))).
  2:{ rewrite rev_length. reflexivity. }
  rewrite (q1_scan_tagged_rail
    (rev (map q0_stable_control_tag (first :: rest)))
    (5 :: stored)
    (6 :: 2 :: (if sacrificial then 3 else 2) :: suffix)).
  2:{ apply q1_stable_control_rail_reverse_safe. }
  rewrite rev_involutive.
  destruct sacrificial; reflexivity.
Qed.

Print Assumptions q5_q1_native_tagged_return_reenters_q0.


(** Conditional end-to-end return/dispatch from an explicit q5 entry:
    q5 restores a 6/7 rail, q1 traverses it and exits through 6,2,
    and q0 passes the displacement mark and BOTH stable control tags
    before reading the intended raw target.  Neither branch claims
    upstream reachability from canonical q12. *)
Theorem q5_q1_q0_native_tagged_target_dispatch :
  forall (first : bool) (rest : list bool)
         (sacrificial next extra target : bool)
         (stored tail : list nat),
    run ((S (length (map q0_stable_control_tag (first :: rest))) +
          (length (map q0_stable_control_tag (first :: rest)) + 2)) + 4)
      (entry_config 5
        (map q0_stable_control_tag rest ++ 5 :: stored)
        (q0_stable_control_tag first ::
         6 :: 2 :: (if sacrificial then 3 else 2) ::
         q0_stable_control_tag next ::
         q0_stable_control_tag extra ::
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev
        ([if sacrificial then 3 else 2] ++
         [q0_stable_control_tag next; q0_stable_control_tag extra]) ++
       0 :: 6 :: map q0_stable_control_tag (first :: rest) ++
       5 :: stored) tail
    else cfg_ml 2
      (rev
        ([if sacrificial then 3 else 2] ++
         [q0_stable_control_tag next; q0_stable_control_tag extra]) ++
       0 :: 6 :: map q0_stable_control_tag (first :: rest) ++
       5 :: stored) (2 :: tail).
Proof.
  intros first rest sacrificial next extra target stored tail.
  rewrite writeback_run_add.
  rewrite (q5_q1_native_tagged_return_reenters_q0
    first rest sacrificial stored
    (q0_stable_control_tag next ::
     q0_stable_control_tag extra ::
     source_bit target :: tail)).
  replace 4
    with (length [if sacrificial then 3 else 2] + 3)
    by reflexivity.
  rewrite (q0_tagged_control_pair_dispatches_target
    [if sacrificial then 3 else 2]
    (0 :: 6 :: map q0_stable_control_tag (first :: rest) ++
     5 :: stored)
    tail next extra target).
  2:{
    constructor.
    - destruct sacrificial; unfold q0_pass; auto 12.
    - constructor.
  }
  reflexivity.
Qed.

Print Assumptions q5_q1_q0_native_tagged_target_dispatch.
