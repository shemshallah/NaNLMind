(** * ISA-OBL-3e PUTC 0x15: decode and one-step agreement

    PUTC is opcode 0x15; the fixture has one PUTC, in the [puts] block:

      90  FFF8_15500000_F8FF  PUTC r5

    PUTC is the one ISA action whose effect has no field in the Coq VM
    model: [VM] has PC, registers, memory, flags, halt and link, but no
    output channel.  The extended model [exec_instr_p] therefore models
    PUTC as a PC advance only.  The [R]-preservation theorem
    [literal_step_PUTC_agrees] accordingly covers the *entire* modelled
    state: after the step, PC has advanced and every other [R] clause is
    unchanged.

    The output effect itself is proved on the concrete literal machine
    [LPState] of [MinskyNaN16LiteralStep.v], which does carry
    [lp_out]:

    - [lp_putc_out]: one [pPUTC] appends the low byte of [r[d]] to the
      output string;
    - [lp_step_pc90_out]: at fixture PC 90, one real [lp_step] appends
      exactly that byte, using the code-intact hypothesis for the pinned
      image;
    - [putc_byte_eq]: the ISA's [N.land _ 255] byte selection is the
      [nat] low-byte operation [mod 256].

    So the modelled-state agreement is complete, and the unmodelled
    output delta is discharged at the concrete machine level.  The
    remaining limitation is representational: the Coq VM cannot state a
    PUTC output theorem, because it has no output field.

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps MinskyNaN16LiteralStep.

Open Scope nat_scope.
Open Scope string_scope.

(** ** The low-byte selection *)

Lemma putc_byte_eq :
  forall x : N, N.to_nat (N.land x 255%N) = N.to_nat x mod 256.
Proof.
  intro x.
  replace 255%N with (N.ones 8) by reflexivity.
  rewrite N.land_ones.
  rewrite N2Nat.inj_mod.
  rewrite N2Nat.inj_pow.
  cbn. reflexivity.
Qed.

(** ** One-step [R] agreement (modelled state) *)

Theorem literal_step_PUTC_agrees :
  forall (image : nat -> N) L vm prog d,
    R L vm ->
    d < 16 ->
    decode_word_p (image (l_pc L)) = Some (pPUTC d) ->
    nth_error prog (vm_pc vm) = Some (pPUTC d) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog d HR Hd Hdec Hnth.
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
  - rewrite Hpcvm. reflexivity.
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

(** ** Decode of the fixture word *)

Lemma fixture_pc90_instr :
  nth 90 fixture_prog_full instrp_default = pPUTC 5.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_90 :
  decode_word_p (literal_word_at 90) = Some (pPUTC 5).
Proof.
  rewrite (decode_full_pointwise 90 ltac:(lia)).
  rewrite fixture_pc90_instr. reflexivity.
Qed.

Lemma nth_fixture_pc90 :
  nth_error fixture_prog_full 90 = Some (pPUTC 5).
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligation (modelled state) *)

Theorem fixture_pc90_putc_decode_and_step :
  decode_word_p (literal_word_at 90) = Some (pPUTC 5) /\
  forall L vm,
    R L vm ->
    l_pc L = 90 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_90.
  - intros L vm HR Hpc.
    eapply literal_step_PUTC_agrees with (d := 5).
    + exact HR.
    + lia.
    + rewrite Hpc. apply decode_word_image_word_90.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc90.
Qed.

(** ** Output effect on the concrete literal machine *)

Lemma lp_putc_out :
  forall (L : LPState) d,
    lp_out (lp_exec L (pPUTC d)) =
    append (lp_out L)
      (String (Ascii.ascii_of_nat (lget_reg (lp_reg L) d mod 256))
              EmptyString).
Proof.
  intros L d.
  cbn [lp_exec lget_reg].
  rewrite putc_byte_eq.
  reflexivity.
Qed.

Lemma lp_putc_frame :
  forall (L : LPState) d,
    lp_pc (lp_exec L (pPUTC d)) = S (lp_pc L) /\
    lp_reg (lp_exec L (pPUTC d)) = lp_reg L /\
    lp_mem (lp_exec L (pPUTC d)) = lp_mem L /\
    lp_k (lp_exec L (pPUTC d)) = lp_k L /\
    lp_halted (lp_exec L (pPUTC d)) = lp_halted L.
Proof.
  intros L d. cbn [lp_exec]. repeat split; reflexivity.
Qed.

(** At fixture PC 90 the real step appends the low byte of [r5]. *)
Theorem lp_step_pc90_out :
  forall L,
    code_intact (lp_mem L) ->
    lp_pc L = 90 ->
    lp_out (lp_step L) =
    append (lp_out L)
      (String (Ascii.ascii_of_nat (lget_reg (lp_reg L) 5 mod 256))
              EmptyString).
Proof.
  intros L Hc Hpc.
  unfold lp_step.
  rewrite Hpc.
  rewrite (Hc 90 ltac:(lia)).
  rewrite (decode_full_pointwise 90 ltac:(lia)).
  rewrite fixture_pc90_instr.
  apply lp_putc_out.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_PUTC_agrees.
Print Assumptions fixture_pc90_putc_decode_and_step.
Print Assumptions lp_putc_out.
Print Assumptions lp_step_pc90_out.
