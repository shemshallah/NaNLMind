(** * ISA-OBL-3e SHL 0x05: decode and one-step agreement

    This module closes the SHL obligation of the raw NaN16 ISA for the
    literal fixture.  SHL is opcode 0x05 and is word 49 of the pinned
    image:

      49  FFF8_05780003_F8FF  SHL r7,r8,3

    Two agreement statements are proved.

    - [literal_step_SHL_agrees_ext] is stated against the extended Coq
      model [exec_instr_p] of [MinskyNaN16LiteralExec.v].

    - [literal_step_SHL_agrees] is stated against the *pre-existing* Coq
      model [exec_instr] of [MinskyNaN16VM.v] and the original [Instr]
      program type.  It is derived from the extended statement through
      the conservativity lemma [exec_instr_p_embed].

    Explicit side conditions, all inherited from deltas between the ISA
    text and the Coq model:

    - [a < 16], [d < 16]: literal operands outside 0..15 read the list
      default, the Coq model reads the total register function.
    - [d <> 15]: the Coq model keeps the link in [vm_link], not
      [vm_reg 15] (D-16).
    - [imm < 32]: the literal ISA shifts by [imm mod 32]; the Coq model
      [iSHL] shifts by the raw [imm] (D-08).
    - [l_reg L a * 2 ^ imm < 2 ^ 32]: the literal ISA masks the result
      to 32 bits; the Coq model shift is unbounded (D-09).  The fixture
      shift is by 3 on the row index [r8 < 184], so the premise holds on
      every reachable fixture state.

    The concrete obligation [fixture_pc49_shl_decode_and_step] states
    both the literal decode and the one-step [R] preservation from
    [l_pc = 49].  [fixture_pc49_shl_agrees_model] is the same step
    against the pre-existing [Instr] model on the checked prefix
    [fixture_prog_0_66].

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** ** Generic one-step agreement (extended model) *)

Theorem literal_step_SHL_agrees_ext :
  forall (image : nat -> N) L vm prog d a imm,
    R L vm ->
    a < 16 ->
    d < 16 ->
    d <> 15 ->
    imm < 32 ->
    l_reg L a * 2 ^ imm < 2 ^ 32 ->
    decode_word_p (image (l_pc L)) = Some (pSHL d a imm) ->
    nth_error prog (vm_pc vm) = Some (pSHL d a imm) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog d a imm HR Ha Hd Hd15 Himm Hov Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  assert (Hsh : Nat.shiftl (l_reg L a) imm < 2 ^ 32).
  { rewrite Nat.shiftl_mul_pow2. exact Hov. }
  assert (Hv : e_shl32 (l_reg L a) (imm mod 32) = Nat.shiftl (l_reg L a) imm).
  { rewrite Nat.mod_small by lia. apply e_shl32_eq. exact Hsh. }
  unfold literal_step_p.
  rewrite Hdec.
  cbn [lit_exec_p].
  unfold exec_instr_p.
  rewrite Hnth.
  cbn [exec_instr_p].
  unfold get_reg.
  rewrite Hreg_a.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite !set_reg_eq. rewrite Hv.
      rewrite Nat.mod_small by exact Hsh. reflexivity.
    + rewrite !set_reg_neq by exact Hne. apply Hregs. exact Hi.
  - rewrite !set_reg_neq by lia. exact Hreg15.
  - rewrite set_reg_neq by lia. exact Hlink.
  - intro ad. apply Hmem.
  - rewrite pack_k_zf. rewrite Hv. reflexivity.
  - rewrite pack_k_lf. reflexivity.
  - apply pack_k_lt_4.
  - exact Hhalt.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq. rewrite Hv. exact Hsh.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** Generic one-step agreement (pre-existing Coq model) *)

Theorem literal_step_SHL_agrees :
  forall (image : nat -> N) L vm prog d a imm,
    R L vm ->
    a < 16 ->
    d < 16 ->
    d <> 15 ->
    imm < 32 ->
    l_reg L a * 2 ^ imm < 2 ^ 32 ->
    decode_word_p (image (l_pc L)) = Some (pSHL d a imm) ->
    nth_error prog (vm_pc vm) = Some (iSHL d a imm) ->
    R (literal_step_p image L) (exec_instr prog vm).
Proof.
  intros image L vm prog d a imm HR Ha Hd Hd15 Himm Hov Hdec Hnth.
  rewrite <- exec_instr_p_embed.
  eapply literal_step_SHL_agrees_ext.
  - exact HR.
  - exact Ha.
  - exact Hd.
  - exact Hd15.
  - exact Himm.
  - exact Hov.
  - exact Hdec.
  - rewrite nth_error_map, Hnth. reflexivity.
Qed.

(** ** Decode of the fixture word *)

Lemma fixture_pc49_instr :
  nth 49 fixture_prog_full instrp_default = pSHL 7 8 3.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_49 :
  decode_word_p (literal_word_at 49) = Some (pSHL 7 8 3).
Proof.
  rewrite (decode_full_pointwise 49 ltac:(lia)).
  rewrite fixture_pc49_instr. reflexivity.
Qed.

Lemma nth_fixture_pc49 :
  nth_error fixture_prog_full 49 = Some (pSHL 7 8 3).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_0_66_pc49 :
  nth_error fixture_prog_0_66 49 = Some (iSHL 7 8 3).
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligations *)

Theorem fixture_pc49_shl_decode_and_step :
  decode_word_p (literal_word_at 49) = Some (pSHL 7 8 3) /\
  forall L vm,
    R L vm ->
    l_pc L = 49 ->
    l_reg L 8 * 2 ^ 3 < 2 ^ 32 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_49.
  - intros L vm HR Hpc Hov.
    eapply literal_step_SHL_agrees_ext with (d := 7) (a := 8) (imm := 3).
    + exact HR.
    + lia.
    + lia.
    + lia.
    + lia.
    + exact Hov.
    + rewrite Hpc. apply decode_word_image_word_49.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc49.
Qed.

Theorem fixture_pc49_shl_agrees_model :
  decode_word_p (literal_word_at 49) = Some (pSHL 7 8 3) /\
  forall L vm,
    R L vm ->
    l_pc L = 49 ->
    l_reg L 8 * 2 ^ 3 < 2 ^ 32 ->
    R (literal_step_p literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_49.
  - intros L vm HR Hpc Hov.
    eapply literal_step_SHL_agrees with (d := 7) (a := 8) (imm := 3).
    + exact HR.
    + lia.
    + lia.
    + lia.
    + lia.
    + exact Hov.
    + rewrite Hpc. apply decode_word_image_word_49.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_0_66_pc49.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_SHL_agrees_ext.
Print Assumptions literal_step_SHL_agrees.
Print Assumptions fixture_pc49_shl_decode_and_step.
Print Assumptions fixture_pc49_shl_agrees_model.
