(** * Canonical fetch: q5 match, action copy and direction capture

    One instruction record of the wide source format is

      X=4, current bits, read bit, next bits, write bit, direction bit.

    The canonical q5 phase matches the current/read prefix, the q6 copy
    phase copies the next/write action into the working marks, and the q9
    direction phase captures the direction bit and enters q12/q13.

    This theorem composes those three certified phases into one exact
    native clock.  It is still a phase theorem, not a whole-source step.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyConcreteDispatch MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalMatch MinskyCanonicalCopy
  MinskyCanonicalCopyGeneral MinskyCanonicalDirection.

(** [bits] is the current-state/read prefix, [action_bits] the
    next-state/write action of equal length, and [dir] the direction bit
    that follows them in the record. *)
Theorem canonical_q5_match_copy_direction :
  forall bits action_bits tbuffer data dir tail,
    length action_bits = length bits ->
    run ((((length bits + 2) +
           (matched_comparison_steps bits 0 1 + (length bits + 1))) +
          copy_all_clock bits action_bits [] (map match_mark bits)) +
         (S (length (map match_mark bits ++ map match_mark action_bits)) +
          (S (length
                (rev (map match_mark bits ++ map match_mark action_bits) ++
                 [4] ++ rev (map match_mark action_bits))) +
           S (length (map match_mark action_bits)))))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++ map source_bit action_bits ++
         source_bit dir :: tail)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark action_bits) ++ 5 :: rev tbuffer ++
       6 :: rev data)
      (4 :: map match_mark bits ++ map match_mark action_bits ++
           (if dir then 3 else 2) :: tail).
Proof.
  intros bits action_bits tbuffer data dir tail Hlen.
  assert (Hreg6 : Forall q6_pass (map match_mark bits)).
  {
    apply Forall_match_mark.
    intros b. destruct b; unfold q6_pass, match_mark; auto 10.
  }
  assert (Hreg7 : Forall q7_pass (map match_mark bits)).
  {
    apply Forall_match_mark.
    intros b. destruct b; unfold q7_pass, match_mark; auto 10.
  }
  assert (Hmarked6 : Forall q6_pass
      (map match_mark bits ++ map match_mark action_bits)).
  {
    apply Forall_app. split.
    - exact Hreg6.
    - apply Forall_match_mark.
      intros b. destruct b; unfold q6_pass, match_mark; auto 10.
  }
  assert (Hmarked7 : Forall q7_pass
      (map match_mark bits ++ map match_mark action_bits)).
  {
    apply Forall_app. split.
    - exact Hreg7.
    - apply Forall_match_mark.
      intros b. destruct b; unfold q7_pass, match_mark; auto 10.
  }
  assert (Hrec7 : Forall q7_pass (map match_mark action_bits)).
  {
    apply Forall_match_mark.
    intros b. destruct b; unfold q7_pass, match_mark; auto 10.
  }
  assert (Hrec9 : Forall q9_pass (map match_mark action_bits)).
  {
    apply Forall_match_mark.
    intros b. destruct b; unfold q9_pass, match_mark; auto 10.
  }
  rewrite <- Nat.add_assoc.
  rewrite dispatch_run_add.
  rewrite (canonical_q5_match_to_q6 bits tbuffer data
    (map source_bit action_bits ++ source_bit dir :: tail)).
  rewrite dispatch_run_add.
  rewrite (canonical_q6_copy_all bits
    (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
    (map match_mark bits ++ map source_bit action_bits ++
     source_bit dir :: tail)
    [] (map match_mark bits) action_bits (source_bit dir :: tail)
    tbuffer data eq_refl eq_refl (eq_sym Hlen)
    (Forall_nil q7_pass) (Forall_nil q9_pass) Hreg6 Hreg7).
  replace
    (map match_mark bits ++ map match_mark action_bits ++
     source_bit dir :: tail)
    with
    ((map match_mark bits ++ map match_mark action_bits) ++
     source_bit dir :: tail)
    by (rewrite <- app_assoc; reflexivity).
  cbn [app].
  exact (canonical_q6_direction_capture
    (map match_mark bits ++ map match_mark action_bits)
    (map match_mark action_bits) tail tbuffer data dir
    Hmarked6 Hmarked7 Hrec7 Hrec9).
Qed.

Print Assumptions canonical_q5_match_copy_direction.
