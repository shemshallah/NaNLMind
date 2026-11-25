(** * ISA-OBL-3e CALL 0x0B: decode and one-step agreement

    CALL is opcode 0x0B.  The fixture has four calls:

       6  FFF8_0B00001D_F8FF  CALL 29
      27  FFF8_0B000054_F8FF  CALL 84
      31  FFF8_0B000024_F8FF  CALL 36
      97  FFF8_0B000054_F8FF  CALL 84

    Both machines agree on where CALL goes and both install the return
    address [pc + 1], but they keep the link in different places:

    - the literal ISA writes [r15 := pc + 1];
    - the Coq model writes [vm_link := pc + 1] and leaves [vm_reg 15]
      unchanged.

    The relation [R] ties *both* [vm_link] and [vm_reg 15] to the
    literal [r15] (D-16).  Consequently the full-[R] agreement theorem
    carries an explicit link-coherence premise

      [l_reg L 15 = S (l_pc L)]

    saying the literal link register already holds the return address the
    call installs.  This premise is false at the fixture's first call
    (the reset state has [r15 = 0], the call installs 7), so it is a real
    delta, not a bookkeeping artifact.

    The unconditional statement is [literal_step_CALL_agrees_no15]: it
    preserves every clause of [R] except the disputed [vm_reg 15] clause,
    using [R_no15] from [MinskyNaN16LiteralExec.v].  This is the form the
    concrete fixture obligations use.

    Register/PC side conditions:

    - [S (l_pc L) < 2 ^ 32]: the installed return address is a 32-bit
      literal register value;
    - [d <> 15] does not occur because CALL has no destination field.

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** Concrete return addresses in this file are below 128; this turns
    that into the 32-bit bound without normalizing [2 ^ 32] in [nat]. *)
Lemma lt_two32_of_lt_128 : forall k, k < 128 -> k < 2 ^ 32.
Proof.
  intros k Hk.
  apply Nat.lt_le_trans with (m := 128).
  - exact Hk.
  - change (2 ^ 7 <= 2 ^ 32).
    apply Nat.pow_le_mono_r; lia.
Qed.

(** ** Unconditional agreement modulo the [vm_reg 15] clause *)

Theorem literal_step_CALL_agrees_no15 :
  forall (image : nat -> N) L vm prog target,
    R_no15 L vm ->
    S (l_pc L) < 2 ^ 32 ->
    decode_word_p (image (l_pc L)) = Some (pCALL target) ->
    nth_error prog (vm_pc vm) = Some (pCALL target) ->
    R_no15 (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog target HR Hret Hdec Hnth.
  destruct HR as
    (Hpcvm & Hregs & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step_p.
  rewrite Hdec.
  cbn [lit_exec_p].
  unfold exec_instr_p.
  rewrite Hnth.
  cbn [exec_instr_p].
  unfold R_no15.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ].
  split_conj.
  - reflexivity.
  - intros i Hi.
    rewrite set_reg_neq by lia. apply Hregs. exact Hi.
  - rewrite Hpcvm, set_reg_eq. reflexivity.
  - intro ad. apply Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - intros i Hi.
    destruct (Nat.eq_dec i 15) as [-> | Hne].
    + rewrite set_reg_eq. exact Hret.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** Full [R] agreement under link coherence (extended model) *)

Theorem literal_step_CALL_agrees_ext :
  forall (image : nat -> N) L vm prog target,
    R L vm ->
    S (l_pc L) < 2 ^ 32 ->
    l_reg L 15 = S (l_pc L) ->
    decode_word_p (image (l_pc L)) = Some (pCALL target) ->
    nth_error prog (vm_pc vm) = Some (pCALL target) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog target HR Hret Hcoh Hdec Hnth.
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
       l_pc l_reg l_mem l_k l_halted instr_succ].
  split_conj.
  - reflexivity.
  - intros i Hi.
    rewrite set_reg_neq by lia. apply Hregs. exact Hi.
  - rewrite set_reg_eq. rewrite Hreg15, Hcoh. reflexivity.
  - rewrite Hpcvm, set_reg_eq. reflexivity.
  - intro ad. apply Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - intros i Hi.
    destruct (Nat.eq_dec i 15) as [-> | Hne].
    + rewrite set_reg_eq. exact Hret.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** Full [R] agreement against the pre-existing [Instr] model *)

Theorem literal_step_CALL_agrees :
  forall (image : nat -> N) L vm prog target,
    R L vm ->
    S (l_pc L) < 2 ^ 32 ->
    l_reg L 15 = S (l_pc L) ->
    decode_word_p (image (l_pc L)) = Some (pCALL target) ->
    nth_error prog (vm_pc vm) = Some (iCALL target) ->
    R (literal_step_p image L) (exec_instr prog vm).
Proof.
  intros image L vm prog target HR Hret Hcoh Hdec Hnth.
  rewrite <- exec_instr_p_embed.
  eapply literal_step_CALL_agrees_ext.
  - exact HR.
  - exact Hret.
  - exact Hcoh.
  - exact Hdec.
  - rewrite nth_error_map, Hnth. reflexivity.
Qed.

(** ** Decode of the four fixture calls *)

Lemma fixture_pc6_instr :
  nth 6 fixture_prog_full instrp_default = pCALL 29.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc27_instr :
  nth 27 fixture_prog_full instrp_default = pCALL 84.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc31_instr :
  nth 31 fixture_prog_full instrp_default = pCALL 36.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_pc97_instr :
  nth 97 fixture_prog_full instrp_default = pCALL 84.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_6 :
  decode_word_p (literal_word_at 6) = Some (pCALL 29).
Proof.
  rewrite (decode_full_pointwise 6 ltac:(lia)).
  rewrite fixture_pc6_instr. reflexivity.
Qed.

Lemma decode_word_image_word_27 :
  decode_word_p (literal_word_at 27) = Some (pCALL 84).
Proof.
  rewrite (decode_full_pointwise 27 ltac:(lia)).
  rewrite fixture_pc27_instr. reflexivity.
Qed.

Lemma decode_word_image_word_31 :
  decode_word_p (literal_word_at 31) = Some (pCALL 36).
Proof.
  rewrite (decode_full_pointwise 31 ltac:(lia)).
  rewrite fixture_pc31_instr. reflexivity.
Qed.

Lemma decode_word_image_word_97 :
  decode_word_p (literal_word_at 97) = Some (pCALL 84).
Proof.
  rewrite (decode_full_pointwise 97 ltac:(lia)).
  rewrite fixture_pc97_instr. reflexivity.
Qed.

Lemma nth_fixture_pc6 :
  nth_error fixture_prog_full 6 = Some (pCALL 29).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc27 :
  nth_error fixture_prog_full 27 = Some (pCALL 84).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc31 :
  nth_error fixture_prog_full 31 = Some (pCALL 36).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc97 :
  nth_error fixture_prog_full 97 = Some (pCALL 84).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_0_66_pc6 :
  nth_error fixture_prog_0_66 6 = Some (iCALL 29).
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligations *)

Theorem fixture_pc6_call_decode_and_step :
  decode_word_p (literal_word_at 6) = Some (pCALL 29) /\
  forall L vm,
    R L vm ->
    l_pc L = 6 ->
    R_no15 (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_6.
  - intros L vm HR Hpc.
    eapply literal_step_CALL_agrees_no15 with (target := 29).
    + apply R_R_no15. exact HR.
    + rewrite Hpc. apply lt_two32_of_lt_128. lia.
    + rewrite Hpc. apply decode_word_image_word_6.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc6.
Qed.

Theorem fixture_pc27_call_decode_and_step :
  decode_word_p (literal_word_at 27) = Some (pCALL 84) /\
  forall L vm,
    R L vm ->
    l_pc L = 27 ->
    R_no15 (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_27.
  - intros L vm HR Hpc.
    eapply literal_step_CALL_agrees_no15 with (target := 84).
    + apply R_R_no15. exact HR.
    + rewrite Hpc. apply lt_two32_of_lt_128. lia.
    + rewrite Hpc. apply decode_word_image_word_27.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc27.
Qed.

Theorem fixture_pc31_call_decode_and_step :
  decode_word_p (literal_word_at 31) = Some (pCALL 36) /\
  forall L vm,
    R L vm ->
    l_pc L = 31 ->
    R_no15 (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_31.
  - intros L vm HR Hpc.
    eapply literal_step_CALL_agrees_no15 with (target := 36).
    + apply R_R_no15. exact HR.
    + rewrite Hpc. apply lt_two32_of_lt_128. lia.
    + rewrite Hpc. apply decode_word_image_word_31.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc31.
Qed.

Theorem fixture_pc97_call_decode_and_step :
  decode_word_p (literal_word_at 97) = Some (pCALL 84) /\
  forall L vm,
    R L vm ->
    l_pc L = 97 ->
    R_no15 (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_97.
  - intros L vm HR Hpc.
    eapply literal_step_CALL_agrees_no15 with (target := 84).
    + apply R_R_no15. exact HR.
    + rewrite Hpc. apply lt_two32_of_lt_128. lia.
    + rewrite Hpc. apply decode_word_image_word_97.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc97.
Qed.

(** The full-[R] statement at word 6, with its link-coherence premise
    explicit.  The fixture reset state does *not* satisfy it, which is
    the D-16 delta recorded in the module header. *)
Theorem fixture_pc6_call_agrees_model :
  decode_word_p (literal_word_at 6) = Some (pCALL 29) /\
  forall L vm,
    R L vm ->
    l_pc L = 6 ->
    l_reg L 15 = 7 ->
    R (literal_step_p literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_6.
  - intros L vm HR Hpc Hr15.
    eapply literal_step_CALL_agrees with (target := 29).
    + exact HR.
    + rewrite Hpc. apply lt_two32_of_lt_128. lia.
    + rewrite Hpc, Hr15. reflexivity.
    + rewrite Hpc. apply decode_word_image_word_6.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_0_66_pc6.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_CALL_agrees_no15.
Print Assumptions literal_step_CALL_agrees_ext.
Print Assumptions literal_step_CALL_agrees.
Print Assumptions fixture_pc6_call_decode_and_step.
