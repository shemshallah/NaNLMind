(** * ISA-OBL-3e base: extended literal executor and extended Coq model

    [MinskyNaN16LiteralPuts.v] decodes the full literal code region
    [0,99) to the instruction type [InstrP], whose opcode list is

      MOVI, LD, ST, CMP, JMP[p], CALL, RET, ADD, SUB, SHL, SHR, BOOL,
      PUTC, predicated RET, HALT.

    [MinskyNaN16LiteralDecode.v] defines the literal machine [LState] and
    the relation [R] to the Coq VM of [MinskyNaN16VM.v], but its executor
    [lit_exec] and its decoder [decode_word] only cover the seven opcodes
    MOVI/LD/ST/CMP/JMP/ADD/SUB.  [MinskyNaN16LiteralOps.v] proves the
    one-step obligations of ST/CMP/JMP/ADD/SUB against the Coq model.

    This file is the shared base for the remaining raw-NaN opcodes:

      SHL 0x05, SHR 0x06, CALL 0x0B, RET 0x0C (plain and predicated),
      BOOL/BOOL.8 0x00, PUTC 0x15, HALT 0xFF.

    It contributes three things.

    1. [lit_exec_p] is the [InstrP]-typed extension of [lit_exec] on the
       same [LState].  It is a conservative extension on the seven
       opcodes already handled by [lit_exec] (lemma
       [lit_exec_p_embed_core]); on the other four the old [lit_exec] was
       the identity catch-all, while [lit_exec_p] now performs the ISA
       action.  [literal_step_p] is the corresponding full decoder/step.

    2. [exec_instr_p] is the Coq-side model for the full [InstrP] stream.
       On the eleven constructors of [Instr] it is *definitionally* the
       existing [exec_instr] of [MinskyNaN16VM.v] (lemma
       [exec_instr_p_embed]), so it does not revise any previously
       checked VM behaviour.  The four constructors absent from [Instr]
       (SHR, BOOL, PUTC, predicated RET) are specified here from the
       NAN0S ISA text: logical right shift, the four-bit BOOL truth
       table, low-byte output, and predicated return through the link.

       The Coq VM has no output channel, so model-side PUTC advances the
       PC and leaves every modelled field unchanged.  The literal output
       effect is proved separately in [MinskyNaN16LiteralPutc.v] on the
       concrete machine [LPState], which does carry [lp_out].

    3. The 32-bit arithmetic used by the new opcodes is defined once, at
       [nat] level, and shared by [lit_exec_p] and [exec_instr_p]:
       [e_shl32], [e_shr32], [e_bnot32], [e_bool_res].  The two masking
       identities that connect them to the unbounded Coq model are
       [e_shl32_eq] (needs the no-overflow side condition) and
       [e_shr32_lt].  The BOOL result is masked by construction, so it is
       always a 32-bit word ([e_bool_res_lt_two32]); for the fixture's
       BOOL.8 it is exactly [Nat.land a b] ([e_bool_res_8]) and with the
       fixture mask 255 it is the low byte ([e_bool_res_8_255]).

    No [Admitted], [Axiom], or [Parameter] is used in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralPuts.

Open Scope nat_scope.

(** ** 32-bit arithmetic for the new opcodes

    [e_mask32] is the 32-bit mask [2^32 - 1].  The operations are
    spelled with [Nat.land]/[Nat.lor]/[Nat.lxor]/[Nat.shiftl] and the
    mask, so they are executable by the kernel and provably 32-bit. *)

Definition e_mask32 : nat := Nat.ones 32.

Definition e_shl32 (a n : nat) : nat :=
  Nat.land (Nat.shiftl a n) e_mask32.

Definition e_shr32 (a n : nat) : nat :=
  Nat.shiftr a n.

Definition e_bnot32 (x : nat) : nat :=
  Nat.land (Nat.lxor x e_mask32) e_mask32.

(** The four products are the four disjoint bit classes selected by the
    four-bit ISA truth table [tbl].  The final mask keeps the definition
    total for arbitrary [tbl] and makes the result a 32-bit word. *)
Definition e_bool_res (tbl a b : nat) : nat :=
  Nat.land
    ((if Nat.eqb (Nat.land tbl 1) 1 then e_bnot32 (Nat.lor a b) else 0) +
     ((if Nat.eqb (Nat.land tbl 2) 2 then Nat.land (e_bnot32 a) b else 0) +
      ((if Nat.eqb (Nat.land tbl 4) 4 then Nat.land a (e_bnot32 b) else 0) +
       (if Nat.eqb (Nat.land tbl 8) 8 then Nat.land a b else 0))))
    e_mask32.

Lemma e_mask32_bound : e_mask32 < 2 ^ 32.
Proof.
  unfold e_mask32. rewrite Nat.ones_equiv.
  pose proof (Nat.pow_nonzero 2 32 ltac:(lia)) as Hnz.
  lia.
Qed.

(** Left shift: the literal result is the masked shift; the Coq model
    shift is unbounded.  The bridge is exactly a no-overflow premise. *)
Lemma e_shl32_eq :
  forall a n, Nat.shiftl a n < 2 ^ 32 -> e_shl32 a n = Nat.shiftl a n.
Proof.
  intros a n H.
  unfold e_shl32, e_mask32.
  rewrite Nat.land_ones.
  apply Nat.mod_small. exact H.
Qed.

(** Right shift never increases a value, so no overflow premise is
    needed and the masked literal result is already < 2^32. *)
Lemma e_shr32_lt :
  forall a n, a < 2 ^ 32 -> e_shr32 a n < 2 ^ 32.
Proof.
  intros a n H. unfold e_shr32.
  eapply Nat.le_lt_trans.
  - apply Nat.shiftr_upper_bound.
  - exact H.
Qed.

Lemma e_bool_res_lt_two32 :
  forall tbl a b, e_bool_res tbl a b < 2 ^ 32.
Proof.
  intros tbl a b. unfold e_bool_res.
  eapply Nat.le_lt_trans.
  - apply Nat.land_le_r.
  - apply e_mask32_bound.
Qed.

(** The BOOL.8 truth table selects only the last product, so the result
    is the bitwise conjunction.  The bound on [a] is the 32-bit register
    invariant of [R]; [Nat.land a b <= a]. *)
Lemma e_bool_res_8 :
  forall a b, a < 2 ^ 32 -> e_bool_res 8 a b = Nat.land a b.
Proof.
  intros a b Ha.
  unfold e_bool_res.
  replace (Nat.land 8 1) with 0 by reflexivity.
  replace (Nat.land 8 2) with 0 by reflexivity.
  replace (Nat.land 8 4) with 0 by reflexivity.
  replace (Nat.land 8 8) with 8 by reflexivity.
  cbn [Nat.eqb].
  replace (Nat.land 8 1) with 0 by reflexivity.
  replace (Nat.land 8 2) with 0 by reflexivity.
  replace (Nat.land 8 4) with 0 by reflexivity.
  replace (Nat.land 8 8) with 8 by reflexivity.
  cbn [Nat.eqb].
  rewrite Nat.add_0_l, Nat.add_0_l, Nat.add_0_l.
  unfold e_mask32.
  rewrite Nat.land_ones.
  apply Nat.mod_small.
  eapply Nat.le_lt_trans.
  - apply Nat.land_le_l.
  - exact Ha.
Qed.

(** The fixture's BOOL.8 has [r4 = 255], so the conjunction is the low
    byte of its left operand. *)
Lemma e_bool_res_8_255 :
  forall a, a < 2 ^ 32 -> e_bool_res 8 a 255 = a mod 256.
Proof.
  intros a Ha.
  rewrite e_bool_res_8 by exact Ha.
  change 255 with (Nat.ones 8).
  rewrite Nat.land_ones.
  reflexivity.
Qed.

(** Bridge between the literal zero test on [N] and the Coq model zero
    test on [nat]. *)
Lemma eqb_of_nat_zero :
  forall v : nat, N.eqb (N.of_nat v) 0%N = Nat.eqb v 0.
Proof.
  intro v.
  destruct (Nat.eqb v 0) eqn:E.
  - apply Nat.eqb_eq in E. subst. reflexivity.
  - apply Nat.eqb_neq in E.
    destruct (N.eqb (N.of_nat v) 0%N) eqn:F.
    + apply N.eqb_eq in F. exfalso. apply E.
      apply f_equal with (f := N.to_nat) in F.
      rewrite Nat2N.id in F. cbn in F. exact F.
    + reflexivity.
Qed.

(** ** Extended literal executor

    The seven already-supported cases are copied verbatim from
    [lit_exec] in [MinskyNaN16LiteralDecode.v] so that
    [lit_exec_p_embed_core] is definitional. *)

Definition lit_exec_p (L : LState) (ins : InstrP) : LState :=
  match ins with
  | pMOVI d imm =>
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d imm;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pLD d a imm =>
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d
                    (payload_word (l_mem L (l_reg L a + imm)));
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pST d a imm =>
      {| l_pc := S (l_pc L);
         l_reg := l_reg L;
         l_mem := fun ad =>
           if Nat.eqb ad (l_reg L a + imm)
           then nan_mkword (l_reg L d) 10
           else l_mem L ad;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pCMP a b =>
      {| l_pc := S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb (l_reg L a) (l_reg L b))
                       (Nat.ltb (l_reg L a) (l_reg L b));
         l_halted := l_halted L |}
  | pJMP p target =>
      {| l_pc := if pred_passes (pred_nat p) (l_k L)
                 then target else S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pADD d a b =>
      let s := l_reg L a + l_reg L b in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d (s mod 2 ^ 32);
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb (s mod 2 ^ 32) 0)
                       (Nat.leb (2 ^ 32) s);
         l_halted := l_halted L |}
  | pSUB d a b =>
      let v := (l_reg L a - l_reg L b) mod 2 ^ 32 in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d v;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb v 0)
                       (Nat.ltb (l_reg L a) (l_reg L b));
         l_halted := l_halted L |}
  | pSHL d a imm =>
      let v := e_shl32 (l_reg L a) (imm mod 32) in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d v;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb v 0) false;
         l_halted := l_halted L |}
  | pSHR d a imm =>
      let v := e_shr32 (l_reg L a) (imm mod 32) in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d v;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb v 0) false;
         l_halted := l_halted L |}
  | pBOOL tbl d a b =>
      let res := e_bool_res tbl (l_reg L a) (l_reg L b) in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d res;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb res 0) false;
         l_halted := l_halted L |}
  | pPUTC d =>
      {| l_pc := S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pCALL target =>
      {| l_pc := target;
         l_reg := set_reg (l_reg L) 15 (S (l_pc L));
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pRET =>
      {| l_pc := l_reg L 15;
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pRETP p =>
      {| l_pc := if pred_passes (pred_nat p) (l_k L)
                 then l_reg L 15 else S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | pHALT =>
      {| l_pc := l_pc L;
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := true |}
  end.

Definition literal_step_p (image : nat -> N) (L : LState) : LState :=
  match decode_word_p (image (l_pc L)) with
  | Some ins => lit_exec_p L ins
  | None => L
  end.

(** Conservativity on the seven opcodes that [lit_exec] already
    implements.  The four remaining [Instr] constructors were the
    identity catch-all of [lit_exec]; [lit_exec_p] now executes them. *)

Definition core_instr (ins : Instr) : bool :=
  match ins with
  | iMOVI _ _ | iLD _ _ _ | iST _ _ _ | iCMP _ _ | iJMP _ _
  | iADD _ _ _ | iSUB _ _ _ => true
  | iSHL _ _ _ | iCALL _ | iRET | iHALT => false
  end.

Lemma lit_exec_p_embed_core :
  forall L ins,
    core_instr ins = true ->
    lit_exec_p L (embed_instr ins) = lit_exec L ins.
Proof.
  intros L ins H.
  destruct ins; try discriminate; reflexivity.
Qed.

Lemma lit_exec_p_embed_movi :
  forall L d imm,
    lit_exec_p L (embed_instr (iMOVI d imm)) = lit_exec L (iMOVI d imm).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_ld :
  forall L d a imm,
    lit_exec_p L (embed_instr (iLD d a imm)) = lit_exec L (iLD d a imm).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_st :
  forall L d a imm,
    lit_exec_p L (embed_instr (iST d a imm)) = lit_exec L (iST d a imm).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_cmp :
  forall L a b,
    lit_exec_p L (embed_instr (iCMP a b)) = lit_exec L (iCMP a b).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_jmp :
  forall L p target,
    lit_exec_p L (embed_instr (iJMP p target)) = lit_exec L (iJMP p target).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_add :
  forall L d a b,
    lit_exec_p L (embed_instr (iADD d a b)) = lit_exec L (iADD d a b).
Proof. reflexivity. Qed.

Lemma lit_exec_p_embed_sub :
  forall L d a b,
    lit_exec_p L (embed_instr (iSUB d a b)) = lit_exec L (iSUB d a b).
Proof. reflexivity. Qed.

(** ** Extended Coq model

    This is [exec_instr] of [MinskyNaN16VM.v] on the full [InstrP]
    stream.  The eleven [Instr] cases are copied verbatim; the four new
    cases are the ISA semantics.  PUTC has no output channel in the VM,
    so it only advances the PC (the output is proved on [LPState] in
    [MinskyNaN16LiteralPutc.v]). *)

Definition exec_instr_p (prog : list InstrP) (vm : VM) : VM :=
  match nth_error prog (vm_pc vm) with
  | None =>
      {| vm_pc := vm_pc vm; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
         vm_zf := vm_zf vm; vm_lf := vm_lf vm;
         vm_halted := true; vm_link := vm_link vm |}
  | Some ins =>
      let r := vm_reg vm in
      let m := vm_mem vm in
      match ins with
      | pCMP a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          {| vm_pc := instr_succ (vm_pc vm); vm_reg := r; vm_mem := m;
             vm_zf := Nat.eqb A B; vm_lf := Nat.ltb A B;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pJMP p target =>
          let pc' := if pred_holds p (vm_zf vm) (vm_lf vm)
                     then target else instr_succ (vm_pc vm) in
          {| vm_pc := pc'; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pSHL d a imm =>
          let A := get_reg r a in
          let v := Nat.shiftl A imm in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pSHR d a imm =>
          let A := get_reg r a in
          let v := Nat.shiftr A imm in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pADD d a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          let v := A + B in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pSUB d a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          let v := A - B in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := Nat.ltb A B;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pLD d a imm =>
          let A := get_reg r a in
          let v := m (A + imm) in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pST d a imm =>
          let A := get_reg r a in
          let v := get_reg r d in
          let m' := fun k => if Nat.eqb k (A + imm) then v else m k in
          {| vm_pc := instr_succ (vm_pc vm); vm_reg := r; vm_mem := m';
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pMOVI d imm =>
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d imm; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pBOOL tbl d a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          let v := e_bool_res tbl A B in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pPUTC d =>
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pCALL target =>
          {| vm_pc := target; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := instr_succ (vm_pc vm) |}
      | pRET =>
          {| vm_pc := vm_link vm; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pRETP p =>
          let pc' := if pred_holds p (vm_zf vm) (vm_lf vm)
                     then vm_link vm else instr_succ (vm_pc vm) in
          {| vm_pc := pc'; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | pHALT =>
          {| vm_pc := vm_pc vm; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := true; vm_link := vm_link vm |}
      end
  end.

(** On every program written in the original [Instr] subset the extended
    model is the existing Coq model, instruction for instruction. *)
Lemma exec_instr_p_embed :
  forall (prog : list Instr) vm,
    exec_instr_p (map embed_instr prog) vm = exec_instr prog vm.
Proof.
  intros prog vm.
  unfold exec_instr_p, exec_instr.
  rewrite nth_error_map.
  destruct (nth_error prog (vm_pc vm)) as [ins|] eqn:E.
  - destruct ins; cbn [embed_instr]; reflexivity.
  - reflexivity.
Qed.

(** ** Relation without the disputed [vm_reg 15] clause

    [R] ties both [vm_link] and [vm_reg 15] to the literal [r15]
    (D-16).  The Coq model's CALL writes only [vm_link], so the
    [vm_reg 15] clause cannot survive a call whose return address is
    not already in [r15].  [R_no15] is [R] with that one clause
    removed; it is what CALL preserves unconditionally. *)

Definition R_no15 (L : LState) (vm : VM) : Prop :=
  vm_pc vm = l_pc L /\
  (forall i, i < 15 -> vm_reg vm i = l_reg L i mod 2 ^ 32) /\
  vm_link vm = l_reg L 15 /\
  (forall a, vm_mem vm a = payload_word (l_mem L a)) /\
  vm_zf vm = Nat.eqb ((l_k L / 2) mod 2) 1 /\
  vm_lf vm = Nat.eqb (l_k L mod 2) 1 /\
  l_k L < 4 /\
  vm_halted vm = l_halted L /\
  (forall i, i < 16 -> l_reg L i < 2 ^ 32).

Lemma R_R_no15 : forall L vm, R L vm -> R_no15 L vm.
Proof.
  intros L vm HR.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold R_no15.
  split_conj.
  - exact Hpc.
  - exact Hregs.
  - exact Hlink.
  - exact Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - exact Hbound.
Qed.

(** Assumption audit *)

Print Assumptions lit_exec_p_embed_core.
Print Assumptions exec_instr_p_embed.
Print Assumptions e_shl32_eq.
Print Assumptions e_shr32_lt.
Print Assumptions e_bool_res_lt_two32.
Print Assumptions e_bool_res_8.
Print Assumptions e_bool_res_8_255.
Print Assumptions R_R_no15.
