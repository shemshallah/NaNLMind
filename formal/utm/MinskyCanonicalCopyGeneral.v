(** * General canonical q6-q11 copy cycle

    The single-cycle module fixes an empty processed prefix.  This module
    generalizes the cycle to an arbitrary processed condition prefix
    (already moved left of Y) and an arbitrary marked record prefix.  This
    is the invariant needed for the induction over all condition bits.

    It is still one literal cycle; the induction is a separate obligation.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalMatch MinskyCanonicalCopy.

Lemma Forall_source_bit_q7 :
  forall bits,
    Forall q7_pass (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q7_pass, source_bit; auto 10.
    + exact IH.
Qed.

(** Scan an arbitrary marked prefix and write the head of the following
    nonempty raw list.  This avoids splitting the raw list into its head
    and tail before the rewrite. *)
Lemma q10_write_after_marked :
  forall marked raw left,
    Forall q9_pass marked ->
    raw <> [] ->
    (hd 0 raw = 0 \/ hd 0 raw = 1) ->
    run (S (length marked))
      (entry_config 10 left (marked ++ raw)) =
    entry_config 11 (2 :: rev marked ++ left) (tl raw).
Proof.
  intros marked.
  induction marked as [|m ms IH]; intros raw left Hmarks Hne Hhd.
  - cbn [length].
    destruct raw as [|h t]; [contradiction|].
    cbn [hd] in Hhd.
    destruct Hhd as [-> | ->]; reflexivity.
  - inversion Hmarks as [|? ? Hm Hms]; subst.
    change (run (S (S (length ms)))
      (entry_config 10 left (m :: (ms ++ raw))) =
      entry_config 11 (2 :: rev (m :: ms) ++ left) (tl raw)).
    rewrite entry_run_successor.
    rewrite (q10_pass_step m left (ms ++ raw) Hm).
    rewrite (IH raw (m :: left) Hms Hne Hhd).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma q9_write_after_marked :
  forall marked raw left,
    Forall q9_pass marked ->
    raw <> [] ->
    (hd 0 raw = 0 \/ hd 0 raw = 1) ->
    run (S (length marked))
      (entry_config 9 left (marked ++ raw)) =
    entry_config 11 (3 :: rev marked ++ left) (tl raw).
Proof.
  intros marked.
  induction marked as [|m ms IH]; intros raw left Hmarks Hne Hhd.
  - cbn [length].
    destruct raw as [|h t]; [contradiction|].
    cbn [hd] in Hhd.
    destruct Hhd as [-> | ->]; reflexivity.
  - inversion Hmarks as [|? ? Hm Hms]; subst.
    change (run (S (S (length ms)))
      (entry_config 9 left (m :: (ms ++ raw))) =
      entry_config 11 (3 :: rev (m :: ms) ++ left) (tl raw)).
    rewrite entry_run_successor.
    rewrite (q9_pass_step m left (ms ++ raw) Hm).
    rewrite (IH raw (m :: left) Hms Hne Hhd).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma rev_general_scan :
  forall processed region (raw : list nat),
    rev (rev region ++ [4] ++ rev raw ++ processed) =
    rev processed ++ raw ++ [4] ++ region.
Proof.
  intros processed region raw.
  repeat rewrite rev_app_distr.
  cbn [rev].
  repeat rewrite rev_involutive.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Theorem canonical_q6_copy_zero_general :
  forall processed c bits' region record_tail tbuffer data,
    Forall q7_pass processed ->
    Forall q9_pass processed ->
    Forall q6_pass region ->
    Forall q7_pass region ->
    run (S (length region) +
         (S (length (rev region ++ [4] ++
             rev (map source_bit (c :: bits')) ++ processed)) +
          (S (length processed) + S (length bits'))))
      (entry_config 6
        (4 :: rev (map source_bit (c :: bits')) ++ processed ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (region ++ 0 :: record_tail)) =
    entry_config 6
      (4 :: rev (map source_bit bits') ++ 2 :: processed ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (region ++ 2 :: record_tail).
Proof.
  intros processed c bits' region record_tail tbuffer data
    Hproc7 Hproc9 Hreg6 Hreg7.
  set (raw := map source_bit (c :: bits')).
  set (xs := rev region ++ [4] ++ rev raw ++ processed).
  assert (Hxs7 : Forall q7_pass xs).
  { unfold xs. rewrite Forall_app. split.
    - apply Forall_rev. exact Hreg7.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q7_pass; auto 10.
        * constructor.
      + rewrite Forall_app. split.
        * apply Forall_rev. unfold raw. apply Forall_source_bit_q7.
        * exact Hproc7. }
  assert (Hne : xs <> []).
  { intro H.
    assert (Hlen : length xs = 0) by (rewrite H; reflexivity).
    unfold xs in Hlen.
    repeat rewrite app_length in Hlen.
    cbn [length] in Hlen.
    lia. }
  assert (Hscan : Forall q8_pass (hd 2 xs :: tl xs)).
  { apply Forall_q7_to_q8. apply Forall_hd_tl; [exact Hne | exact Hxs7]. }
  rewrite dispatch_run_add.
  rewrite (q6_scan_zero region
    (4 :: rev raw ++ processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
    record_tail Hreg6).
  replace (cfg_ml 8 (rev region ++
      4 :: rev raw ++ processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (2 :: record_tail))
    with (cfg_ml 8 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data))
      (2 :: record_tail)).
  2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
  rewrite (cfg_ml_left_scan 8 xs (rev tbuffer ++ 6 :: rev data)
    2 record_tail Hne).
  rewrite <- (length_hd_tl xs Hne).
  rewrite dispatch_run_add.
  rewrite (q8_scan_to_y (tl xs) (hd 2 xs)
    (rev tbuffer ++ 6 :: rev data) (2 :: record_tail) Hscan).
  rewrite (rev_hd_tl xs Hne).
  unfold xs, raw.
  rewrite rev_general_scan.
  cbn [map].
  repeat rewrite <- app_assoc.
  cbn [app].
  rewrite dispatch_run_add.
  replace (S (length processed))
    with (S (length (rev processed)))
    by (rewrite rev_length; reflexivity).
  assert (Hne_raw : source_bit c :: map source_bit bits' ++
      4 :: region ++ 2 :: record_tail <> []).
  { discriminate. }
  assert (Hhd_raw : hd 0 (source_bit c :: map source_bit bits' ++
      4 :: region ++ 2 :: record_tail) = 0 \/
      hd 0 (source_bit c :: map source_bit bits' ++
      4 :: region ++ 2 :: record_tail) = 1).
  { cbn [hd]. destruct c; auto. }
  rewrite (q10_write_after_marked (rev processed)
    (source_bit c :: map source_bit bits' ++ 4 :: region ++ 2 :: record_tail)
    (5 :: rev tbuffer ++ 6 :: rev data)
    (Forall_rev Hproc9) Hne_raw Hhd_raw).
  rewrite rev_involutive.
  cbn [tl].
  replace (S (length bits'))
    with (S (length (map source_bit bits')))
    by (rewrite map_length; reflexivity).
  rewrite (q11_scan_to_marker (map source_bit bits')
    (2 :: processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
    (region ++ 2 :: record_tail)
    (Forall_source_bit_q11 bits')).
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Theorem canonical_q6_copy_one_general :
  forall processed c bits' region record_tail tbuffer data,
    Forall q7_pass processed ->
    Forall q9_pass processed ->
    Forall q6_pass region ->
    Forall q7_pass region ->
    run (S (length region) +
         (S (length (rev region ++ [4] ++
             rev (map source_bit (c :: bits')) ++ processed)) +
          (S (length processed) + S (length bits'))))
      (entry_config 6
        (4 :: rev (map source_bit (c :: bits')) ++ processed ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (region ++ 1 :: record_tail)) =
    entry_config 6
      (4 :: rev (map source_bit bits') ++ 3 :: processed ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (region ++ 3 :: record_tail).
Proof.
  intros processed c bits' region record_tail tbuffer data
    Hproc7 Hproc9 Hreg6 Hreg7.
  set (raw := map source_bit (c :: bits')).
  set (xs := rev region ++ [4] ++ rev raw ++ processed).
  assert (Hxs7 : Forall q7_pass xs).
  { unfold xs. rewrite Forall_app. split.
    - apply Forall_rev. exact Hreg7.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q7_pass; auto 10.
        * constructor.
      + rewrite Forall_app. split.
        * apply Forall_rev. unfold raw. apply Forall_source_bit_q7.
        * exact Hproc7. }
  assert (Hne : xs <> []).
  { intro H.
    assert (Hlen : length xs = 0) by (rewrite H; reflexivity).
    unfold xs in Hlen.
    repeat rewrite app_length in Hlen.
    cbn [length] in Hlen.
    lia. }
  assert (Hscan : Forall q8_pass (hd 2 xs :: tl xs)).
  { apply Forall_q7_to_q8. apply Forall_hd_tl; [exact Hne | exact Hxs7]. }
  rewrite dispatch_run_add.
  rewrite (q6_scan_one region
    (4 :: rev raw ++ processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
    record_tail Hreg6).
  replace (cfg_ml 7 (rev region ++
      4 :: rev raw ++ processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (3 :: record_tail))
    with (cfg_ml 7 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data))
      (3 :: record_tail)).
  2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
  rewrite (cfg_ml_left_scan 7 xs (rev tbuffer ++ 6 :: rev data)
    3 record_tail Hne).
  rewrite <- (length_hd_tl xs Hne).
  rewrite dispatch_run_add.
  rewrite (q7_scan_to_y (tl xs) (hd 2 xs)
    (rev tbuffer ++ 6 :: rev data) (3 :: record_tail) Hscan).
  rewrite (rev_hd_tl xs Hne).
  unfold xs, raw.
  rewrite rev_general_scan.
  cbn [map].
  repeat rewrite <- app_assoc.
  cbn [app].
  rewrite dispatch_run_add.
  replace (S (length processed))
    with (S (length (rev processed)))
    by (rewrite rev_length; reflexivity).
  assert (Hne_raw : source_bit c :: map source_bit bits' ++
      4 :: region ++ 3 :: record_tail <> []).
  { discriminate. }
  assert (Hhd_raw : hd 0 (source_bit c :: map source_bit bits' ++
      4 :: region ++ 3 :: record_tail) = 0 \/
      hd 0 (source_bit c :: map source_bit bits' ++
      4 :: region ++ 3 :: record_tail) = 1).
  { cbn [hd]. destruct c; auto. }
  rewrite (q9_write_after_marked (rev processed)
    (source_bit c :: map source_bit bits' ++ 4 :: region ++ 3 :: record_tail)
    (5 :: rev tbuffer ++ 6 :: rev data)
    (Forall_rev Hproc9) Hne_raw Hhd_raw).
  rewrite rev_involutive.
  cbn [tl].
  replace (S (length bits'))
    with (S (length (map source_bit bits')))
    by (rewrite map_length; reflexivity).
  rewrite (q11_scan_to_marker (map source_bit bits')
    (3 :: processed ++ 5 :: rev tbuffer ++ 6 :: rev data)
    (region ++ 3 :: record_tail)
    (Forall_source_bit_q11 bits')).
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.


Print Assumptions canonical_q6_copy_zero_general.
Print Assumptions canonical_q6_copy_one_general.


(** Specialized cycle with the exact Fixpoint-unfolded record shape.
    This is the form needed by the all-condition induction. *)
Lemma canonical_q6_copy_unfolded :
  forall processed c cs region rs record_tail tbuffer data (r : bool),
    Forall q7_pass processed ->
    Forall q9_pass processed ->
    Forall q6_pass region ->
    Forall q7_pass region ->
    run (S (length region) +
         (S (length (rev region ++ [4] ++
             rev (map source_bit (c :: cs)) ++ processed)) +
          (S (length processed) + S (length cs))))
      (entry_config 6
        (4 :: rev (map source_bit (c :: cs)) ++ processed ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (region ++ map source_bit (r :: rs) ++ record_tail)) =
    entry_config 6
      (4 :: rev (map source_bit cs) ++ match_mark r :: processed ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (region ++ match_mark r :: map source_bit rs ++ record_tail).
Proof.
  intros processed c cs region rs record_tail tbuffer data r
    Hproc7 Hproc9 Hreg6 Hreg7.
  destruct r; cbn [map].
  - apply (canonical_q6_copy_one_general processed c cs region
      (map source_bit rs ++ record_tail) tbuffer data
      Hproc7 Hproc9 Hreg6 Hreg7).
  - apply (canonical_q6_copy_zero_general processed c cs region
      (map source_bit rs ++ record_tail) tbuffer data
      Hproc7 Hproc9 Hreg6 Hreg7).
Qed.

Print Assumptions canonical_q6_copy_unfolded.

Fixpoint copy_all_clock (bits record_bits : list bool)
    (processed region : list nat) : nat :=
  match bits, record_bits with
  | c :: cs, r :: rs =>
      (S (length region) +
       (S (length (rev region ++ [4] ++
           rev (map source_bit (c :: cs)) ++ processed)) +
        (S (length processed) + S (length cs))))
      + copy_all_clock cs rs (match_mark r :: processed)
          (region ++ [match_mark r])
  | _, _ => 0
  end.

Theorem canonical_q6_copy_all :
  forall bits record_bits processed region record_tail tbuffer data,
    length bits = length record_bits ->
    Forall q7_pass processed ->
    Forall q9_pass processed ->
    Forall q6_pass region ->
    Forall q7_pass region ->
    run (copy_all_clock bits record_bits processed region)
      (entry_config 6
        (4 :: rev (map source_bit bits) ++ processed ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (region ++ map source_bit record_bits ++ record_tail)) =
    entry_config 6
      (4 :: rev (map match_mark record_bits) ++ processed ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (region ++ map match_mark record_bits ++ record_tail).
Proof.
  intros bits.
  induction bits as [|c cs IH];
    intros record_bits processed region record_tail tbuffer data
      Hlen Hproc7 Hproc9 Hreg6 Hreg7.
  - destruct record_bits as [|r rs].
    + cbn [copy_all_clock map]. reflexivity.
    + cbn [length] in Hlen. discriminate Hlen.
  - destruct record_bits as [|r rs].
    + cbn [length] in Hlen. discriminate Hlen.
    + assert (Hlen' : length cs = length rs).
      { inversion Hlen. reflexivity. }
      cbn [copy_all_clock].
      rewrite dispatch_run_add.
      destruct r.
      * rewrite (canonical_q6_copy_unfolded processed c cs region rs
          record_tail tbuffer data true Hproc7 Hproc9 Hreg6 Hreg7).
        cbn [match_mark map rev app].
        replace (region ++ 3 :: map source_bit rs ++ record_tail)
          with ((region ++ [3]) ++ map source_bit rs ++ record_tail)
          by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
        replace (region ++ 3 :: map match_mark rs ++ record_tail)
          with ((region ++ [3]) ++ map match_mark rs ++ record_tail)
          by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
        apply (IH rs (3 :: processed) (region ++ [3])
          record_tail tbuffer data).
        -- exact Hlen'.
        -- constructor; [unfold q7_pass; auto 10 | exact Hproc7].
        -- constructor; [unfold q9_pass; auto 10 | exact Hproc9].
        -- apply Forall_app; split; [exact Hreg6 | constructor;
             [unfold q6_pass; auto 10 | constructor]].
        -- apply Forall_app; split; [exact Hreg7 | constructor;
             [unfold q7_pass; auto 10 | constructor]].
      * rewrite (canonical_q6_copy_unfolded processed c cs region rs
          record_tail tbuffer data false Hproc7 Hproc9 Hreg6 Hreg7).
        cbn [match_mark map rev app].
        replace (region ++ 2 :: map source_bit rs ++ record_tail)
          with ((region ++ [2]) ++ map source_bit rs ++ record_tail)
          by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
        replace (region ++ 2 :: map match_mark rs ++ record_tail)
          with ((region ++ [2]) ++ map match_mark rs ++ record_tail)
          by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
        apply (IH rs (2 :: processed) (region ++ [2])
          record_tail tbuffer data).
        -- exact Hlen'.
        -- constructor; [unfold q7_pass; auto 10 | exact Hproc7].
        -- constructor; [unfold q9_pass; auto 10 | exact Hproc9].
        -- apply Forall_app; split; [exact Hreg6 | constructor;
             [unfold q6_pass; auto 10 | constructor]].
        -- apply Forall_app; split; [exact Hreg7 | constructor;
             [unfold q7_pass; auto 10 | constructor]].
Qed.

Print Assumptions canonical_q6_copy_all.
