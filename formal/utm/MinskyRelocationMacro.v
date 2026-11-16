(** * Native rightward and leftward relocation scans of Minsky's 23x8 table

    q17/q18 scan to marker 7, replace it with a binary mark, and
    return in q5. q19 scans to a raw source bit, replaces it with
    the displaced-head marker 6, and chooses q17 or q18. q20 performs
    the corresponding leftward scan, then turns right. All theorems
    concern the literal transition table for arbitrary finite scans
    and surrounding tape. They do not assert whole-source simulation.
*)
From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyHeadMoveMacro MinskyWritebackMacro MinskyMatchMacro MinskySourceEncoding.

Definition q17_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6.

Lemma q17_pass_step :
  forall s q left right,
    (q = 17 \/ q = 18) ->
    q17_pass s ->
    step (entry_config q left (s :: right)) =
    entry_config q (s :: left) right.
Proof.
  intros s q left right Hq Hs.
  destruct Hq as [-> | ->];
  destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q17_cross_marker :
  forall left tail,
    step (entry_config 17 left (7 :: tail)) =
    cfg_ml 5 left (2 :: tail).
Proof. intros left tail; unfold cfg_ml; destruct left; reflexivity. Qed.

Lemma q18_cross_marker :
  forall left tail,
    step (entry_config 18 left (7 :: tail)) =
    cfg_ml 5 left (3 :: tail).
Proof. intros left tail; unfold cfg_ml; destruct left; reflexivity. Qed.

Theorem q17_scan_to_marker :
  forall scanned left tail,
    Forall q17_pass scanned ->
    run (S (length scanned))
      (entry_config 17 left (scanned ++ 7 :: tail)) =
    cfg_ml 5 (rev scanned ++ left) (2 :: tail).
Proof.
  induction scanned as [|s rest IH]; intros left tail Hscan.
  - change (step (entry_config 17 left (7 :: tail)) =
      cfg_ml 5 left (2 :: tail)).
    apply q17_cross_marker.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 17 left (s :: rest ++ 7 :: tail))) =
      cfg_ml 5 (rev (s :: rest) ++ left) (2 :: tail)).
    rewrite (q17_pass_step s 17 left (rest ++ 7 :: tail)
      (or_introl eq_refl) Hs).
    rewrite (IH (s :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s left).
    reflexivity.
Qed.

Theorem q18_scan_to_marker :
  forall scanned left tail,
    Forall q17_pass scanned ->
    run (S (length scanned))
      (entry_config 18 left (scanned ++ 7 :: tail)) =
    cfg_ml 5 (rev scanned ++ left) (3 :: tail).
Proof.
  induction scanned as [|s rest IH]; intros left tail Hscan.
  - change (step (entry_config 18 left (7 :: tail)) =
      cfg_ml 5 left (3 :: tail)).
    apply q18_cross_marker.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 18 left (s :: rest ++ 7 :: tail))) =
      cfg_ml 5 (rev (s :: rest) ++ left) (3 :: tail)).
    rewrite (q17_pass_step s 18 left (rest ++ 7 :: tail)
      (or_intror eq_refl) Hs).
    rewrite (IH (s :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s left).
    reflexivity.
Qed.

Lemma q19_pass_step :
  forall s left right,
    q15_pass s ->
    step (entry_config 19 left (s :: right)) =
    entry_config 19 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q19_raw_to_m :
  forall bit left tail,
    step (entry_config 19 left (source_bit bit :: tail)) =
    entry_config (if bit then 18 else 17) (6 :: left) tail.
Proof. intros [] left tail; reflexivity. Qed.

Theorem q19_scan_to_m :
  forall scanned bit left tail,
    Forall q15_pass scanned ->
    run (S (length scanned))
      (entry_config 19 left (scanned ++ source_bit bit :: tail)) =
    entry_config (if bit then 18 else 17)
      (6 :: rev scanned ++ left) tail.
Proof.
  induction scanned as [|s rest IH]; intros bit left tail Hscan.
  - apply q19_raw_to_m.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 19 left
        (s :: rest ++ source_bit bit :: tail))) =
      entry_config (if bit then 18 else 17)
        (6 :: rev (s :: rest) ++ left) tail).
    rewrite (q19_pass_step s left
      (rest ++ source_bit bit :: tail) Hs).
    rewrite (IH bit (s :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s left).
    reflexivity.
Qed.

Lemma q20_pass_step :
  forall s next left right,
    q15_pass s ->
    step (entry_config 20 (next :: left) (s :: right)) =
    entry_config 20 left (next :: s :: right).
Proof.
  intros s next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q20_raw_to_m :
  forall bit left tail,
    step (entry_config 20 left (source_bit bit :: tail)) =
    entry_config (if bit then 18 else 17) (6 :: left) tail.
Proof. intros [] left tail; reflexivity. Qed.

Theorem q20_scan_to_m :
  forall remaining s bit prefix suffix,
    Forall q15_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 20 (remaining ++ source_bit bit :: prefix)
        (s :: suffix)) =
    entry_config (if bit then 18 else 17)
      (6 :: prefix) (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros s bit prefix suffix Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
      destruct bit; reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 20 (next :: rest ++ source_bit bit :: prefix)
        (s :: suffix)) =
      entry_config (if bit then 18 else 17)
        (6 :: prefix) (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q20_pass_step s next
      (rest ++ source_bit bit :: prefix) suffix Hs).
    rewrite (IH next bit prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

(** Complete q19 -> (q17 or q18) -> q5 subcycle, including its clock. *)
Theorem q19_to_q5_relocation :
  forall scanned between bit left tail,
    Forall q15_pass scanned ->
    Forall q17_pass between ->
    run (S (length scanned) + S (length between))
      (entry_config 19 left
        (scanned ++ source_bit bit :: between ++ 7 :: tail)) =
    cfg_ml 5 (rev between ++ 6 :: rev scanned ++ left)
      ((if bit then 3 else 2) :: tail).
Proof.
  intros scanned between bit left tail Hscan Hbetween.
  rewrite writeback_run_add.
  rewrite (q19_scan_to_m scanned bit left
    (between ++ 7 :: tail) Hscan).
  destruct bit; simpl.
  - apply q18_scan_to_marker. exact Hbetween.
  - apply q17_scan_to_marker. exact Hbetween.
Qed.

Print Assumptions q17_scan_to_marker.
Print Assumptions q18_scan_to_marker.
Print Assumptions q19_scan_to_m.
Print Assumptions q20_scan_to_m.
Print Assumptions q19_to_q5_relocation.
