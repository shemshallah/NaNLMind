(** * Tagged halt hook

    The frozen table has exactly one halting transition: q3 on Y=5.
    The verified tagged left cycle sends a target=true dispatch to q3;
    if the right tail is a q3-passable list followed by 5, the machine
    halts.  This is a native halt macro from the tagged q15 entry.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyActionMacro
  MinskyWritebackMacro MinskyHeadMoveMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle MinskyWideSource
  MinskyConcreteDispatch MinskyWideConcreteDispatch
  MinskyDirectionRelocationCycle.

Definition q3_halt_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 6 \/ s = 7.

Lemma q3_halt_pass_step :
  forall s left right,
    q3_halt_pass s ->
    step (entry_config 3 left (s :: right)) =
    entry_config 3 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q3_five_halts :
  forall left tail,
    c_halted (step (entry_config 3 left (5 :: tail))) = true.
Proof. intros left tail. reflexivity. Qed.

Theorem q3_scan_to_five_halts :
  forall scanned left tail,
    Forall q3_halt_pass scanned ->
    c_halted
      (run (S (length scanned))
        (entry_config 3 left (scanned ++ 5 :: tail))) = true.
Proof.
  induction scanned as [|s rest IH];
    intros left tail Hscan.
  - cbn [length app run].
    apply q3_five_halts.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    cbn [length app].
    change (c_halted
      (run (S (length rest))
        (step (entry_config 3 left
          (s :: rest ++ 5 :: tail)))) = true).
    rewrite (q3_halt_pass_step s left (rest ++ 5 :: tail) Hs).
    apply IH. exact Hrest.
Qed.

(** Target=true tagged left dispatch reaches q3; a passable tail then
    Y=5 halts the machine in 21 + S |tail| native steps. *)
Theorem q15_left_false_guard_halt :
  forall (old next extra : bool) (outer scanned tail : list nat),
    Forall q3_halt_pass scanned ->
    c_halted
      (run (21 + S (length scanned))
        (entry_config 15
          (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
          (q0_stable_control_tag next ::
           q0_stable_control_tag extra :: source_bit true ::
           scanned ++ 5 :: tail))) = true.
Proof.
  intros old next extra outer scanned tail Hscan.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_target_dispatch
    old next extra true outer (scanned ++ 5 :: tail)).
  apply q3_scan_to_five_halts. exact Hscan.
Qed.

Print Assumptions q3_scan_to_five_halts.
Print Assumptions q15_left_false_guard_halt.


(** Local copy of the 4-prefix bridge, kept here so this module only
    depends on the tagged cycle file. *)
Theorem q15_q16_four_prefix_roundtrip_local :
  forall (old target : bool) (tags left suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run (S (length (rev tags)) + S (length (tags ++ [4])))
      (entry_config 15 (4 :: source_bit old :: left)
        (rev tags ++ source_bit target :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit target :: suffix).
Proof.
  intros old target tags left suffix H15 H16.
  rewrite dispatch_run_add.
  rewrite (q15_scan_to_raw (rev tags) target
    (4 :: source_bit old :: left) suffix H15).
  rewrite rev_involutive.
  replace (tags ++ 4 :: source_bit old :: left)
    with ((tags ++ [4]) ++ source_bit old :: left)
    by (rewrite <- app_assoc; reflexivity).
  destruct (tags ++ [4]) as [|s remaining] eqn:H.
  - assert (Hlen : length (tags ++ [4]) = 0)
      by (rewrite H; reflexivity).
    rewrite length_app in Hlen. cbn [length] in Hlen. lia.
  - assert (H16' : Forall q16_pass (s :: remaining)) by exact H16.
    cbn [app cfg_ml].
    rewrite (q16_restore_to_raw remaining s old left
      (source_bit target :: suffix) H16').
    reflexivity.
Qed.

Lemma map_q16_restore_four_prefix :
  forall tags,
    map q16_restore (rev (tags ++ [4])) =
    4 :: map q16_restore (rev tags).
Proof.
  intros tags.
  rewrite rev_app_distr. cbn [rev].
  reflexivity.
Qed.

Theorem q15_q22_right_four_prefix_to_q19 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (rev (map q0_stable_control_tag (first :: rest)))) +
         S (length
           (rev (map q0_stable_control_tag (first :: rest)) ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix).
Proof.
  intros first rest dir_head dir_remaining old target outer suffix H21.
  assert (H15 : Forall q15_pass
      (rev (map q0_stable_control_tag (first :: rest)))).
  { apply q15_stable_control_rail_reverse_safe. }
  assert (H16 : Forall q16_pass
      (map q0_stable_control_tag (first :: rest) ++ [4])).
  {
    rewrite Forall_app. split.
    - apply q16_stable_control_rail_safe.
    - constructor.
      + unfold q16_pass; auto 12.
      + constructor.
  }
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite dispatch_run_add.
  match goal with |- ?G => idtac "Q19PREFIX:" G end.
  rewrite (q15_q16_four_prefix_roundtrip_local old target
    (map q0_stable_control_tag (first :: rest))
    (dir_head :: dir_remaining ++ 3 :: outer) suffix H15 H16).
  rewrite map_q16_restore_four_prefix.
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head ::
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix)).
  rewrite (q21_scan_to_right_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: 4 ::
     map q16_restore
       (rev (map q0_stable_control_tag (first :: rest))) ++
     source_bit target :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Print Assumptions q15_q22_right_four_prefix_to_q19.
