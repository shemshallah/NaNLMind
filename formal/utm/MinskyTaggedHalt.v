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
