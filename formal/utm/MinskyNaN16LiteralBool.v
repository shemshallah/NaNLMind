(** * ISA-OBL-3e BOOL 0x00: decode and one-step agreement

    BOOL is opcode 0x00; the fixture contains exactly one BOOL, the
    [BOOL.8] of the [puts] block:

      87  7FF8_00520004_F17F  BOOL.8 r5,r2,r4

    The pre-existing [Instr] model has no BOOL constructor, so the
    agreement statement uses the extended model [exec_instr_p]
    ([pBOOL]) of [MinskyNaN16LiteralExec.v].  Both machines use the
    same four-bit truth-table function [e_bool_res]; the content of the
    proof is the register plumbing, the 32-bit bound of the result
    ([e_bool_res_lt_two32]), and the BOOL.8 reduction to conjunction
    ([e_bool_res_8]) and to a low-byte mask ([e_bool_res_8_255]).

    Side conditions:

    - [a < 16], [b < 16], [d < 16]: register-index range of the literal
      list;
    - [d <> 15]: D-16, the model keeps the link in [vm_link].

    There is no shift or overflow premise: the truth-table result is
    masked to 32 bits by construction.

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralOps.

Open Scope nat_scope.

(** Small concrete numerals stay below [2 ^ 32]; this avoids ever
    normalizing the unary numeral [2 ^ 32] itself. *)
Lemma lt_two32_of_lt_128_bool : forall k, k < 128 -> k < 2 ^ 32.
Proof.
  intros k Hk.
  apply Nat.lt_le_trans with (m := 128).
  - exact Hk.
  - change (2 ^ 7 <= 2 ^ 32).
    apply Nat.pow_le_mono_r; lia.
Qed.

(** ** Generic one-step agreement *)

Theorem literal_step_BOOL_agrees :
  forall (image : nat -> N) L vm prog tbl d a b,
    R L vm ->
    a < 16 ->
    b < 16 ->
    d < 16 ->
    d <> 15 ->
    decode_word_p (image (l_pc L)) = Some (pBOOL tbl d a b) ->
    nth_error prog (vm_pc vm) = Some (pBOOL tbl d a b) ->
    R (literal_step_p image L) (exec_instr_p prog vm).
Proof.
  intros image L vm prog tbl d a b HR Ha Hb Hd Hd15 Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  pose proof (R_reg_eq L vm b HR Hb) as Hreg_b.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step_p.
  rewrite Hdec.
  cbn [lit_exec_p].
  unfold exec_instr_p.
  rewrite Hnth.
  cbn [exec_instr_p].
  unfold get_reg.
  rewrite Hreg_a, Hreg_b.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite !set_reg_eq.
      rewrite Nat.mod_small.
      * reflexivity.
      * apply e_bool_res_lt_two32.
    + rewrite !set_reg_neq by exact Hne. apply Hregs. exact Hi.
  - rewrite !set_reg_neq by lia. exact Hreg15.
  - rewrite set_reg_neq by lia. exact Hlink.
  - intro ad. apply Hmem.
  - rewrite pack_k_zf. reflexivity.
  - rewrite pack_k_lf. reflexivity.
  - apply pack_k_lt_4.
  - exact Hhalt.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq. apply e_bool_res_lt_two32.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** BOOL.8 arithmetic checks *)

(** The fixture's truth table is the conjunction. *)
Lemma fixture_bool8_is_conj :
  forall a b, a < 2 ^ 32 -> e_bool_res 8 a b = Nat.land a b.
Proof. apply e_bool_res_8. Qed.

(** The fixture mask [r4 = 255] turns the conjunction into the low byte. *)
Lemma fixture_bool8_is_low_byte :
  forall a, a < 2 ^ 32 -> e_bool_res 8 a 255 = a mod 256.
Proof. apply e_bool_res_8_255. Qed.

(** A concrete value check: the small instance [BOOL.8 5 4] is 4. *)
Lemma fixture_bool8_small :
  e_bool_res 8 5 4 = 4.
Proof.
  rewrite e_bool_res_8.
  - reflexivity.
  - apply lt_two32_of_lt_128_bool. lia.
Qed.

(** ** Decode of the fixture word *)

Lemma fixture_pc87_instr :
  nth 87 fixture_prog_full instrp_default = pBOOL 8 5 2 4.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_87 :
  decode_word_p (literal_word_at 87) = Some (pBOOL 8 5 2 4).
Proof.
  rewrite (decode_full_pointwise 87 ltac:(lia)).
  rewrite fixture_pc87_instr. reflexivity.
Qed.

Lemma nth_fixture_pc87 :
  nth_error fixture_prog_full 87 = Some (pBOOL 8 5 2 4).
Proof. vm_compute. reflexivity. Qed.

(** ** Concrete fixture obligation *)

Theorem fixture_pc87_bool_decode_and_step :
  decode_word_p (literal_word_at 87) = Some (pBOOL 8 5 2 4) /\
  e_bool_res 8 5 4 = 4 /\
  forall L vm,
    R L vm ->
    l_pc L = 87 ->
    R (literal_step_p literal_word_at L)
      (exec_instr_p fixture_prog_full vm).
Proof.
  split.
  - apply decode_word_image_word_87.
  - split.
    + apply fixture_bool8_small.
    + intros L vm HR Hpc.
      eapply literal_step_BOOL_agrees with (tbl := 8) (d := 5) (a := 2) (b := 4).
      * exact HR.
      * lia.
      * lia.
      * lia.
      * lia.
      * rewrite Hpc. apply decode_word_image_word_87.
      * rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc87.
Qed.

(** Assumption audit *)

Print Assumptions literal_step_BOOL_agrees.
Print Assumptions fixture_bool8_is_conj.
Print Assumptions fixture_pc87_bool_decode_and_step.
