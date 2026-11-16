(** * Concrete q15/q16 movement phase of the unchanged 23x8 table

    q15 scans right over marked/delimiter cells until a raw 0/1 bit and
    returns left in q16.  q16 restores 2->0 and 3->1 while scanning left
    to the preceding raw bit, writes the marker 7, and selects q21/q22.
    These are exact native-table facts for arbitrary finite scan lengths.

    They do NOT by themselves identify a simulated source head position,
    prove an instruction macro, or establish universality.
*)

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyMatchMacro MinskySourceEncoding.

Definition q15_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q15_pass_step :
  forall s left right,
    q15_pass s ->
    step (entry_config 15 left (s :: right)) =
    entry_config 15 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q15_raw_return :
  forall bit left tail,
    step (entry_config 15 left (source_bit bit :: tail)) =
    cfg_ml 16 left (source_bit bit :: tail).
Proof.
  intros [] left tail; unfold cfg_ml; destruct left; reflexivity.
Qed.

Theorem q15_scan_to_raw :
  forall scanned bit left tail,
    Forall q15_pass scanned ->
    run (S (length scanned))
      (entry_config 15 left (scanned ++ source_bit bit :: tail)) =
    cfg_ml 16 (rev scanned ++ left) (source_bit bit :: tail).
Proof.
  induction scanned as [|s rest IH]; intros bit left tail Hscan.
  - change (step (entry_config 15 left (source_bit bit :: tail)) =
      cfg_ml 16 left (source_bit bit :: tail)).
    apply q15_raw_return.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 15 left (s :: rest ++ source_bit bit :: tail))) =
      cfg_ml 16 (rev (s :: rest) ++ left) (source_bit bit :: tail)).
    rewrite (q15_pass_step s left (rest ++ source_bit bit :: tail) Hs).
    rewrite (IH bit (s :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s left).
    reflexivity.
Qed.

Definition q16_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Definition q16_restore (s : nat) : nat :=
  match s with
  | 2 => 0
  | 3 => 1
  | _ => s
  end.

Lemma q16_pass_step :
  forall s next left right,
    q16_pass s ->
    step (entry_config 16 (next :: left) (s :: right)) =
    entry_config 16 left (next :: q16_restore s :: right).
Proof.
  intros s next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q16_raw_mark :
  forall bit left tail,
    step (entry_config 16 left (source_bit bit :: tail)) =
    cfg_ml (if bit then 22 else 21) left (7 :: tail).
Proof.
  intros [] left tail; unfold cfg_ml; destruct left; reflexivity.
Qed.

(** Exact leftward restoration and branch selection.  The simulated
    left tape is arbitrary; [cfg_ml] handles even an empty outer prefix. *)
Theorem q16_restore_to_raw :
  forall remaining s bit prefix suffix,
    Forall q16_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 16 (remaining ++ source_bit bit :: prefix)
        (s :: suffix)) =
    cfg_ml (if bit then 22 else 21) prefix
      (7 :: map q16_restore (rev (s :: remaining)) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros s bit prefix suffix Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
      destruct bit; destruct prefix; reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 16 (next :: rest ++ source_bit bit :: prefix)
        (s :: suffix)) =
      cfg_ml (if bit then 22 else 21) prefix
        (7 :: map q16_restore (rev (s :: next :: rest)) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q16_pass_step s next
      (rest ++ source_bit bit :: prefix) suffix Hs).
    rewrite (IH next bit prefix (q16_restore s :: suffix) Hrest).
    cbn [rev].
    rewrite map_app.
    cbn [map].
    rewrite (append_singleton_assoc
      (map q16_restore (rev (next :: rest)))
      (q16_restore s) suffix).
    reflexivity.
Qed.

Print Assumptions q15_scan_to_raw.
Print Assumptions q16_restore_to_raw.
