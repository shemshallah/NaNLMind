(** * ISA-OBL-3e SHR 0x06: decode and one-step agreement

    SHR is opcode 0x06 and is word 91 of the pinned image:

      91  FFF8_06220008_F8FF  SHR r2,r2,8

    The pre-existing Coq model [Instr] of [MinskyNaN16VM.v] has no SHR
    constructor, so the agreement statement is made against the extended
    model [exec_instr_p] of [MinskyNaN16LiteralExec.v], whose [pSHR] case
    is the ISA logical right shift [Nat.shiftr].  On the eleven original
    [Instr] constructors that model is definitionally [exec_instr]
    ([exec_instr_p_embed]), so no previously checked VM behaviour is
    revised.

    Side conditions:

    - [a < 16], [d < 16]: register-index range of the literal list;
    - [d <> 15]: the Coq model keeps the link in [vm_link], not
      [vm_reg 15] (D-16);
    - [imm < 32]: the literal ISA shifts by [imm mod 32] while the model
      uses the raw [imm] (D-08).

    There is no overflow premise: a right shift never increases the
    operand, so [e_shr32_lt] gives the 32-bit bound from the [R] register
    invariant.  The fixture shift is by 8.

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** ** Generic one-step agreement *)

Theorem literal_step_SHR_agrees :
  forall (image : nat -> N) L vm prog d a imm,
    R L vm ->
    a < 16 ->
    d < 16 ->
    d <> 15 ->
    imm < 32 ->
    decode_word_p (image (l_pc L)) = Some (pSHR d a imm) ->
    nth_error prog (vm_pc vm) = Some (pSHR d a imm) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog d a imm HR Ha Hd Hd15 Himm Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  assert (Hv : e_shr32 (l_reg L a) (imm mod 32) = Nat.shiftr (l_reg L a) imm).
  { unfold e_shr32. rewrite Nat.mod_small by lia. reflexivity. }
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
      rewrite Nat.mod_small.
      * reflexivity.
      * apply e_shr32_lt. apply Hbound. lia.
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
    + rewrite set_reg_eq. rewrite Hv. apply e_shr32_lt. apply Hbound. lia.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** Decode of the fixture word *)

Lemma fixture_pc91_instr :
  nth 91 fixture_prog_full instrp_default = pSHR 2 2 8.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_91 :
  decode_word_p (literal_word_at 91) = Some (pSHR 2 2 8).
Proof.
  rewrite (decode_full_pointwise 91 ltac:(lia)).
  rewrite fixture_pc91_instr. reflexivity.
Qed.

Lemma nth_fixture_pc91 :
  nth_error fixture_prog_full 91 = Some (pSHR 2 2 8).
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligation *)

Theorem fixture_pc91_shr_decode_and_step :
  decode_word_p (literal_word_at 91) = Some (pSHR 2 2 8) /\
  forall L vm,
    R L vm ->
    l_pc L = 91 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_91.
  - intros L vm HR Hpc.
    eapply literal_step_SHR_agrees with (d := 2) (a := 2) (imm := 8).
    + exact HR.
    + lia.
    + lia.
    + lia.
    + lia.
    + rewrite Hpc. apply decode_word_image_word_91.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc91.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_SHR_agrees.
Print Assumptions fixture_pc91_shr_decode_and_step.
