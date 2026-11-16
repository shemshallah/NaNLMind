(** * Native q21/q22 movement decision: scan to the stored direction

    The unchanged transition table moves left through unmarked control
    symbols in q21/q22. It then consumes the first direction mark:
      2 -> move left in q20, with bit written as 0/1;
      3 -> move right in q19, with bit written as 0/1.
    Bit 0 corresponds to state q21; bit 1 to q22. All the results
    below quantify over arbitrary finite intervening symbols and
    surrounding zipper tapes. No complete source simulation is assumed.
*)
From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyHeadMoveMacro MinskyMatchMacro.

Definition q21_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Definition q21_written (q : nat) : nat :=
  if Nat.eqb q 22 then 1 else 0.

Lemma q21_pass_step :
  forall q s next left right,
    (q = 21 \/ q = 22) ->
    q21_pass s ->
    step (entry_config q (next :: left) (s :: right)) =
    entry_config q left (next :: s :: right).
Proof.
  intros q s next left right Hq Hs.
  destruct Hq as [-> | ->];
  destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q21_cross_left :
  forall q left tail,
    (q = 21 \/ q = 22) ->
    step (entry_config q left (2 :: tail)) =
    cfg_ml 20 left (q21_written q :: tail).
Proof.
  intros q left tail [-> | ->];
    unfold cfg_ml, q21_written; destruct left; reflexivity.
Qed.

Lemma q21_cross_right :
  forall q left tail,
    (q = 21 \/ q = 22) ->
    step (entry_config q left (3 :: tail)) =
    entry_config 19 (q21_written q :: left) tail.
Proof.
  intros q left tail [-> | ->]; reflexivity.
Qed.

Theorem q21_scan_to_left_direction :
  forall remaining s q prefix suffix,
    (q = 21 \/ q = 22) ->
    Forall q21_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config q (remaining ++ 2 :: prefix) (s :: suffix)) =
    cfg_ml 20 prefix
      (q21_written q :: rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros s q prefix suffix Hq Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hq as [-> | ->];
    destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
      destruct prefix; reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config q (next :: rest ++ 2 :: prefix)
        (s :: suffix)) =
      cfg_ml 20 prefix
        (q21_written q :: rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q21_pass_step q s next
      (rest ++ 2 :: prefix) suffix Hq Hs).
    rewrite (IH next q prefix (s :: suffix) Hq Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc
      (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Theorem q21_scan_to_right_direction :
  forall remaining s q prefix suffix,
    (q = 21 \/ q = 22) ->
    Forall q21_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config q (remaining ++ 3 :: prefix) (s :: suffix)) =
    entry_config 19 (q21_written q :: prefix)
      (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros s q prefix suffix Hq Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hq as [-> | ->];
    destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
      reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config q (next :: rest ++ 3 :: prefix)
        (s :: suffix)) =
      entry_config 19 (q21_written q :: prefix)
        (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q21_pass_step q s next
      (rest ++ 3 :: prefix) suffix Hq Hs).
    rewrite (IH next q prefix (s :: suffix) Hq Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc
      (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Print Assumptions q21_scan_to_left_direction.
Print Assumptions q21_scan_to_right_direction.
