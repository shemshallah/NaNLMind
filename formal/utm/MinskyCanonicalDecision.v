(** * Canonical q16 decision through q21/q22 to q19/q20

    The restore phase leaves a q16 frame whose left tape is the q15
    backscan, X=4, the raw old direction bit and the stored direction
    markers.  q16 restores the backscan, writes 7 at the raw bit and
    selects q21/q22; q21/q22 then scan left to the direction marker and
    select q19 (marker 3, right) or q20 (marker 2, left).

    These are macro compositions over exact native-table runs.  No
    complete source-step theorem is claimed here.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyConcreteDispatch MinskyMatchMacro
  MinskyHeadMoveMacro MinskyDirectionDecision MinskyWritebackMacro
  MinskyRelocationMacro MinskyCanonicalRestore.

Lemma q16_pass_two : q16_pass 2.
Proof. unfold q16_pass; auto. Qed.

Lemma q16_pass_three : q16_pass 3.
Proof. unfold q16_pass; auto 10. Qed.

(** Marker 3 means right: q21/q22 enters q19. *)
Theorem canonical_q16_decision_to_q19 :
  forall m marked old dir_head dir_remaining outer bit tail,
    q16_pass m ->
    Forall q16_pass marked ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (m :: rev marked ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (cfg_ml 16
        (rev (marked ++ [m]) ++ 4 ::
         source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (source_bit bit :: tail)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros m marked old dir_head dir_remaining outer bit tail
    Hm Hmarked Hdir.
  rewrite dispatch_run_add.
  rewrite (canonical_restore_q16_decision m marked old
    (dir_head :: dir_remaining ++ 3 :: outer) bit tail Hm Hmarked).
  cbn [cfg_ml].
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite (q21_scan_to_right_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: tail) Hq Hdir).
  destruct old; reflexivity.
Qed.

(** Marker 2 means left: q21/q22 enters q20. *)
Theorem canonical_q16_decision_to_q20 :
  forall m marked old dir_head dir_remaining outer bit tail,
    q16_pass m ->
    Forall q16_pass marked ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (m :: rev marked ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (cfg_ml 16
        (rev (marked ++ [m]) ++ 4 ::
         source_bit old :: dir_head :: dir_remaining ++ 2 :: outer)
        (source_bit bit :: tail)) =
    cfg_ml 20 outer
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros m marked old dir_head dir_remaining outer bit tail
    Hm Hmarked Hdir.
  rewrite dispatch_run_add.
  rewrite (canonical_restore_q16_decision m marked old
    (dir_head :: dir_remaining ++ 2 :: outer) bit tail Hm Hmarked).
  cbn [cfg_ml].
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite (q21_scan_to_left_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: tail) Hq Hdir).
  destruct old; reflexivity.
Qed.

Print Assumptions canonical_q16_decision_to_q19.
Print Assumptions canonical_q16_decision_to_q20.

(** The restore frame's last record mark is [match_mark b]; q14 restores
    it to the raw bit [source_bit b], which is exactly the decision bit q16
    writes as 7 before selecting q21/q22.  This closes q12 directly onto the
    decision phase. *)
Corollary canonical_q12_restore_to_q16_decision :
  forall marked tbuffer data (b : bool) rest bit tail,
    Forall q12_pass (match_mark b :: rest ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev rest ++ [match_mark b]) ->
    Forall q15_pass (marked ++ [2]) ->
    Forall q16_pass marked ->
    run (S (length (match_mark b :: rest ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev rest ++ [match_mark b])) +
         S (length (marked ++ [2])) +
         S (length (2 :: rev marked ++ [4])))
      (cfg_ml 12
        (match_mark b :: rest ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 2 :: source_bit bit :: tail)) =
    cfg_ml (if b then 22 else 21)
      (map q14_restore (rest ++ 5 :: rev tbuffer) ++ 3 :: rev data)
      (7 :: map q16_restore (rev (2 :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros marked tbuffer data b rest bit tail H12 H14 H15 Hmarked.
  rewrite dispatch_run_add.
  rewrite (canonical_restore_q12_q15_capture (match_mark b) rest
    tbuffer data marked bit tail H12 H14 H15).
  assert (Hrev :
    rev (tbuffer ++ [5] ++ rev rest ++ [match_mark b]) =
    match_mark b :: rest ++ 5 :: rev tbuffer).
  { rewrite <- (rev_restore_scan (match_mark b) rest tbuffer).
    rewrite rev_involutive. reflexivity. }
  rewrite Hrev.
  replace (map q14_restore
      (match_mark b :: rest ++ 5 :: rev tbuffer))
    with (source_bit b ::
      map q14_restore (rest ++ 5 :: rev tbuffer))
    by (destruct b; reflexivity).
  apply (canonical_restore_q16_decision 2 marked b
    (map q14_restore (rest ++ 5 :: rev tbuffer) ++ 3 :: rev data)
    bit tail q16_pass_two Hmarked).
Qed.

(** The q13 branch is identical with direction mark 3 and trailing 2. *)
Corollary canonical_q13_restore_to_q16_decision :
  forall marked tbuffer data (b : bool) rest bit tail,
    Forall q12_pass (match_mark b :: rest ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev rest ++ [match_mark b]) ->
    Forall q15_pass (marked ++ [3]) ->
    Forall q16_pass marked ->
    run (S (length (match_mark b :: rest ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev rest ++ [match_mark b])) +
         S (length (marked ++ [3])) +
         S (length (3 :: rev marked ++ [4])))
      (cfg_ml 13
        (match_mark b :: rest ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: source_bit bit :: tail)) =
    cfg_ml (if b then 22 else 21)
      (map q14_restore (rest ++ 5 :: rev tbuffer) ++ 2 :: rev data)
      (7 :: map q16_restore (rev (3 :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros marked tbuffer data b rest bit tail H13 H14 H15 Hmarked.
  rewrite dispatch_run_add.
  rewrite (canonical_restore_q13_q15_capture (match_mark b) rest
    tbuffer data marked bit tail H13 H14 H15).
  assert (Hrev :
    rev (tbuffer ++ [5] ++ rev rest ++ [match_mark b]) =
    match_mark b :: rest ++ 5 :: rev tbuffer).
  { rewrite <- (rev_restore_scan (match_mark b) rest tbuffer).
    rewrite rev_involutive. reflexivity. }
  rewrite Hrev.
  replace (map q14_restore
      (match_mark b :: rest ++ 5 :: rev tbuffer))
    with (source_bit b ::
      map q14_restore (rest ++ 5 :: rev tbuffer))
    by (destruct b; reflexivity).
  apply (canonical_restore_q16_decision 3 marked b
    (map q14_restore (rest ++ 5 :: rev tbuffer) ++ 2 :: rev data)
    bit tail q16_pass_three Hmarked).
Qed.

Print Assumptions canonical_q12_restore_to_q16_decision.
Print Assumptions canonical_q13_restore_to_q16_decision.

(** Rightward relocation: q19 scans the restored marker block and the
    7 written by q16, displaces the next raw record bit by 6, and q17/q18
    return to a following 7 marker in q5. *)
Theorem canonical_q16_decision_right_to_q5 :
  forall m marked old dir_head dir_remaining outer between bit final,
    q16_pass m ->
    Forall q16_pass marked ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (m :: rev marked ++ [4]))) ->
    Forall q17_pass between ->
    run ((S (length (m :: rev marked ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (S (length
            (rev (dir_head :: dir_remaining) ++
             7 :: map q16_restore (rev (m :: rev marked ++ [4])))) +
          S (length between)))
      (cfg_ml 16
        (rev (marked ++ [m]) ++ 4 ::
         source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (source_bit bit :: between ++ 7 :: final)) =
    cfg_ml 5
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++
            7 :: map q16_restore (rev (m :: rev marked ++ [4]))) ++
       source_bit old :: outer)
      ((if bit then 3 else 2) :: final).
Proof.
  intros m marked old dir_head dir_remaining outer between bit final
    Hm Hmarked H21 Hright Hbetween.
  rewrite dispatch_run_add.
  rewrite (canonical_q16_decision_to_q19 m marked old dir_head
    dir_remaining outer bit (between ++ 7 :: final) Hm Hmarked H21).
  replace
    (rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: between ++ 7 :: final)
    with
    ((rev (dir_head :: dir_remaining) ++
      7 :: map q16_restore (rev (m :: rev marked ++ [4]))) ++
     source_bit bit :: between ++ 7 :: final).
  2:{ cbn [app]. repeat rewrite app_assoc.
      repeat rewrite <- app_assoc. reflexivity. }
  apply (q19_to_q5_relocation
    (rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (m :: rev marked ++ [4])))
    between bit (source_bit old :: outer) final Hright Hbetween).
Qed.

(** Leftward relocation: q20 steps onto the target raw bit, writes 6, and
    q17/q18 scan back right across the stored raw bit and the direction
    markers to the 7 left by q16, returning to q5. *)
Theorem canonical_q16_decision_left_to_q5 :
  forall m marked old dir_head dir_remaining target outer bit tail,
    q16_pass m ->
    Forall q16_pass marked ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass (rev (dir_head :: dir_remaining)) ->
    run ((S (length (m :: rev marked ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (1 + S (length
            (source_bit old :: rev (dir_head :: dir_remaining)))))
      (cfg_ml 16
        (rev (marked ++ [m]) ++ 4 ::
         source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (source_bit bit :: tail)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros m marked old dir_head dir_remaining target outer bit tail
    Hm Hmarked H21 Hreturn.
  assert (Hreturn' :
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining))).
  {
    constructor.
    - destruct old; unfold q17_pass, source_bit; simpl;
        [right; left; reflexivity | left; reflexivity].
    - exact Hreturn.
  }
  rewrite dispatch_run_add.
  rewrite (canonical_q16_decision_to_q20 m marked old dir_head
    dir_remaining (source_bit target :: outer) bit tail Hm Hmarked H21).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail))) = expected)
  end.
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: tail)).
  destruct target.
  - exact (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail) Hreturn').
  - exact (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore (rev (m :: rev marked ++ [4])) ++
       source_bit bit :: tail) Hreturn').
Qed.

Print Assumptions canonical_q16_decision_right_to_q5.
Print Assumptions canonical_q16_decision_left_to_q5.

