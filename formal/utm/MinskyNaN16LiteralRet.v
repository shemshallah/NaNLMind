(** * ISA-OBL-3e RET 0x0C: decode and one-step agreement

    RET is opcode 0x0C.  The fixture has three plain returns and one
    predicated return:

      35  FFF8_0C000000_F8FF  RET
      78  FFF8_0C000000_F8FF  RET
      83  FFF8_0C000000_F8FF  RET
      89  FFF1_0C000000_F17F  RET[EQ]

    The plain return needs *no* side condition beyond the relation [R].
    The reason is the link reconciliation of [R]: the model jumps to
    [vm_link] and the literal machine jumps to [r15], and [R] contains
    exactly [vm_link = r15].  This is the one place where the D-16 link
    reconciliation makes the agreement immediate.

    The predicated return has no counterpart in the pre-existing [Instr]
    model, so its statement uses the extended model [exec_instr_p]
    ([pRETP]).  The model evaluates the predicate with the Coq truth
    table [pred_holds] on [vm_zf]/[vm_lf]; the literal machine evaluates
    the oracle bit test [pred_passes] on the packed flags.  The two agree
    on every [k < 4] except [k = 3], hence the explicit side condition
    [l_k L <> 3] (D-07).  This is the same condition already used for
    JMP[EQ]/JMP[GE] in [MinskyNaN16LiteralOps.v].

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** ** Plain RET: extended model *)

Theorem literal_step_RET_agrees_ext :
  forall (image : nat -> N) L vm prog,
    R L vm ->
    decode_word_p (image (l_pc L)) = Some pRET ->
    nth_error prog (vm_pc vm) = Some pRET ->
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
  - exact Hlink.
  - exact Hregs.
  - exact Hreg15.
  - exact Hlink.
  - exact Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - exact Hbound.
Qed.

(** ** Plain RET: pre-existing [Instr] model *)

Theorem literal_step_RET_agrees :
  forall (image : nat -> N) L vm prog,
    R L vm ->
    decode_word_p (image (l_pc L)) = Some pRET ->
    nth_error prog (vm_pc vm) = Some iRET ->
    R (literal_step_p image L) (exec_instr prog vm).
Proof.
  intros image L vm prog HR Hdec Hnth.
  rewrite <- exec_instr_p_embed.
  eapply literal_step_RET_agrees_ext.
  - exact HR.
  - exact Hdec.
  - rewrite nth_error_map, Hnth. reflexivity.
Qed.

(** ** Predicated RET: extended model *)

Theorem literal_step_RETP_agrees :
  forall (image : nat -> N) L vm prog p,
    R L vm ->
    l_k L <> 3 ->
    decode_word_p (image (l_pc L)) = Some (pRETP p) ->
    nth_error prog (vm_pc vm) = Some (pRETP p) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog p HR Hne Hdec Hnth.
  pose proof HR as HR0.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  assert (Hpred : pred_holds p (vm_zf vm) (vm_lf vm)
                = pred_passes (pred_nat p) (l_k L)).
  { rewrite Hzf, Hlf. apply pred_agrees; [exact Hk | exact Hne]. }
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
  - rewrite Hpred, Hlink, Hpcvm. reflexivity.
  - exact Hregs.
  - exact Hreg15.
  - exact Hlink.
  - exact Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - exact Hbound.
Qed.

(** ** Decode of the four fixture returns *)

Lemma fixture_pc35_instr :
  nth 35 fixture_prog_full instrp_default = pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc78_instr :
  nth 78 fixture_prog_full instrp_default = pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc83_instr :
  nth 83 fixture_prog_full instrp_default = pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc89_instr :
  nth 89 fixture_prog_full instrp_default = pRETP pEQ.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_35 :
  decode_word_p (literal_word_at 35) = Some pRET.
Proof.
  rewrite (decode_full_pointwise 35 ltac:(lia)).
  rewrite fixture_pc35_instr. reflexivity.
Qed.

Lemma decode_word_image_word_78 :
  decode_word_p (literal_word_at 78) = Some pRET.
Proof.
  rewrite (decode_full_pointwise 78 ltac:(lia)).
  rewrite fixture_pc78_instr. reflexivity.
Qed.

Lemma decode_word_image_word_83 :
  decode_word_p (literal_word_at 83) = Some pRET.
Proof.
  rewrite (decode_full_pointwise 83 ltac:(lia)).
  rewrite fixture_pc83_instr. reflexivity.
Qed.

Lemma decode_word_image_word_89 :
  decode_word_p (literal_word_at 89) = Some (pRETP pEQ).
Proof.
  rewrite (decode_full_pointwise 89 ltac:(lia)).
  rewrite fixture_pc89_instr. reflexivity.
Qed.

Lemma nth_fixture_pc35 :
  nth_error fixture_prog_full 35 = Some pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc78 :
  nth_error fixture_prog_full 78 = Some pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc83 :
  nth_error fixture_prog_full 83 = Some pRET.
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc89 :
  nth_error fixture_prog_full 89 = Some (pRETP pEQ).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_0_66_pc35 :
  nth_error fixture_prog_0_66 35 = Some iRET.
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligations *)

Theorem fixture_pc35_ret_decode_and_step :
  decode_word_p (literal_word_at 35) = Some pRET /\
  forall L vm,
    R L vm ->
    l_pc L = 35 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_35.
  - intros L vm HR Hpc.
    eapply literal_step_RET_agrees_ext.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_35.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc35.
Qed.

Theorem fixture_pc78_ret_decode_and_step :
  decode_word_p (literal_word_at 78) = Some pRET /\
  forall L vm,
    R L vm ->
    l_pc L = 78 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_78.
  - intros L vm HR Hpc.
    eapply literal_step_RET_agrees_ext.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_78.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc78.
Qed.

Theorem fixture_pc83_ret_decode_and_step :
  decode_word_p (literal_word_at 83) = Some pRET /\
  forall L vm,
    R L vm ->
    l_pc L = 83 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_83.
  - intros L vm HR Hpc.
    eapply literal_step_RET_agrees_ext.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_83.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc83.
Qed.

Theorem fixture_pc89_retp_decode_and_step :
  decode_word_p (literal_word_at 89) = Some (pRETP pEQ) /\
  forall L vm,
    R L vm ->
    l_pc L = 89 ->
    l_k L <> 3 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_89.
  - intros L vm HR Hpc Hne.
    eapply literal_step_RETP_agrees with (p := pEQ).
    + exact HR.
    + exact Hne.
    + rewrite Hpc. apply decode_word_image_word_89.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc89.
Qed.

(** The plain return against the pre-existing [Instr] model, on the
    checked prefix [fixture_prog_0_66]. *)
Theorem fixture_pc35_ret_agrees_model :
  decode_word_p (literal_word_at 35) = Some pRET /\
  forall L vm,
    R L vm ->
    l_pc L = 35 ->
    R (literal_step_p literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_35.
  - intros L vm HR Hpc.
    eapply literal_step_RET_agrees.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_35.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_0_66_pc35.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_RET_agrees_ext.
Print Assumptions literal_step_RET_agrees.
Print Assumptions literal_step_RETP_agrees.
Print Assumptions fixture_pc89_retp_decode_and_step.
