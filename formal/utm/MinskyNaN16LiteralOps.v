(** * ISA-OBL-3b: ST, CMP, JMP, ADD and SUB one-step agreement

    This file extends the literal decoder/executor of
    [MinskyNaN16LiteralDecode.v] to the next control-skeleton opcodes and
    proves, for the pinned literal image, the decode and one-step
    agreement obligations for:

      word 2   ST r1,r0,100
      word 9   CMP r1,r2
      word 10  JMP[NE] 96
      word 22  ADD r3,r3,r13
      word 24  SUB r5,r5,r13
      word 47  CMP r8,r6
      word 48  JMP[GE] 81
      word 62  JMP[EQ] 67
      word 66  JMP[ALWAYS] 70

    Word 47 is the fixture's [CMP r8,r6]; word 3 of the pinned image is
    [MOVI r1,166], not a CMP.  The theorems below are named by their true
    literal PCs and [fixture_pc3_is_movi] records word 3 explicitly.

    Honest side conditions, inherited from the Coq model deltas:

    - ADD carries [l_reg a + l_reg b < 2^32] (D-03: the Coq model has no
      carry flag).
    - SUB carries [l_reg b <= l_reg a] (D-04: the Coq model truncates
      [nat] subtraction at zero).
    - JMP[EQ] and JMP[GE] carry [l_k <> 3] (D-07: the Coq truth table
      and the literal bit test differ at [k=3]).  JMP[NE] and JMP[ALWAYS]
      need no such side condition.
    - Register-writing ADD/SUB carry [d <> 15] because the Coq model
      keeps the link in [vm_link], not [vm_reg 15] (D-16).  The fixture
      ADD/SUB destinations are 3, 5 and 11, so this is discharged by
      computation.

    No [Admitted], [Axiom], or [Parameter] is used here. *)

From Coq Require Import List Arith Bool Lia NArith.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage.

Open Scope nat_scope.

(** ** Generic one-step agreement, independent of the program tail *)

Theorem literal_step_ST_agrees :
  forall (image : nat -> N) L vm prog d a imm,
    R L vm ->
    a < 16 ->
    d < 16 ->
    decode_word (image (l_pc L)) = Some (iST d a imm) ->
    nth_error prog (vm_pc vm) = Some (iST d a imm) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog d a imm HR Ha Hd Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  pose proof (R_reg_eq L vm d HR Hd) as Hreg_d.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step.
  rewrite Hdec.
  cbn [lit_exec].
  unfold exec_instr.
  rewrite Hnth.
  cbn.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi. apply Hregs. exact Hi.
  - exact Hreg15.
  - exact Hlink.
  - intro ad.
    unfold get_reg.
    rewrite Hreg_a, Hreg_d.
    destruct (Nat.eqb ad (l_reg L a + imm)) eqn:E.
    + symmetry. apply payload_word_nan_mkword. apply Hbound. exact Hd.
    + apply Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - intros i Hi. apply Hbound. exact Hi.
Qed.

Theorem literal_step_CMP_agrees :
  forall (image : nat -> N) L vm prog a b,
    R L vm ->
    a < 16 ->
    b < 16 ->
    decode_word (image (l_pc L)) = Some (iCMP a b) ->
    nth_error prog (vm_pc vm) = Some (iCMP a b) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog a b HR Ha Hb Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  pose proof (R_reg_eq L vm b HR Hb) as Hreg_b.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step.
  rewrite Hdec.
  cbn [lit_exec].
  unfold exec_instr.
  rewrite Hnth.
  cbn.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi. apply Hregs. exact Hi.
  - exact Hreg15.
  - exact Hlink.
  - intro ad. apply Hmem.
  - unfold get_reg. rewrite Hreg_a, Hreg_b. rewrite pack_k_zf. reflexivity.
  - unfold get_reg. rewrite Hreg_a, Hreg_b. rewrite pack_k_lf. reflexivity.
  - apply pack_k_lt_4.
  - exact Hhalt.
  - intros i Hi. apply Hbound. exact Hi.
Qed.

(** Changing only the PC leaves [R] intact.  This isolates the JMP case. *)
Lemma R_pc_change :
  forall L vm pc',
    R L vm ->
    R {| l_pc := pc'; l_reg := l_reg L; l_mem := l_mem L;
         l_k := l_k L; l_halted := l_halted L |}
      {| vm_pc := pc'; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
         vm_zf := vm_zf vm; vm_lf := vm_lf vm;
         vm_halted := vm_halted vm; vm_link := vm_link vm |}.
Proof.
  intros L vm pc' HR.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted].
  split_conj.
  - reflexivity.
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

Theorem literal_step_JMP_agrees_pred :
  forall (image : nat -> N) L vm prog p target,
    R L vm ->
    pred_holds p (vm_zf vm) (vm_lf vm)
      = pred_passes (pred_nat p) (l_k L) ->
    decode_word (image (l_pc L)) = Some (iJMP p target) ->
    nth_error prog (vm_pc vm) = Some (iJMP p target) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog p target HR Hpred Hdec Hnth.
  pose proof HR as HR0.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold literal_step.
  rewrite Hdec.
  cbn [lit_exec].
  unfold exec_instr.
  rewrite Hnth.
  cbn.
  rewrite Hpred, Hpcvm.
  cbn [instr_succ].
  eapply R_pc_change with
    (pc' := if pred_passes (pred_nat p) (l_k L)
            then target else S (l_pc L)).
  exact HR0.
Qed.

Theorem literal_step_JMP_agrees :
  forall (image : nat -> N) L vm prog p target,
    R L vm ->
    l_k L <> 3 ->
    decode_word (image (l_pc L)) = Some (iJMP p target) ->
    nth_error prog (vm_pc vm) = Some (iJMP p target) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog p target HR Hne Hdec Hnth.
  assert (Hpred : pred_holds p (vm_zf vm) (vm_lf vm)
                = pred_passes (pred_nat p) (l_k L)).
  { destruct HR as
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
    rewrite Hzf, Hlf. apply pred_agrees; [exact Hk | exact Hne]. }
  eapply literal_step_JMP_agrees_pred.
  - exact HR.
  - exact Hpred.
  - exact Hdec.
  - exact Hnth.
Qed.

Theorem literal_step_JMP_NE_agrees :
  forall (image : nat -> N) L vm prog target,
    R L vm ->
    decode_word (image (l_pc L)) = Some (iJMP pNE target) ->
    nth_error prog (vm_pc vm) = Some (iJMP pNE target) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog target HR Hdec Hnth.
  assert (Hpred : pred_holds pNE (vm_zf vm) (vm_lf vm)
                = pred_passes (pred_nat pNE) (l_k L)).
  { destruct HR as
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
    rewrite Hzf, Hlf. apply pred_agrees_ne. exact Hk. }
  eapply literal_step_JMP_agrees_pred.
  - exact HR.
  - exact Hpred.
  - exact Hdec.
  - exact Hnth.
Qed.

Theorem literal_step_JMP_ALWAYS_agrees :
  forall (image : nat -> N) L vm prog target,
    R L vm ->
    decode_word (image (l_pc L)) = Some (iJMP pALWAYS target) ->
    nth_error prog (vm_pc vm) = Some (iJMP pALWAYS target) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog target HR Hdec Hnth.
  assert (Hpred : pred_holds pALWAYS (vm_zf vm) (vm_lf vm)
                = pred_passes (pred_nat pALWAYS) (l_k L)).
  { destruct HR as
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
    rewrite Hzf, Hlf. apply pred_agrees_always. exact Hk. }
  eapply literal_step_JMP_agrees_pred.
  - exact HR.
  - exact Hpred.
  - exact Hdec.
  - exact Hnth.
Qed.

Theorem literal_step_ADD_agrees :
  forall (image : nat -> N) L vm prog d a b,
    R L vm ->
    a < 16 ->
    b < 16 ->
    d < 16 ->
    d <> 15 ->
    l_reg L a + l_reg L b < 2 ^ 32 ->
    decode_word (image (l_pc L)) = Some (iADD d a b) ->
    nth_error prog (vm_pc vm) = Some (iADD d a b) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog d a b HR Ha Hb Hd Hd15 Hnc Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  pose proof (R_reg_eq L vm b HR Hb) as Hreg_b.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  assert (Hsum : vm_reg vm a + vm_reg vm b
               = l_reg L a + l_reg L b).
  { rewrite Hreg_a, Hreg_b. reflexivity. }
  assert (Hmod : (l_reg L a + l_reg L b) mod 2 ^ 32
               = l_reg L a + l_reg L b).
  { apply Nat.mod_small. exact Hnc. }
  assert (Hcarry : Nat.leb (2 ^ 32) (l_reg L a + l_reg L b) = false).
  { destruct (Nat.leb (2 ^ 32) (l_reg L a + l_reg L b)) eqn:E;
      [|reflexivity].
    apply Nat.leb_le in E. lia. }
  unfold literal_step.
  rewrite Hdec.
  cbn [lit_exec].
  unfold exec_instr.
  rewrite Hnth.
  cbn [l_pc l_reg l_mem l_k l_halted
       vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       instr_succ get_reg].
  unfold get_reg. rewrite Hsum, Hmod, Hcarry.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite !set_reg_eq. repeat rewrite Hmod. reflexivity.
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
    + rewrite set_reg_eq. exact Hnc.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

Theorem literal_step_SUB_agrees :
  forall (image : nat -> N) L vm prog d a b,
    R L vm ->
    a < 16 ->
    b < 16 ->
    d < 16 ->
    d <> 15 ->
    l_reg L b <= l_reg L a ->
    decode_word (image (l_pc L)) = Some (iSUB d a b) ->
    nth_error prog (vm_pc vm) = Some (iSUB d a b) ->
    R (literal_step image L) (exec_instr prog vm).
Proof.
  intros image L vm prog d a b HR Ha Hb Hd Hd15 Hle Hdec Hnth.
  pose proof (R_reg_eq L vm a HR Ha) as Hreg_a.
  pose proof (R_reg_eq L vm b HR Hb) as Hreg_b.
  destruct HR as
    (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  assert (Hsub : vm_reg vm a - vm_reg vm b = l_reg L a - l_reg L b).
  { rewrite Hreg_a, Hreg_b. reflexivity. }
  assert (Hdiff : l_reg L a - l_reg L b < 2 ^ 32).
  { pose proof (Hbound a Ha). lia. }
  assert (Hmod : (l_reg L a - l_reg L b) mod 2 ^ 32
               = l_reg L a - l_reg L b).
  { apply Nat.mod_small. exact Hdiff. }
  unfold literal_step.
  rewrite Hdec.
  cbn [lit_exec].
  unfold exec_instr.
  rewrite Hnth.
  cbn [l_pc l_reg l_mem l_k l_halted
       vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       instr_succ get_reg].
  unfold get_reg. rewrite Hsub, Hmod.
  unfold R.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
  split_conj.
  - rewrite Hpcvm. reflexivity.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite !set_reg_eq. repeat rewrite Hmod. reflexivity.
    + rewrite !set_reg_neq by exact Hne. apply Hregs. exact Hi.
  - rewrite !set_reg_neq by lia. exact Hreg15.
  - rewrite set_reg_neq by lia. exact Hlink.
  - intro ad. apply Hmem.
  - rewrite pack_k_zf. reflexivity.
  - rewrite Hreg_a, Hreg_b. rewrite pack_k_lf. reflexivity.
  - apply pack_k_lt_4.
  - exact Hhalt.
  - intros i Hi.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq. exact Hdiff.
    + rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** The concrete fixture prefix and its selected words *)

Definition fixture_prog_0_66 : list Instr :=
  slice_main ++ slice_run100 ++ slice_step_prelude ++ slice_scan.

Lemma lit_CMP_k_lt_3 :
  forall L a b, l_k (lit_exec L (iCMP a b)) < 3.
Proof.
  intros L a b.
  cbn [lit_exec].
  set (A := l_reg L a). set (B := l_reg L b).
  destruct (Nat.eqb A B) eqn:E;
    destruct (Nat.ltb A B) eqn:E2; cbn; try lia.
  exfalso. apply Nat.eqb_eq in E. apply Nat.ltb_lt in E2. lia.
Qed.

Lemma lit_CMP_k_ne_3 :
  forall L a b, l_k (lit_exec L (iCMP a b)) <> 3.
Proof.
  intros L a b. pose proof (lit_CMP_k_lt_3 L a b). lia.
Qed.

Lemma R_pc : forall L vm, R L vm -> vm_pc vm = l_pc L.
Proof. intros L vm HR. destruct HR as (Hpc & _). exact Hpc. Qed.

Lemma nth_fixture_pc2 :
  nth_error fixture_prog_0_66 2 = Some (iST 1 0 100).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc3 :
  nth_error fixture_prog_0_66 3 = Some (iMOVI 1 166).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc9 :
  nth_error fixture_prog_0_66 9 = Some (iCMP 1 2).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc10 :
  nth_error fixture_prog_0_66 10 = Some (iJMP pNE 96).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc22 :
  nth_error fixture_prog_0_66 22 = Some (iADD 3 3 13).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc24 :
  nth_error fixture_prog_0_66 24 = Some (iSUB 5 5 13).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc47 :
  nth_error fixture_prog_0_66 47 = Some (iCMP 8 6).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc48 :
  nth_error fixture_prog_0_66 48 = Some (iJMP pGE 81).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc62 :
  nth_error fixture_prog_0_66 62 = Some (iJMP pEQ 67).
Proof. vm_compute. reflexivity. Qed.

Lemma nth_fixture_pc66 :
  nth_error fixture_prog_0_66 66 = Some (iJMP pALWAYS 70).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_2 :
  decode_word (literal_word_at 2) = Some (iST 1 0 100).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_3 :
  decode_word (literal_word_at 3) = Some (iMOVI 1 166).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_9 :
  decode_word (literal_word_at 9) = Some (iCMP 1 2).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_10 :
  decode_word (literal_word_at 10) = Some (iJMP pNE 96).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_22 :
  decode_word (literal_word_at 22) = Some (iADD 3 3 13).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_24 :
  decode_word (literal_word_at 24) = Some (iSUB 5 5 13).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_47 :
  decode_word (literal_word_at 47) = Some (iCMP 8 6).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_48 :
  decode_word (literal_word_at 48) = Some (iJMP pGE 81).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_62 :
  decode_word (literal_word_at 62) = Some (iJMP pEQ 67).
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_image_word_66 :
  decode_word (literal_word_at 66) = Some (iJMP pALWAYS 70).
Proof. vm_compute. reflexivity. Qed.

(** ** Packaged fixture obligations *)

Theorem fixture_pc2_st_decode_and_step :
  decode_word (literal_word_at 2) = Some (iST 1 0 100) /\
  forall L vm,
    R L vm ->
    l_pc L = 2 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_2.
  - intros L vm HR Hpc.
    eapply literal_step_ST_agrees with (d := 1) (a := 0) (imm := 100).
    + exact HR.
    + lia.
    + lia.
    + rewrite Hpc. apply decode_word_image_word_2.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc2.
Qed.

Theorem fixture_pc3_is_movi :
  decode_word (literal_word_at 3) = Some (iMOVI 1 166) /\
  nth_error fixture_prog_0_66 3 = Some (iMOVI 1 166).
Proof.
  split; [apply decode_word_image_word_3 | apply nth_fixture_pc3].
Qed.

Theorem fixture_pc9_cmp_decode_and_step :
  decode_word (literal_word_at 9) = Some (iCMP 1 2) /\
  forall L vm,
    R L vm ->
    l_pc L = 9 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_9.
  - intros L vm HR Hpc.
    eapply literal_step_CMP_agrees with (a := 1) (b := 2).
    + exact HR.
    + lia.
    + lia.
    + rewrite Hpc. apply decode_word_image_word_9.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc9.
Qed.

Theorem fixture_pc10_jmp_ne_decode_and_step :
  decode_word (literal_word_at 10) = Some (iJMP pNE 96) /\
  forall L vm,
    R L vm ->
    l_pc L = 10 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_10.
  - intros L vm HR Hpc.
    eapply literal_step_JMP_NE_agrees.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_10.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc10.
Qed.

Theorem fixture_pc22_add_decode_and_step :
  decode_word (literal_word_at 22) = Some (iADD 3 3 13) /\
  forall L vm,
    R L vm ->
    l_pc L = 22 ->
    l_reg L 3 + l_reg L 13 < 2 ^ 32 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_22.
  - intros L vm HR Hpc Hnc.
    eapply literal_step_ADD_agrees with (d := 3) (a := 3) (b := 13).
    + exact HR.
    + lia.
    + lia.
    + lia.
    + lia.
    + exact Hnc.
    + rewrite Hpc. apply decode_word_image_word_22.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc22.
Qed.

Theorem fixture_pc24_sub_decode_and_step :
  decode_word (literal_word_at 24) = Some (iSUB 5 5 13) /\
  forall L vm,
    R L vm ->
    l_pc L = 24 ->
    l_reg L 13 <= l_reg L 5 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_24.
  - intros L vm HR Hpc Hle.
    eapply literal_step_SUB_agrees with (d := 5) (a := 5) (b := 13).
    + exact HR.
    + lia.
    + lia.
    + lia.
    + lia.
    + exact Hle.
    + rewrite Hpc. apply decode_word_image_word_24.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc24.
Qed.

Theorem fixture_pc47_cmp86_decode_and_step :
  decode_word (literal_word_at 47) = Some (iCMP 8 6) /\
  forall L vm,
    R L vm ->
    l_pc L = 47 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_47.
  - intros L vm HR Hpc.
    eapply literal_step_CMP_agrees with (a := 8) (b := 6).
    + exact HR.
    + lia.
    + lia.
    + rewrite Hpc. apply decode_word_image_word_47.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc47.
Qed.

Theorem fixture_pc48_jmp_ge_decode_and_step :
  decode_word (literal_word_at 48) = Some (iJMP pGE 81) /\
  forall L vm,
    R L vm ->
    l_pc L = 48 ->
    l_k L <> 3 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_48.
  - intros L vm HR Hpc Hne.
    eapply literal_step_JMP_agrees.
    + exact HR.
    + exact Hne.
    + rewrite Hpc. apply decode_word_image_word_48.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc48.
Qed.

Theorem fixture_pc62_jmp_eq_decode_and_step :
  decode_word (literal_word_at 62) = Some (iJMP pEQ 67) /\
  forall L vm,
    R L vm ->
    l_pc L = 62 ->
    l_k L <> 3 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_62.
  - intros L vm HR Hpc Hne.
    eapply literal_step_JMP_agrees.
    + exact HR.
    + exact Hne.
    + rewrite Hpc. apply decode_word_image_word_62.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc62.
Qed.

Theorem fixture_pc66_jmp_always_decode_and_step :
  decode_word (literal_word_at 66) = Some (iJMP pALWAYS 70) /\
  forall L vm,
    R L vm ->
    l_pc L = 66 ->
    R (literal_step literal_word_at L)
      (exec_instr fixture_prog_0_66 vm).
Proof.
  split.
  - apply decode_word_image_word_66.
  - intros L vm HR Hpc.
    eapply literal_step_JMP_ALWAYS_agrees.
    + exact HR.
    + rewrite Hpc. apply decode_word_image_word_66.
    + rewrite (R_pc L vm HR), Hpc. apply nth_fixture_pc66.
Qed.

