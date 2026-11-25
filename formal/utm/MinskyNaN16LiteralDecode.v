(** * ISA-OBL-1 and ISA-OBL-3a: literal decode and single-step execution

    This file discharges the first ISA-level obligation of
    [NAN0S_ISA_SPEC.md], section 6.3:

      [fixture_pc0_decode_and_step]

    and the first opcode-extension obligation, ISA-OBL-3a:

      [fixture_pc7_decode_and_step]   (LD r1,r0,100)

    LD is word 7 of the fixture and is the memory-read counterpart used
    by the control skeleton.  This revision additionally decodes and
    executes ST (0x09), CMP (0x07), JMP (0x0A) with the NE/EQ/GE/ALWAYS
    selectors, and ADD/SUB (0x03/0x04) under their no-overflow /
    no-borrow side conditions.  SHL, CALL, RET, HALT, BOOL, PUTC, SHR and
    predicated non-jump instructions remain outside this decoder and are
    listed precisely by [decode_word_op_coverage].

    Word 0 of the pinned assembled fixture is

      0xFFF801D00001F8FF = FFF8_01D00001_F8FF = MOVI r13,1

    We define a literal NaN16 word decoder for the MOVI/LD/ST/CMP/JMP/
    ADD/SUB slice, a literal machine state and step for those cases, and
    the proposed refinement relation [R] between the literal state and
    the Coq [VM] model of [MinskyNaN16VM.v].  We prove that the original
    pinned words decode to [iMOVI 13 1] and [iLD 1 0 100], that one
    literal step from the reset state reaches [pc = 1], [r13 = 1],
    [k = 0] with memory and all other registers unchanged, and that the
    literal successors are related by [R] to [exec_instr] on the
    corresponding fixture programs.  The new opcode obligations and the
    concrete ST/CMP/JMP/ADD/SUB fixture words are in
    [MinskyNaN16LiteralOps.v].

    Scope and honest limitations:

    - The decoder below handles MOVI (0x01), ADD (0x03), SUB (0x04),
      CMP (0x07), LD (0x08), ST (0x09), and JMP (0x0A) with the four
      predicate selectors that occur in the fixture (NE/EQ/GE/ALWAYS).
      SHL, CALL, RET, HALT and the display/string opcodes are still
      rejected; extending to the full fixture stream remains ISA-OBL-2.
    - The literal step below executes those seven opcodes.  ADD and SUB
      carry explicit no-carry / no-borrow hypotheses because of D-03 and
      D-04; JMP[EQ] and JMP[GE] carry the D-07 side condition [l_k <> 3].
      The remaining fixture opcodes are ISA-OBL-3.
    - [fixture_prog] is the one-instruction head slice of the Coq fixture
      program used by ISA-OBL-1.  The LD obligation uses the literal
      eight-word control prefix [fixture_prog_prefix8] and selects word 7.
      The full 99-word decoder agreement is ISA-OBL-2.
    - The raw word is a binary natural [N], not a unary [nat].  This is
      the same 64-bit value; using [nat] would force Coq to normalize a
      2^48-scale unary numeral.  Register and payload values remain [nat]
      where the Coq model requires them.
    - The generic one-step theorems for the added opcodes and the concrete
      fixture-word obligations are in [MinskyNaN16LiteralOps.v].
    - Memory coherence is stated for all addresses, not only for
      [a < NAN_WORDS].  The Coq model has a total [nat -> nat] memory, so
      the total version is the strongest form and avoids choosing the
      unresolved D-01/D-02 memory geometry. *)

From Coq Require Import List Arith Bool Lia NArith.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM.

Open Scope nat_scope.

(** ** The literal 64-bit word and its field layout *)

(** The pinned word as a binary natural.  Its hexadecimal form is exactly
    0xFFF801D00001F8FF.  [N] keeps the literal exact without unary [nat]
    expansion. *)
Definition literal_word0 : N := 0xFFF801D00001F8FF.

Lemma literal_word0_lt_2_64 : (literal_word0 < 2 ^ 64)%N.
Proof. vm_compute. reflexivity. Qed.

(** ISA-OBL-3a uses word 7 of the same assembled fixture,

      0xFFF808100064F8FF = FFF8_08100064_F8FF = LD r1,r0,100. *)
Definition literal_word7 : N := 0xFFF808100064F8FF.

Lemma literal_word7_lt_2_64 : (literal_word7 < 2 ^ 64)%N.
Proof. vm_compute. reflexivity. Qed.

(** The literal image used by the original ISA-OBL-1/ISA-OBL-3a
    obligations.  Words 0 and 7 are pinned; all other words are zero
    here.  The added opcode obligations in [MinskyNaN16LiteralOps.v] use
    the full pinned image [MinskyNaN16LiteralImage.literal_word_at]
    instead. *)
Definition image_word (idx : nat) : N :=
  match idx with
  | 0 => literal_word0
  | 7 => literal_word7
  | _ => 0
  end.

(** NaN16 word layout (NAN0S_ISA_SPEC.md section 2.1):

      byte 0..1   FAR head, big-endian 16-bit
      byte 2..5   payload, little-endian 32-bit
      byte 6..7   NEAR head, little-endian 16-bit

    In the raw little-endian word:

      w = near << 48 | payload << 16 | far_swapped
      far_swapped = (far >> 8) | ((far & 0xFF) << 8). *)

Definition word_near (w : N) : nat :=
  N.to_nat (N.shiftr w 48).

Definition word_far_raw (w : N) : N :=
  N.land w 0xFFFF.

Definition swap16 (x : N) : N :=
  N.shiftr x 8 + N.shiftl (N.land x 0xFF) 8.

Definition word_far (w : N) : nat :=
  N.to_nat (swap16 (word_far_raw w)).

Definition word_payload (w : N) : N :=
  N.land (N.shiftr w 16) 0xFFFFFFFF.

Definition word_op (w : N) : nat :=
  N.to_nat (N.shiftr (word_payload w) 24).

Definition word_d (w : N) : nat :=
  N.to_nat (N.land (N.shiftr (word_payload w) 20) 0xF).

Definition word_a (w : N) : nat :=
  N.to_nat (N.land (N.shiftr (word_payload w) 16) 0xF).

Definition word_imm (w : N) : nat :=
  N.to_nat (N.land (word_payload w) 0xFFFF).

(** Heads and classes, matching NAN0S_ISA_SPEC.md section 2.1:

      nan_hvalid(h) = ((h & 0x7FF0) == 0x7FF0)
                      /\ ((h & 15) == 1 \/ (h & 15) == 8)
      nan_hcls(h)   = ((h >> 2) & 2) | (h >> 15)
      n             = (class(near) << 2) | class(far).

    The executable definitions below use binary [N] masks and shifts.
    This is the same function as the arithmetic [h/16 mod 2048],
    [h/8 mod 2], [h/2^15 mod 2] spelling, but avoids Coq's linear
    [divmod] on 16-bit heads: that spelling made the full literal run
    uncomputable inside the kernel VM. *)

Definition nan_hvalid_N (x : N) : bool :=
  andb (N.eqb (N.land x 0x7FF0%N) 0x7FF0%N)
       (orb (N.eqb (N.land x 0xF%N) 1%N)
            (N.eqb (N.land x 0xF%N) 8%N)).

Definition nan_hcls_N (x : N) : nat :=
  2 * N.to_nat (N.land (N.shiftr x 3) 1%N) +
      N.to_nat (N.land (N.shiftr x 15) 1%N).

Definition nan_hvalid (h : nat) : bool :=
  nan_hvalid_N (N.of_nat h).

Definition nan_hcls (h : nat) : nat :=
  nan_hcls_N (N.of_nat h).

Definition word_n_N (w : N) : nat :=
  nan_hcls_N (N.shiftr w 48) * 4 +
  nan_hcls_N (swap16 (N.land w 0xFFFF)).

Definition word_n (w : N) : nat :=
  nan_hcls (word_near w) * 4 + nan_hcls (word_far w).

(** Predicate bit test: pass iff [(n >> k) & 1 = 1]. *)
Definition pred_passes (n k : nat) : bool :=
  Nat.eqb ((n / 2 ^ k) mod 2) 1.

(** Packed flags.  The oracle's [k] is [2*Z + L], with [L] in bit 0. *)
Definition pack_k (zf lf : bool) : nat :=
  (if zf then 2 else 0) + (if lf then 1 else 0).

Lemma pack_k_zf :
  forall zf lf, Nat.eqb ((pack_k zf lf / 2) mod 2) 1 = zf.
Proof. intros [] []; reflexivity. Qed.

Lemma pack_k_lf :
  forall zf lf, Nat.eqb (pack_k zf lf mod 2) 1 = lf.
Proof. intros [] []; reflexivity. Qed.

Lemma pack_k_lt_4 :
  forall zf lf, pack_k zf lf < 4.
Proof. intros zf lf. destruct zf, lf; cbn; lia. Qed.

(** Selector value [n] of a predicate, and the inverse decode used by the
    fixture's four selectors.  These are the values tabulated in
    NAN0S_ISA_SPEC.md section 3.4. *)
Definition pred_nat (p : preg) : nat :=
  match p with
  | pEQ => 4
  | pNE => 3
  | pLT => 2
  | pGE => 5
  | pGT => 1
  | pLE => 6
  | pALWAYS => 15
  | pNEVER => 0
  end.

Definition pred_of_selector (n : nat) : option preg :=
  match n with
  | 3 => Some pNE
  | 4 => Some pEQ
  | 5 => Some pGE
  | 15 => Some pALWAYS
  | _ => None
  end.

(** The Coq truth-table predicates and the oracle's bit test agree on
    every reachable packed-flag value except [k = 3].  [NE] and [ALWAYS]
    agree at [k = 3] too; [EQ] and [GE] are the cases that need the
    side condition (D-07). *)
Lemma pred_agrees :
  forall p k,
    k < 4 ->
    k <> 3 ->
    pred_holds p (Nat.eqb ((k / 2) mod 2) 1)
                (Nat.eqb (k mod 2) 1)
    = pred_passes (pred_nat p) k.
Proof.
  intros p k Hlt Hne.
  assert (Hk : k = 0 \/ k = 1 \/ k = 2) by lia.
  destruct Hk as [-> | [-> | ->]]; destruct p; reflexivity.
Qed.

Lemma pred_agrees_ne :
  forall k,
    k < 4 ->
    pred_holds pNE (Nat.eqb ((k / 2) mod 2) 1)
                (Nat.eqb (k mod 2) 1)
    = pred_passes 3 k.
Proof.
  intros k Hk.
  assert (Hk' : k = 0 \/ k = 1 \/ k = 2 \/ k = 3) by lia.
  destruct Hk' as [-> | [-> | [-> | ->]]]; reflexivity.
Qed.

Lemma pred_agrees_always :
  forall k,
    k < 4 ->
    pred_holds pALWAYS (Nat.eqb ((k / 2) mod 2) 1)
                       (Nat.eqb (k mod 2) 1)
    = pred_passes 15 k.
Proof.
  intros k Hk.
  assert (Hk' : k = 0 \/ k = 1 \/ k = 2 \/ k = 3) by lia.
  destruct Hk' as [-> | [-> | [-> | ->]]]; reflexivity.
Qed.

(** ** The literal decoder

    The head gate is part of the decoder: an invalid near or far head
    produces [None].  For a valid head pair the accepted opcodes are
    MOVI (0x01), ADD (0x03), SUB (0x04), CMP (0x07), LD (0x08), ST (0x09),
    and JMP (0x0A).  Register operands [b] are [imm & 15] as specified in
    NAN0S_ISA_SPEC.md section 4; JMP targets keep the full 16-bit [imm].
    The JMP selector is restricted to NE/EQ/GE/ALWAYS by
    [pred_of_selector]; every other opcode or selector is rejected. *)

Definition decode_word (w : N) : option Instr :=
  if andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)) then
    if Nat.eqb (word_op w) 1 then
      Some (iMOVI (word_d w) (word_imm w))
    else if Nat.eqb (word_op w) 3 then
      Some (iADD (word_d w) (word_a w) (word_imm w mod 16))
    else if Nat.eqb (word_op w) 4 then
      Some (iSUB (word_d w) (word_a w) (word_imm w mod 16))
    else if Nat.eqb (word_op w) 7 then
      Some (iCMP (word_a w) (word_imm w mod 16))
    else if Nat.eqb (word_op w) 8 then
      Some (iLD (word_d w) (word_a w) (word_imm w))
    else if Nat.eqb (word_op w) 9 then
      Some (iST (word_d w) (word_a w) (word_imm w))
    else if Nat.eqb (word_op w) 10 then
      match pred_of_selector (word_n w) with
      | Some p => Some (iJMP p (word_imm w))
      | None => None
      end
    else None
  else None.

(** ** Literal machine state and one literal step *)

Record LState := {
  l_pc : nat;
  l_reg : Reg;
  l_mem : nat -> N;
  l_k : nat;
  l_halted : bool;
}.

Definition lit_reset (mem : nat -> N) : LState :=
  {| l_pc := 0;
     l_reg := reg0;
     l_mem := mem;
     l_k := 0;
     l_halted := false |}.

(** The 32-bit payload projection used by the relation and by literal LD. *)
Definition payload_word (w : N) : nat :=
  N.to_nat (word_payload w).

(** The raw word constructor.  [nan_head i] is [NAN_HEADS[i]] of
    NAN0S_ISA_SPEC.md section 2.1, and [nan_mkword v n] places [v] in the
    32-bit payload, [n]'s low two bits in the far head, and [n]'s high two
    bits in the near head.  [ST] writes [nan_mkword (r[d]) 10]. *)
Definition nan_head (i : nat) : N :=
  match i with
  | 0 => 0x7FF1
  | 1 => 0xFFF1
  | 2 => 0x7FF8
  | _ => 0xFFF8
  end.

Definition nan_mkword (v : nat) (n : nat) : N :=
  (N.shiftl (nan_head ((n / 4) mod 4)) 48
   + N.shiftl (N.of_nat v) 16
   + swap16 (nan_head (n mod 4)))%N.

(** The literal actions of the ISA.  Instructions still outside this
    slice are not reachable through [decode_word] above; the catch-all
    keeps [lit_exec] total.  LD loads the payload of the literal word at
    [r[a] + imm]; ST writes a class-10 word at that address.  CMP and
    SUB use the oracle's unsigned compare, ADD uses carry-out as [L]. *)
Definition lit_exec (L : LState) (ins : Instr) : LState :=
  match ins with
  | iMOVI d imm =>
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d imm;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | iLD d a imm =>
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d
                    (payload_word (l_mem L (l_reg L a + imm)));
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | iST d a imm =>
      {| l_pc := S (l_pc L);
         l_reg := l_reg L;
         l_mem := fun ad =>
           if Nat.eqb ad (l_reg L a + imm)
           then nan_mkword (l_reg L d) 10
           else l_mem L ad;
         l_k := l_k L;
         l_halted := l_halted L |}
  | iCMP a b =>
      {| l_pc := S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb (l_reg L a) (l_reg L b))
                       (Nat.ltb (l_reg L a) (l_reg L b));
         l_halted := l_halted L |}
  | iJMP p target =>
      {| l_pc := if pred_passes (pred_nat p) (l_k L)
                 then target else S (l_pc L);
         l_reg := l_reg L;
         l_mem := l_mem L;
         l_k := l_k L;
         l_halted := l_halted L |}
  | iADD d a b =>
      let s := l_reg L a + l_reg L b in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d (s mod 2 ^ 32);
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb (s mod 2 ^ 32) 0)
                       (Nat.leb (2 ^ 32) s);
         l_halted := l_halted L |}
  | iSUB d a b =>
      let v := (l_reg L a - l_reg L b) mod 2 ^ 32 in
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d v;
         l_mem := l_mem L;
         l_k := pack_k (Nat.eqb v 0)
                       (Nat.ltb (l_reg L a) (l_reg L b));
         l_halted := l_halted L |}
  | _ => L
  end.

Definition literal_step (image : nat -> N) (L : LState) : LState :=
  match decode_word (image (l_pc L)) with
  | Some ins => lit_exec L ins
  | None => L
  end.

(** ** Proposed relation between literal state and the Coq VM

    This follows NAN0S_ISA_SPEC.md section 6.2 with the D-16 link
    reconciliation made explicit: both [vm_reg 15] and [vm_link] are tied
    to the literal [r15].  The memory clause projects each literal word to
    its 32-bit payload, because the Coq model's [LD]/[ST] see payloads.
    The address bound is omitted: the Coq memory is total.

    The final clause records that literal registers are 32-bit.  It is
    needed by literal LD: the load address is [r[a] + imm] in the literal
    machine, while the Coq model sees [vm_reg a + imm].  The relation only
    says [vm_reg a = r[a] mod 2^32]; the bound identifies the two.

    The [l_k < 4] clause records that [k] is a two-bit packed flag word.
    It is preserved by every literal action (CMP/ADD/SUB repack 0..3) and
    is needed to compare the exact bit-test predicate with the Coq truth
    table; see [pred_agrees] and D-07. *)

Definition R (L : LState) (vm : VM) : Prop :=
  vm_pc vm = l_pc L /\
  (forall i, i < 15 -> vm_reg vm i = l_reg L i mod 2 ^ 32) /\
  vm_reg vm 15 = l_reg L 15 mod 2 ^ 32 /\
  vm_link vm = l_reg L 15 /\
  (forall a, vm_mem vm a = payload_word (l_mem L a)) /\
  vm_zf vm = Nat.eqb ((l_k L / 2) mod 2) 1 /\
  vm_lf vm = Nat.eqb (l_k L mod 2) 1 /\
  l_k L < 4 /\
  vm_halted vm = l_halted L /\
  (forall i, i < 16 -> l_reg L i < 2 ^ 32).

(** Register equality follows at every architectural index, including
    [r15], because the relation also bounds the literal register. *)
Lemma R_reg_eq :
  forall L vm i, R L vm -> i < 16 -> vm_reg vm i = l_reg L i.
Proof.
  intros L vm i HR Hi.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  destruct (Nat.eq_dec i 15) as [-> | Hne].
  - rewrite Hreg15. apply Nat.mod_small. apply Hbound. lia.
  - assert (Hi15 : i < 15) by lia.
    rewrite (Hregs i Hi15). apply Nat.mod_small. apply Hbound. exact Hi.
Qed.

(** Coq-side reset state whose memory is the payload projection of the
    literal image. *)
Definition vm_reset (mem : nat -> N) : VM :=
  {| vm_pc := 0;
     vm_reg := reg0;
     vm_mem := fun a => payload_word (mem a);
     vm_zf := false;
     vm_lf := false;
     vm_halted := false;
     vm_link := 0 |}.

(** The Coq fixture program head.  ISA-OBL-1 only requires word 0; the
    full decoded control stream is ISA-OBL-2. *)
Definition fixture_prog : list Instr :=
  [ iMOVI 13 1 ].

(** Split only conjunctions.  Plain [repeat split] also tries [constructor]
    on equality goals, which can force normalization of [2 ^ 32]. *)
Ltac split_conj := repeat match goal with |- _ /\ _ => split end.

(** ** Helper lemmas for the 32-bit register modulus

    These avoid asking [cbn]/[vm_compute] to normalize the unary numeral
    [2 ^ 32]. *)

Lemma two32_neq_0 : 2 ^ 32 <> 0.
Proof. apply Nat.pow_nonzero. lia. Qed.

Lemma one_lt_two32 : 1 < 2 ^ 32.
Proof. apply Nat.pow_gt_1; lia. Qed.

Lemma one_mod_two32 : 1 mod 2 ^ 32 = 1.
Proof. apply Nat.mod_small. exact one_lt_two32. Qed.

Lemma zero_mod_two32 : 0 mod 2 ^ 32 = 0.
Proof.
  apply Nat.mod_small.
  apply Nat.neq_0_lt_0. exact two32_neq_0.
Qed.

(** ** Helper lemmas for the 32-bit payload bound

    [payload_word] is always a 32-bit value, so storing it in a literal
    register preserves the 32-bit register invariant, and reducing it
    modulo [2 ^ 32] is the identity. *)

Lemma N_lt_to_nat_lt :
  forall a b : N, (a < b)%N -> N.to_nat a < N.to_nat b.
Proof.
  intros a b H. unfold N.lt in H.
  rewrite N2Nat.inj_compare in H.
  apply PeanoNat.Nat.compare_lt_iff. exact H.
Qed.

Lemma word_payload_lt_two32 :
  forall w, (word_payload w < 2 ^ 32)%N.
Proof.
  intro w. unfold word_payload.
  eapply N.le_lt_trans.
  - apply N.land_le_r.
  - vm_compute. reflexivity.
Qed.

Lemma payload_word_lt_two32 :
  forall w, payload_word w < 2 ^ 32.
Proof.
  intro w. unfold payload_word.
  pose proof
    (N_lt_to_nat_lt (word_payload w) (2 ^ 32)%N
       (word_payload_lt_two32 w)) as H.
  rewrite N2Nat.inj_pow in H.
  cbn in H.
  exact H.
Qed.

Lemma payload_word_mod_two32 :
  forall w, payload_word w mod 2 ^ 32 = payload_word w.
Proof.
  intro w. apply Nat.mod_small. apply payload_word_lt_two32.
Qed.

(** ** Payload projection of the raw [ST] word

    [nan_mkword] places the 32-bit value in bits 16..47, so the payload
    projection is the value modulo [2 ^ 32].  The proof is arithmetic on
    [N] fields; no head validity is needed for the payload clause of [R]. *)

Lemma ones32 : (0xFFFFFFFF = N.ones 32)%N.
Proof. vm_compute. reflexivity. Qed.

Lemma N_to_nat_two32 : N.to_nat (2 ^ 32)%N = Nat.pow 2 32.
Proof.
  rewrite N2Nat.inj_pow.
  change (Nat.pow 2 32 = Nat.pow 2 32).
  reflexivity.
Qed.

Lemma N_of_nat_lt_two32 :
  forall v, v < 2 ^ 32 -> (N.of_nat v < 2 ^ 32)%N.
Proof.
  intros v Hv.
  unfold N.lt.
  rewrite N2Nat.inj_compare.
  rewrite Nat2N.id.
  rewrite N_to_nat_two32.
  apply PeanoNat.Nat.compare_lt_iff.
  exact Hv.
Qed.

Lemma N_of_nat_mod_small :
  forall v, v < 2 ^ 32 -> (N.of_nat v mod 2 ^ 32 = N.of_nat v)%N.
Proof.
  intros v Hv. apply N.mod_small. apply N_of_nat_lt_two32. exact Hv.
Qed.

Lemma nan_head_swap16_lt :
  forall i : nat, (swap16 (nan_head (i mod 4)) < 2 ^ 16)%N.
Proof.
  intro i.
  assert (H : (i mod 4 < 4)%nat)
    by (apply Nat.mod_upper_bound; lia).
  destruct (i mod 4) as [|[|[|[|k]]]]; try lia; vm_compute; reflexivity.
Qed.

Lemma nan_mkword_payload_mod :
  forall v n, word_payload (nan_mkword v n) = (N.of_nat v mod 2 ^ 32)%N.
Proof.
  intros v n.
  unfold word_payload, nan_mkword.
  rewrite ones32.
  rewrite N.land_ones.
  rewrite N.shiftr_div_pow2.
  set (near := nan_head ((n / 4) mod 4)).
  set (far := swap16 (nan_head (n mod 4))).
  assert (Hshape :
    (N.shiftl near 48 + N.shiftl (N.of_nat v) 16 + far)%N
    = ((near * 2 ^ 32 + N.of_nat v) * 2 ^ 16 + far)%N).
  { rewrite !N.shiftl_mul_pow2. nia. }
  rewrite Hshape.
  rewrite N.div_add_l by (vm_compute; discriminate).
  assert (Hfar : (far / 2 ^ 16 = 0)%N).
  { apply N.div_small. unfold far. apply nan_head_swap16_lt. }
  rewrite Hfar. rewrite N.add_0_r.
  rewrite N.add_comm.
  rewrite N.Div0.mod_add.
  reflexivity.
Qed.

Lemma payload_word_nan_mkword :
  forall v, v < 2 ^ 32 -> payload_word (nan_mkword v 10) = v.
Proof.
  intros v Hv.
  unfold payload_word.
  rewrite nan_mkword_payload_mod.
  rewrite N_of_nat_mod_small by exact Hv.
  rewrite Nat2N.id.
  reflexivity.
Qed.

(** Field bounds used to identify literal and Coq register operands. *)

Lemma word_d_lt_16 : forall w, word_d w < 16.
Proof.
  intro w. unfold word_d.
  change (N.to_nat (N.land (N.shiftr (word_payload w) 20) 0xF)
          < N.to_nat 16).
  apply N_lt_to_nat_lt.
  eapply N.le_lt_trans.
  - apply N.land_le_r.
  - vm_compute. reflexivity.
Qed.

Lemma word_a_lt_16 : forall w, word_a w < 16.
Proof.
  intro w. unfold word_a.
  change (N.to_nat (N.land (N.shiftr (word_payload w) 16) 0xF)
          < N.to_nat 16).
  apply N_lt_to_nat_lt.
  eapply N.le_lt_trans.
  - apply N.land_le_r.
  - vm_compute. reflexivity.
Qed.

Lemma word_imm_mod_16_lt : forall w, word_imm w mod 16 < 16.
Proof. intro w. apply Nat.mod_upper_bound. lia. Qed.

(** ** Helper lemmas for the register update *)

Lemma reg0_any : forall i, reg0 i = 0.
Proof. reflexivity. Qed.

Lemma set_reg_eq :
  forall (r : Reg) d v, set_reg r d v d = v.
Proof.
  intros r d v. unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma set_reg_neq :
  forall (r : Reg) d v i, i <> d -> set_reg r d v i = r i.
Proof.
  intros r d v i H.
  unfold set_reg.
  destruct (Nat.eqb i d) eqn:E.
  - apply Nat.eqb_eq in E. contradiction.
  - reflexivity.
Qed.

(** ** Literal decoding facts *)

(** [0xFFF8] is [2 ^ 16 - 8]; writing it this way avoids Coq's
    abstract-large-number warning for a 16-bit [nat] literal. *)
Lemma literal_word0_near : word_near literal_word0 = 2 ^ 16 - 8.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_far_raw : word_far_raw literal_word0 = (0xF8FF)%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_far : word_far literal_word0 = 2 ^ 16 - 8.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_payload : word_payload literal_word0 = (0x01D00001)%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_op : word_op literal_word0 = 1.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_d : word_d literal_word0 = 13.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_a : word_a literal_word0 = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_imm : word_imm literal_word0 = 1.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_n : word_n literal_word0 = 15.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_near_valid : nan_hvalid (word_near literal_word0) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_far_valid : nan_hvalid (word_far literal_word0) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_pred_passes :
  forall k, k < 4 -> pred_passes (word_n literal_word0) k = true.
Proof.
  intros k Hk. rewrite literal_word0_n.
  destruct k as [|[|[|[|k]]]]; try reflexivity; lia.
Qed.

Lemma decode_word_literal_word0 :
  decode_word literal_word0 = Some (iMOVI 13 1).
Proof. vm_compute. reflexivity. Qed.

(** ** Literal decoding facts for word 7 (LD) *)

Lemma literal_word7_near : word_near literal_word7 = 2 ^ 16 - 8.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_far : word_far literal_word7 = 2 ^ 16 - 8.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_payload : word_payload literal_word7 = (0x08100064)%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_op : word_op literal_word7 = 8.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_d : word_d literal_word7 = 1.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_a : word_a literal_word7 = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_imm : word_imm literal_word7 = 100.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_n : word_n literal_word7 = 15.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_near_valid : nan_hvalid (word_near literal_word7) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word7_far_valid : nan_hvalid (word_far literal_word7) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_word_literal_word7 :
  decode_word literal_word7 = Some (iLD 1 0 100).
Proof. vm_compute. reflexivity. Qed.

(** The decoder accepts exactly opcodes 0x01 (MOVI), 0x03 (ADD),
    0x04 (SUB), 0x07 (CMP), 0x08 (LD), 0x09 (ST), and 0x0A (JMP).  This
    is the precise positive coverage statement for the extended slice. *)
Lemma decode_word_op_coverage :
  forall w ins,
    decode_word w = Some ins ->
    word_op w = 1 \/ word_op w = 3 \/ word_op w = 4 \/
    word_op w = 7 \/ word_op w = 8 \/ word_op w = 9 \/
    word_op w = 10.
Proof.
  intros w ins H.
  unfold decode_word in H.
  destruct (andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)))
    eqn:Ehead; [|discriminate].
  destruct (Nat.eqb (word_op w) 1) eqn:E1.
  { left. apply Nat.eqb_eq. exact E1. }
  destruct (Nat.eqb (word_op w) 3) eqn:E3.
  { right; left. apply Nat.eqb_eq. exact E3. }
  destruct (Nat.eqb (word_op w) 4) eqn:E4.
  { right; right; left. apply Nat.eqb_eq. exact E4. }
  destruct (Nat.eqb (word_op w) 7) eqn:E7.
  { right; right; right; left. apply Nat.eqb_eq. exact E7. }
  destruct (Nat.eqb (word_op w) 8) eqn:E8.
  { right; right; right; right; left. apply Nat.eqb_eq. exact E8. }
  destruct (Nat.eqb (word_op w) 9) eqn:E9.
  { right; right; right; right; right; left.
    apply Nat.eqb_eq. exact E9. }
  destruct (Nat.eqb (word_op w) 10) eqn:E10.
  { right; right; right; right; right; right.
    apply Nat.eqb_eq. exact E10. }
  destruct (pred_of_selector (word_n w)); discriminate.
Qed.

(** The JMP selector is restricted to the four fixture predicates. *)
Lemma pred_of_selector_range :
  forall n p, pred_of_selector n = Some p ->
  p = pNE \/ p = pEQ \/ p = pGE \/ p = pALWAYS.
Proof.
  intros n p H.
  unfold pred_of_selector in H.
  destruct n as [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]]];
    try discriminate H; inversion H; subst; auto.
Qed.

Lemma decode_word_jmp_pred_coverage :
  forall w p target,
    decode_word w = Some (iJMP p target) ->
    p = pNE \/ p = pEQ \/ p = pGE \/ p = pALWAYS.
Proof.
  intros w p target H.
  unfold decode_word in H.
  destruct (andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)))
    eqn:Ehead; [|discriminate].
  destruct (Nat.eqb (word_op w) 1); [discriminate|].
  destruct (Nat.eqb (word_op w) 3); [discriminate|].
  destruct (Nat.eqb (word_op w) 4); [discriminate|].
  destruct (Nat.eqb (word_op w) 7); [discriminate|].
  destruct (Nat.eqb (word_op w) 8); [discriminate|].
  destruct (Nat.eqb (word_op w) 9); [discriminate|].
  destruct (Nat.eqb (word_op w) 10) eqn:E10; [|discriminate].
  destruct (pred_of_selector (word_n w)) as [q|] eqn:Eq; [|discriminate].
  inversion H; subst.
  apply (pred_of_selector_range (word_n w) p). exact Eq.
Qed.

(** ** The literal first step *)

Lemma fixture_prog_head :
  nth_error fixture_prog 0 = Some (iMOVI 13 1).
Proof. reflexivity. Qed.

Theorem fixture_pc0_literal_step :
  l_pc (literal_step image_word (lit_reset image_word)) = 1 /\
  l_reg (literal_step image_word (lit_reset image_word)) 13 = 1 /\
  l_k (literal_step image_word (lit_reset image_word)) = 0 /\
  l_halted (literal_step image_word (lit_reset image_word)) = false /\
  (forall a,
     l_mem (literal_step image_word (lit_reset image_word)) a =
     image_word a) /\
  (forall i, i <> 13 ->
     l_reg (literal_step image_word (lit_reset image_word)) i = 0).
Proof.
  unfold literal_step.
  cbn [image_word lit_reset l_pc].
  rewrite decode_word_literal_word0.
  cbn.
  split_conj; try reflexivity.
  intros i Hne. rewrite set_reg_neq by exact Hne. reflexivity.
Qed.

(** ** Relation holds at the reset state *)

Lemma R_lit_reset :
  forall mem, R (lit_reset mem) (vm_reset mem).
Proof.
  intro mem.
  unfold R, lit_reset, vm_reset.
  cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
       l_pc l_reg l_mem l_k l_halted reg0].
  split_conj.
  - reflexivity.
  - intros i Hi. rewrite !reg0_any. rewrite zero_mod_two32. reflexivity.
  - rewrite !reg0_any. rewrite zero_mod_two32. reflexivity.
  - reflexivity.
  - intro a. reflexivity.
  - reflexivity.
  - reflexivity.
  - lia.
  - reflexivity.
  - intros i Hi. rewrite reg0_any. apply Nat.neq_0_lt_0. exact two32_neq_0.
Qed.

(** ** ISA-OBL-1 *)

Theorem fixture_pc0_decode_and_step :
  decode_word (image_word 0) = Some (iMOVI 13 1) /\
  forall L vm,
    R L vm ->
    l_pc L = 0 ->
    R (literal_step image_word L) (exec_instr fixture_prog vm).
Proof.
  split.
  - cbn [image_word]. apply decode_word_literal_word0.
  - intros L vm HR Hpc.
    destruct HR as
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
    unfold literal_step.
    rewrite Hpc.
    cbn [image_word].
    rewrite decode_word_literal_word0.
    cbn [lit_exec].
    unfold exec_instr.
    rewrite Hpcvm, Hpc.
    rewrite fixture_prog_head.
    cbn.
    unfold R.
    cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
         l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
    split_conj.
    + reflexivity.
    + intros i Hi.
      destruct (Nat.eq_dec i 13) as [-> | Hne].
      * rewrite !set_reg_eq.
        rewrite one_mod_two32. reflexivity.
      * rewrite !set_reg_neq by exact Hne.
        apply Hregs. exact Hi.
    + rewrite !set_reg_neq by lia.
      exact Hreg15.
    + rewrite set_reg_neq by lia.
      exact Hlink.
    + intro a. exact (Hmem a).
    + exact Hzf.
    + exact Hlf.
    + exact Hk.
    + exact Hhalt.
    + intros i Hi.
      destruct (Nat.eq_dec i 13) as [-> | Hne].
      * rewrite set_reg_eq. exact one_lt_two32.
      * rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** The concrete reset instance, i.e. the Coq successor of the literal
    reset state is the successor produced by [exec_instr] on the fixture
    program head. *)
Theorem fixture_pc0_reset_agrees :
  R (literal_step image_word (lit_reset image_word))
    (exec_instr fixture_prog (vm_reset image_word)).
Proof.
  destruct fixture_pc0_decode_and_step as [_ Hstep].
  apply (Hstep (lit_reset image_word) (vm_reset image_word)).
  - apply R_lit_reset.
  - reflexivity.
Qed.

(** ** ISA-OBL-3a: literal LD decode and single-step execution

    Word 7 of the fixture is [FFF8_08100064_F8FF] = [LD r1,r0,100].
    The Coq program below is the literal eight-word control prefix
    (the first seven instructions are not executed by this obligation;
    [nth_error] selects index 7). *)

Definition fixture_prog_prefix8 : list Instr :=
  [ iMOVI 13 1;      (* 0 *)
    iMOVI 1 5;       (* 1 *)
    iST 1 0 100;     (* 2 *)
    iMOVI 1 166;     (* 3 *)
    iST 1 0 101;     (* 4 *)
    iST 0 0 102;     (* 5 *)
    iCALL 29;        (* 6 *)
    iLD 1 0 100 ].   (* 7 *)

Lemma fixture_prog_prefix8_ld :
  nth_error fixture_prog_prefix8 7 = Some (iLD 1 0 100).
Proof. reflexivity. Qed.

(** Literal LD loads the 32-bit payload at [r[a] + imm].  The proof uses
    the 32-bit register-bound clause of [R] to identify the literal
    address [r[0] + 100] with the Coq address [vm_reg vm 0 + 100]. *)
Theorem fixture_pc7_decode_and_step :
  decode_word (image_word 7) = Some (iLD 1 0 100) /\
  forall L vm,
    R L vm ->
    l_pc L = 7 ->
    R (literal_step image_word L)
      (exec_instr fixture_prog_prefix8 vm).
Proof.
  split.
  - cbn [image_word]. apply decode_word_literal_word7.
  - intros L vm HR Hpc.
    destruct HR as
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
    assert (Hr0 : vm_reg vm 0 = l_reg L 0).
    { rewrite (Hregs 0 ltac:(lia)).
      apply Nat.mod_small. apply Hbound. lia. }
    unfold literal_step.
    rewrite Hpc.
    cbn [image_word].
    rewrite decode_word_literal_word7.
    cbn [lit_exec].
    unfold exec_instr.
    rewrite Hpcvm, Hpc.
    rewrite fixture_prog_prefix8_ld.
    cbn.
    unfold R.
    cbn [vm_pc vm_reg vm_mem vm_zf vm_lf vm_halted vm_link
         l_pc l_reg l_mem l_k l_halted instr_succ get_reg].
    split_conj.
    + reflexivity.
    + intros i Hi.
      destruct (Nat.eq_dec i 1) as [-> | Hne].
      * rewrite !set_reg_eq.
        unfold get_reg.
        rewrite Hr0, Hmem.
        rewrite payload_word_mod_two32.
        reflexivity.
      * rewrite !set_reg_neq by exact Hne.
        apply Hregs. exact Hi.
    + rewrite !set_reg_neq by lia.
      exact Hreg15.
    + rewrite set_reg_neq by lia.
      exact Hlink.
    + intro a. exact (Hmem a).
    + exact Hzf.
    + exact Hlf.
    + exact Hk.
    + exact Hhalt.
    + intros i Hi.
      destruct (Nat.eq_dec i 1) as [-> | Hne].
      * rewrite set_reg_eq. apply payload_word_lt_two32.
      * rewrite set_reg_neq by exact Hne. apply Hbound. exact Hi.
Qed.

(** ** Assumption audit *)

Print Assumptions fixture_pc0_decode_and_step.
Print Assumptions fixture_pc0_literal_step.
Print Assumptions fixture_pc0_reset_agrees.
Print Assumptions decode_word_op_coverage.
Print Assumptions fixture_pc7_decode_and_step.
