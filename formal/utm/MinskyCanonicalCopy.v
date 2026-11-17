(** * Canonical q6-q11 bit-copy cycle for the frozen 23x8 table

    After [canonical_q5_match_to_q6], q6 sees

      left  = 4 :: rev (raw condition) ++ 5 :: rev t-buffer ++ 6 :: rev data
      right = marked condition-record prefix ++ first raw record bit :: rest

    The q6/q7/q8/q9/q10/q11 macros now perform one copy cycle: q6 marks the
    first raw record bit, q7/q8 return to Y, q9/q10 write the copied mark
    into the first raw condition bit, and q11 returns to q6.  The condition
    bit moves to the left of Y and the record bit stays marked.

    This is one literal cycle, not an induction over all condition bits and
    not a source-step theorem.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalMatch.

Lemma cfg_ml_left_scan :
  forall q (xs : list nat) prefix b suffix,
    xs <> [] ->
    cfg_ml q (xs ++ 5 :: prefix) (b :: suffix) =
    entry_config q (tl xs ++ 5 :: prefix) (hd 2 xs :: b :: suffix).
Proof.
  intros q [|x xs] prefix b suffix Hne; [contradiction|reflexivity].
Qed.

Lemma Forall_hd_tl :
  forall (P : nat -> Prop) xs,
    xs <> [] ->
    Forall P xs ->
    Forall P (hd 2 xs :: tl xs).
Proof.
  intros P [|x xs] Hne H; [contradiction|].
  simpl. exact H.
Qed.

Lemma rev_hd_tl :
  forall xs,
    xs <> [] ->
    rev (hd 2 xs :: tl xs) = rev xs.
Proof.
  intros [|x xs] Hne; [contradiction|reflexivity].
Qed.

Lemma length_hd_tl :
  forall xs,
    xs <> [] ->
    length (hd 2 xs :: tl xs) = length xs.
Proof.
  intros [|x xs] Hne; [contradiction|reflexivity].
Qed.

Lemma Forall_q7_to_q8 :
  forall xs,
    Forall q7_pass xs ->
    Forall q8_pass xs.
Proof.
  intros xs H.
  induction H as [|symbol rest Hsymbol Hrest IH].
  - constructor.
  - constructor.
    + unfold q7_pass, q8_pass in *; exact Hsymbol.
    + exact IH.
Qed.

Lemma Forall_match_mark :
  forall (P : nat -> Prop) bits,
    (forall b, P (match_mark b)) ->
    Forall P (map match_mark bits).
Proof.
  intros P bits H.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply H | exact IH].
Qed.

Lemma Forall_match_raw :
  forall (P : nat -> Prop) bits,
    (forall b, P (match_raw b)) ->
    Forall P (map match_raw bits).
Proof.
  intros P bits H.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply H | exact IH].
Qed.

Lemma canonical_scan_nonempty :
  forall bits,
    rev (map match_mark bits) ++ [4] ++ rev (map match_raw bits) <> [].
Proof.
  intros bits H.
  assert (Hlen : length (rev (map match_mark bits) ++ [4] ++
      rev (map match_raw bits)) = 0) by (rewrite H; reflexivity).
  repeat rewrite app_length in Hlen.
  cbn [length] in Hlen.
  lia.
Qed.

Lemma rev_canonical_scan :
  forall bits,
    rev (rev (map match_mark bits) ++ [4] ++ rev (map match_raw bits)) =
    map match_raw bits ++ [4] ++ map match_mark bits.
Proof.
  intros bits.
  rewrite rev_app_distr.
  rewrite rev_app_distr.
  cbn [rev].
  rewrite rev_involutive.
  rewrite rev_involutive.
  repeat rewrite app_nil_r.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Theorem q6_canonical_scan_zero_to_q10 :
  forall bits tbuffer data rest,
    run (S (length (map match_mark bits)) +
         S (length (rev (map match_mark bits) ++ [4] ++
             rev (map match_raw bits))))
      (entry_config 6
        (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (map match_mark bits ++ 0 :: rest)) =
    entry_config 10 (5 :: rev tbuffer ++ 6 :: rev data)
      (map match_raw bits ++ [4] ++ map match_mark bits ++ [2] ++ rest).
Proof.
  intros bits tbuffer data rest.
  set (region := map match_mark bits).
  set (xs := rev region ++ [4] ++ rev (map match_raw bits)).
  assert (Hregion6 : Forall q6_pass region).
  { unfold region. apply Forall_match_mark.
    intro b; destruct b; unfold q6_pass, match_mark; auto 10. }
  assert (Hregion7 : Forall q7_pass region).
  { unfold region. apply Forall_match_mark.
    intro b; destruct b; unfold q7_pass, match_mark; auto 10. }
  assert (Hxs7 : Forall q7_pass xs).
  { unfold xs. rewrite Forall_app. split.
    - apply Forall_rev. exact Hregion7.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q7_pass; auto 10.
        * constructor.
      + apply Forall_rev. apply Forall_match_raw.
        intro b; destruct b; unfold q7_pass, match_raw; auto 10. }
  assert (Hne : xs <> []).
  { unfold xs, region. apply canonical_scan_nonempty. }
  assert (Hscan : Forall q8_pass (hd 2 xs :: tl xs)).
  { apply Forall_q7_to_q8. apply Forall_hd_tl; [exact Hne | exact Hxs7]. }
  rewrite dispatch_run_add.
  rewrite (q6_scan_zero region
    (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
    rest Hregion6).
  replace (cfg_ml 8 (rev region ++
      4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (2 :: rest))
    with (cfg_ml 8 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data)) (2 :: rest)).
  2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
  rewrite (cfg_ml_left_scan 8 xs (rev tbuffer ++ 6 :: rev data) 2 rest Hne).
  rewrite <- (length_hd_tl xs Hne).
  rewrite (q8_scan_to_y (tl xs) (hd 2 xs)
    (rev tbuffer ++ 6 :: rev data) (2 :: rest) Hscan).
  rewrite (rev_hd_tl xs Hne).
  unfold xs, region.
  rewrite rev_canonical_scan.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions q6_canonical_scan_zero_to_q10.

Theorem q6_canonical_scan_one_to_q9 :
  forall bits tbuffer data rest,
    run (S (length (map match_mark bits)) +
         S (length (rev (map match_mark bits) ++ [4] ++
             rev (map match_raw bits))))
      (entry_config 6
        (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (map match_mark bits ++ 1 :: rest)) =
    entry_config 9 (5 :: rev tbuffer ++ 6 :: rev data)
      (map match_raw bits ++ [4] ++ map match_mark bits ++ [3] ++ rest).
Proof.
  intros bits tbuffer data rest.
  set (region := map match_mark bits).
  set (xs := rev region ++ [4] ++ rev (map match_raw bits)).
  assert (Hregion6 : Forall q6_pass region).
  { unfold region. apply Forall_match_mark.
    intro b; destruct b; unfold q6_pass, match_mark; auto 10. }
  assert (Hregion7 : Forall q7_pass region).
  { unfold region. apply Forall_match_mark.
    intro b; destruct b; unfold q7_pass, match_mark; auto 10. }
  assert (Hxs7 : Forall q7_pass xs).
  { unfold xs. rewrite Forall_app. split.
    - apply Forall_rev. exact Hregion7.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q7_pass; auto 10.
        * constructor.
      + apply Forall_rev. apply Forall_match_raw.
        intro b; destruct b; unfold q7_pass, match_raw; auto 10. }
  assert (Hne : xs <> []).
  { unfold xs, region. apply canonical_scan_nonempty. }
  assert (Hscan : Forall q7_pass (hd 2 xs :: tl xs)).
  { apply Forall_hd_tl; [exact Hne | exact Hxs7]. }
  rewrite dispatch_run_add.
  rewrite (q6_scan_one region
    (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
    rest Hregion6).
  replace (cfg_ml 7 (rev region ++
      4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (3 :: rest))
    with (cfg_ml 7 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data)) (3 :: rest)).
  2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
  rewrite (cfg_ml_left_scan 7 xs (rev tbuffer ++ 6 :: rev data) 3 rest Hne).
  rewrite <- (length_hd_tl xs Hne).
  rewrite (q7_scan_to_y (tl xs) (hd 2 xs)
    (rev tbuffer ++ 6 :: rev data) (3 :: rest) Hscan).
  rewrite (rev_hd_tl xs Hne).
  unfold xs, region.
  rewrite rev_canonical_scan.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions q6_canonical_scan_one_to_q9.

Lemma q10_write_bit_nil :
  forall bit rest prefix,
    (bit = 0 \/ bit = 1) ->
    run (S (length ([] : list nat)))
      (entry_config 10 (5 :: prefix) (bit :: rest)) =
    entry_config 11 (2 :: 5 :: prefix) rest.
Proof.
  intros bit rest prefix Hb.
  change (run (S (length ([] : list nat)))
    (entry_config 10 (5 :: prefix) ([] ++ bit :: rest)) =
    entry_config 11 (2 :: rev ([] : list nat) ++ 5 :: prefix) rest).
  apply q10_write_bit.
  - exact Hb.
  - constructor.
Qed.

Lemma q9_write_bit_nil :
  forall bit rest prefix,
    (bit = 0 \/ bit = 1) ->
    run (S (length ([] : list nat)))
      (entry_config 9 (5 :: prefix) (bit :: rest)) =
    entry_config 11 (3 :: 5 :: prefix) rest.
Proof.
  intros bit rest prefix Hb.
  change (run (S (length ([] : list nat)))
    (entry_config 9 (5 :: prefix) ([] ++ bit :: rest)) =
    entry_config 11 (3 :: rev ([] : list nat) ++ 5 :: prefix) rest).
  apply q9_write_bit.
  - exact Hb.
  - constructor.
Qed.

Lemma Forall_match_raw_q11 :
  forall bits,
    Forall q11_pass (map match_raw bits).
Proof.
  intros bits.
  apply Forall_match_raw.
  intro b; destruct b; unfold q11_pass, match_raw; auto 10.
Qed.

Lemma q11_scan_four_to_q6 :
  forall scanned tail left,
    Forall q11_pass scanned ->
    run (S (length scanned))
      (entry_config 11 left (scanned ++ [4] ++ tail)) =
    entry_config 6 (4 :: rev scanned ++ left) tail.
Proof.
  intros scanned tail left Hscan.
  change (run (S (length scanned))
    (entry_config 11 left (scanned ++ 4 :: tail)) =
    entry_config 6 (4 :: rev scanned ++ left) tail).
  apply q11_scan_to_marker.
  exact Hscan.
Qed.

Lemma q10_write_canonical :
  forall c bits' rest prefix,
    run 1
      (entry_config 10 (5 :: prefix)
        ((match_raw c :: map match_raw bits') ++ [4] ++
         (match_mark c :: map match_mark bits') ++ [2] ++ rest)) =
    entry_config 11 (2 :: 5 :: prefix)
      (map match_raw bits' ++ [4] ++
       (match_mark c :: map match_mark bits') ++ [2] ++ rest).
Proof. destruct c; reflexivity. Qed.

Lemma q9_write_canonical :
  forall c bits' rest prefix,
    run 1
      (entry_config 9 (5 :: prefix)
        ((match_raw c :: map match_raw bits') ++ [4] ++
         (match_mark c :: map match_mark bits') ++ [3] ++ rest)) =
    entry_config 11 (3 :: 5 :: prefix)
      (map match_raw bits' ++ [4] ++
       (match_mark c :: map match_mark bits') ++ [3] ++ rest).
Proof. destruct c; reflexivity. Qed.

Lemma Forall_source_bit_q11 :
  forall bits,
    Forall q11_pass (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q11_pass, source_bit; auto 10.
    + exact IH.
Qed.

(** One full zero-bit copy cycle: q6 marks the first raw record bit, q7/q8
    return to Y, q10 writes the copied mark into the first raw condition
    bit, and q11 returns to q6.  The old condition bit moves left of Y and
    the first record bit stays marked. *)
Theorem canonical_q6_copy_zero_to_q6 :
  forall c bits' tbuffer data rest,
    run ((S (length (map match_mark (c :: bits'))) +
          S (length (rev (map match_mark (c :: bits')) ++ [4] ++
              rev (map match_raw (c :: bits')))))
         + (1 + S (length bits')))
      (entry_config 6
        (4 :: rev (map match_raw (c :: bits')) ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (map match_mark (c :: bits') ++ 0 :: rest)) =
    entry_config 6
      (4 :: rev (map source_bit bits') ++ 2 :: 5 ::
       rev tbuffer ++ 6 :: rev data)
      (map match_mark (c :: bits') ++ [2] ++ rest).
Proof.
  intros c bits' tbuffer data rest.
  rewrite dispatch_run_add.
  rewrite q6_canonical_scan_zero_to_q10.
  cbn [map].
  rewrite dispatch_run_add.
  rewrite (q10_write_canonical c bits' rest
    (rev tbuffer ++ 6 :: rev data)).
  replace (S (length bits'))
    with (S (length (map match_raw bits')))
    by (rewrite map_length; reflexivity).
  rewrite (q11_scan_four_to_q6 (map match_raw bits')
    ((match_mark c :: map match_mark bits') ++ [2] ++ rest)
    (2 :: 5 :: rev tbuffer ++ 6 :: rev data)
    (Forall_match_raw_q11 bits')).
  reflexivity.
Qed.

Print Assumptions canonical_q6_copy_zero_to_q6.

(** The one-bit branch is identical except that q9 writes 3. *)
Theorem canonical_q6_copy_one_to_q6 :
  forall c bits' tbuffer data rest,
    run ((S (length (map match_mark (c :: bits'))) +
          S (length (rev (map match_mark (c :: bits')) ++ [4] ++
              rev (map match_raw (c :: bits')))))
         + (1 + S (length bits')))
      (entry_config 6
        (4 :: rev (map match_raw (c :: bits')) ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (map match_mark (c :: bits') ++ 1 :: rest)) =
    entry_config 6
      (4 :: rev (map source_bit bits') ++ 3 :: 5 ::
       rev tbuffer ++ 6 :: rev data)
      (map match_mark (c :: bits') ++ [3] ++ rest).
Proof.
  intros c bits' tbuffer data rest.
  rewrite dispatch_run_add.
  rewrite q6_canonical_scan_one_to_q9.
  cbn [map].
  rewrite dispatch_run_add.
  rewrite (q9_write_canonical c bits' rest
    (rev tbuffer ++ 6 :: rev data)).
  replace (S (length bits'))
    with (S (length (map match_raw bits')))
    by (rewrite map_length; reflexivity).
  rewrite (q11_scan_four_to_q6 (map match_raw bits')
    ((match_mark c :: map match_mark bits') ++ [3] ++ rest)
    (3 :: 5 :: rev tbuffer ++ 6 :: rev data)
    (Forall_match_raw_q11 bits')).
  reflexivity.
Qed.

Print Assumptions canonical_q6_copy_one_to_q6.
