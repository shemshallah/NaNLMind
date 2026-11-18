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
  MinskyConcreteEntry MinskyMatchMacro MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyCanonicalRestore.

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
