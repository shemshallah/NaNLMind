(** * ISA-OBL-1: literal word 0 decode and first step

    This file discharges the first ISA-level obligation of
    [NAN0S_ISA_SPEC.md], section 6.3:

      [fixture_pc0_decode_and_step]

    Word 0 of the pinned assembled fixture is

      0xFFF801D00001F8FF = FFF8_01D00001_F8FF = MOVI r13,1

    We define a literal NaN16 word decoder for the MOVI case, a literal
    machine state and step for that case, and the proposed refinement
    relation [R] between the literal state and the Coq [VM] model of
    [MinskyNaN16VM.v].  We then prove that the decoded instruction is
    [iMOVI 13 1], that one literal step from the reset state reaches
    [pc = 1], [r13 = 1], [k = 0] with memory and all other registers
    unchanged, and that the literal successor is related by [R] to
    [exec_instr fixture_prog vm].

    Scope and honest limitations:

    - The decoder below handles the MOVI opcode (0x01) and rejects other
      opcodes.  Extending it to the full fixture stream is ISA-OBL-2.
    - The literal step below executes MOVI; other decoded instructions
      are out of scope here (they are unreachable because the decoder
      returns [None] for them).  Extending execution to the full fixture
      subset is ISA-OBL-3.
    - [fixture_prog] is the one-instruction head slice of the Coq fixture
      program.  ISA-OBL-1 only inspects word 0; the full 99-word decoder
      agreement is ISA-OBL-2.
    - The raw word is a binary natural [N], not a unary [nat].  This is
      the same 64-bit value; using [nat] would force Coq to normalize a
      2^48-scale unary numeral.  Register and payload values remain [nat]
      where the Coq model requires them.
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

(** The literal image used by the obligation.  Only word 0 is constrained;
    all other words are zero here.  A full image is ISA-OBL-2. *)
Definition image_word (idx : nat) : N :=
  match idx with
  | 0 => literal_word0
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
      n             = (class(near) << 2) | class(far). *)

Definition nan_hvalid (h : nat) : bool :=
  andb (Nat.eqb ((h / 16) mod 2048) 2047)
       (orb (Nat.eqb (h mod 16) 1) (Nat.eqb (h mod 16) 8)).

Definition nan_hcls (h : nat) : nat :=
  2 * ((h / 8) mod 2) + (h / (2 ^ 15)) mod 2.

Definition word_n (w : N) : nat :=
  nan_hcls (word_near w) * 4 + nan_hcls (word_far w).

(** Predicate bit test: pass iff [(n >> k) & 1 = 1]. *)
Definition pred_passes (n k : nat) : bool :=
  Nat.eqb ((n / 2 ^ k) mod 2) 1.

(** ** The minimal literal decoder

    This is the MOVI slice needed by ISA-OBL-1.  The head gate is part of
    the decoder: an invalid near or far head produces [None].  For a valid
    head pair, opcode 0x01 is decoded as [MOVI d,imm]; every other opcode
    is rejected. *)

Definition decode_word (w : N) : option Instr :=
  if andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)) then
    if Nat.eqb (word_op w) 1 then
      Some (iMOVI (word_d w) (word_imm w))
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

(** The MOVI action of the literal ISA.  Other instructions are outside
    ISA-OBL-1 and are not reachable through [decode_word] above. *)
Definition lit_exec (L : LState) (ins : Instr) : LState :=
  match ins with
  | iMOVI d imm =>
      {| l_pc := S (l_pc L);
         l_reg := set_reg (l_reg L) d imm;
         l_mem := l_mem L;
         l_k := l_k L;
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
    The address bound is omitted: the Coq memory is total. *)

Definition payload_word (w : N) : nat :=
  N.to_nat (word_payload w).

Definition R (L : LState) (vm : VM) : Prop :=
  vm_pc vm = l_pc L /\
  (forall i, i < 15 -> vm_reg vm i = l_reg L i mod 2 ^ 32) /\
  vm_reg vm 15 = l_reg L 15 mod 2 ^ 32 /\
  vm_link vm = l_reg L 15 /\
  (forall a, vm_mem vm a = payload_word (l_mem L a)) /\
  vm_zf vm = Nat.eqb ((l_k L / 2) mod 2) 1 /\
  vm_lf vm = Nat.eqb (l_k L mod 2) 1 /\
  vm_halted vm = l_halted L.

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
  - reflexivity.
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
      (Hpcvm & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hhalt).
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
         l_pc l_reg l_mem l_k l_halted instr_succ].
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
    + exact Hhalt.
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

(** ** Assumption audit *)

Print Assumptions fixture_pc0_decode_and_step.
Print Assumptions fixture_pc0_literal_step.
Print Assumptions fixture_pc0_reset_agrees.
