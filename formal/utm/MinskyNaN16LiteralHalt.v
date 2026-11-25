(** * ISA-OBL-3e HALT 0xFF: decode and one-step agreement

    HALT is opcode 0xFF with the [n = 15] (ALWAYS) selector.  The
    fixture halts at two places:

      28  FFF8_FF000000_F8FF  HALT
      98  FFF8_FF000000_F8FF  HALT

    Both machines leave the PC, registers, memory, flags and link
    unchanged and set the halted bit.  The Coq model [Instr] already has
    [iHALT], so [literal_step_HALT_agrees] is stated against the
    pre-existing [exec_instr]; the extended-model form
    [literal_step_HALT_agrees_ext] is provided for uniform coverage with
    the opcodes that need [exec_instr_p], and is used for word 98, which
    lies outside the [Instr]-typed prefix [fixture_prog_0_66].

    There are no side conditions: HALT has no operands, and the decoded
    selector gate ([n = 15]) is part of the decoder, discharged by
    computation on the pinned words.

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** ** One-step agreement (extended model) *)

Theorem literal_step_HALT_agrees_ext :
  forall (image : nat -> N) L vm prog,
    R L vm ->
    decode_word_p (image (l_pc L)) = Some pHALT ->
    nth_error prog (vm_pc vm) = Some pHALT ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog HR Hdec Hnth.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step_p.
  rewrite Hdec.
  cbn [lit_exec_p].
  unfold exec_instr_p.
  rewrite Hnth.
  cbn [exec_instr_p].
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted].
  split_conj.
  - exact Hpcvm.
  - exact Hregs.
  - exact Hreg15.
  - exact Hlink.
  - exact Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - reflexivity.
  - exact Hbound.
Qed.

(** ** One-step agreement (pre-existing [Instr] model) *)

Theorem literal_step_HALT_agrees :
  forall (image : nat -> N) L vm prog,
    R L vm ->
    decode_word_p (image (l_pc L)) = Some pHALT ->
    nth_error prog (vm_pc vm) = Some iHALT ->
    R (literal_step_p image L) (exec_instr prog vm).
Proof.
  intros image L vm prog HR Hdec Hnth.
  rewrite <- exec_instr_p_embed.
  eapply literal_step_HALT_agrees_ext.
  - exact HR.
  - exact Hdec.
  - rewrite nth_error_map, Hnth. reflexivity.
Qed.

(** ** Decode of the two fixture halts *)

Lemma fixture_pc28_instr :
  nth 28 fixture_prog_full instrp_default = pHALT.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc98_instr :
  nth 98 fixture_prog_full instrp_default = pHALT.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_28 :
  decode_word_p (literal_word_at 28) = Some pHALT.
Proof.
  rewrite (decode_full_pointwise 28 ltac:(lia)).
  rewrite fixture_pc28_instr. reflexivity.
Qed.

Lemma decode_word_image_word_98 :
  decode_word_p (literal_word_at 98) = Some pHALT.
Proof.
  rewrite (decode_full_pointwise 98 ltac:(lia)).
  rewrite fixture_pc98_instr. reflexivity.
Qed.

Lemma nth_fixture_pc28 :
  nth_error fixture_prog_full 28 = Some pHALT.
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc98 :
  nth_error fixture_prog_full 98 = Some pHALT.
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_0_66_pc28 :
  nth_error fixture_prog_0_66 28 = Some iHALT.
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligations *)

Theorem fixture_pc28_halt_decode_and_step :
  decode_word_p (literal_word_at 28) = Some pHALT /\
  forall L vm,
    R L vm ->
    l_pc L = 28 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_28.
  - intros L vm HR Hpc.
    eapply literal_step_HALT_agrees_ext.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_28.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc28.
Qed.

Theorem fixture_pc98_halt_decode_and_step :
  decode_word_p (literal_word_at 98) = Some pHALT /\
  forall L vm,
    R L vm ->
    l_pc L = 98 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_98.
  - intros L vm HR Hpc.
    eapply literal_step_HALT_agrees_ext.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_98.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc98.
Qed.

Theorem fixture_pc28_halt_agrees_model :
  decode_word_p (literal_word_at 28) = Some pHALT /\
  forall L vm,
    R L vm ->
    l_pc L = 28 ->
    R (literal_step_p literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_28.
  - intros L vm HR Hpc.
    eapply literal_step_HALT_agrees.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_28.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_0_66_pc28.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_HALT_agrees_ext.
Print Assumptions literal_step_HALT_agrees.
Print Assumptions fixture_pc28_halt_decode_and_step.
Print Assumptions fixture_pc98_halt_decode_and_step.
