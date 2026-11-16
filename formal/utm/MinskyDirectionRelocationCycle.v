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

From Coq Require Import List Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyWritebackMacro
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
