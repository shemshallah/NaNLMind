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

