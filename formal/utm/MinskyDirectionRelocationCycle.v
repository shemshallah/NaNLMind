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

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyWritebackMacro
  MinskyHeadMoveMacro MinskyDirectionDecision MinskyRelocationMacro.

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
  change (run (S (length (s :: remaining)) +
                  S (length (dir_head :: dir_remaining)))
    (entry_config 16
      (remaining ++ source_bit old ::
        dir_head :: dir_remaining ++ 3 :: outer)
      (s :: source_bit next :: suffix)) = _).
  rewrite writeback_run_add.
  rewrite (q16_restore_to_raw remaining s old
    (dir_head :: dir_remaining ++ 3 :: outer)
    (source_bit next :: suffix) H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head :: 7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix)) = _).
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
  change (run (S (length (s :: remaining)) +
                  S (length (dir_head :: dir_remaining)))
    (entry_config 16
      (remaining ++ source_bit old ::
        dir_head :: dir_remaining ++
        2 :: source_bit target :: outer)
      (s :: source_bit next :: suffix)) = _).
  rewrite writeback_run_add.
  rewrite (q16_restore_to_raw remaining s old
    (dir_head :: dir_remaining ++ 2 :: source_bit target :: outer)
    (source_bit next :: suffix) H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 2 :: source_bit target :: outer)
      (dir_head :: 7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix)) = _).
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
  2:{ rewrite app_assoc. reflexivity. }
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
  change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix))) = _).
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (s :: remaining)) ++
     source_bit next :: suffix)).
  destruct target.
  - rewrite (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix) Hreturn').
    reflexivity.
  - rewrite (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (s :: remaining)) ++
       source_bit next :: suffix) Hreturn').
    reflexivity.
Qed.

Print Assumptions q15_q22_right_to_q19.
Print Assumptions q15_q22_left_to_q20.
Print Assumptions q15_q22_right_relocates_to_q5.
Print Assumptions q15_q22_left_relocates_to_q5.
