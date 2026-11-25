(** * ISA-OBL-3c: the full code region, including the [puts] block

    [MinskyNaN16LiteralImage.v] decodes the code slices [0,84) and
    [96,99) to the [Instr] subset of [MinskyNaN16VM.v].  It explicitly
    leaves the [puts] block [84,96) outside, because that block uses
    BOOL.8, PUTC, SHR, and a predicated RET, none of which occur in
    [Instr].

    This file extends the literal decoder with a new instruction type
    [InstrP] that contains every opcode of the fixture:

      MOVI, LD, ST, CMP, JMP[p], CALL, RET, ADD, SUB, SHL, SHR, BOOL,
      PUTC, predicated RET, HALT

    and proves that the contiguous literal code region [0,99) decodes,
    word for word, to the explicit Coq fixture program
    [fixture_prog_full].  That program is the [InstrP] image of the
    already-pinned [slice_main], [slice_run100], [slice_step_prelude],
    [slice_scan], [slice_action], [slice_step_ret], [slice_next],
    [slice_no_trans] and [slice_fail] slices, plus the new [slice_puts].

    What is proved here:

    - [decode_range_p 0 84] decodes the already-supported prefix;
    - [decode_range_p 84 96] decodes [slice_puts] exactly;
    - [decode_range_p 96 99] decodes [slice_fail] exactly;
    - [literal_full_code_decodes] combines them at [0,99);
    - [literal_full_code_pointwise] exposes the same fact as
      [decode_word_p (literal_word_at i) = Some (nth i fixture_prog_full _)]
      for every [i < 99], which is the form used by the run theorem.

    There is no [Admitted], [Axiom], or [Parameter] in this file. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage LiteralImageData.

Open Scope nat_scope.

(** ** Extended instruction set *)

(** The fixture's full opcode list is the [Instr] list of
    [MinskyNaN16VM.v] plus four forms that the VM model omitted:

      [pSHR d a imm]     logical right shift by [imm & 31]
      [pBOOL tbl d a b]   truth-table BOOL, [tbl] is the 4-bit [n] field
      [pPUTC d]          emit the low byte of [r[d]]
      [pRETP p]          predicated return

    The [tbl] field is recorded, not forced to 8, so the decoder is
    faithful to the encoding rather than to the one fixture instance.
    The fixture instance is [tbl = 8] (the truth table [A & B]). *)

Inductive InstrP :=
| pCMP (a b : nat)
| pJMP (p : preg) (target : nat)
| pSHL (d a imm : nat)
| pSHR (d a imm : nat)
| pADD (d a b : nat)
| pSUB (d a b : nat)
| pLD (d a imm : nat)
| pST (d a imm : nat)
| pMOVI (d imm : nat)
| pBOOL (tbl : nat) (d a b : nat)
| pPUTC (d : nat)
| pCALL (target : nat)
| pRET
| pRETP (p : preg)
| pHALT.

(** Embedding of the already-proved [Instr] subset.  This lets the
    existing, already-decoded slices be reused without re-listing their
    84 words by hand. *)

Definition embed_instr (i : Instr) : InstrP :=
  match i with
  | iCMP a b => pCMP a b
  | iJMP p target => pJMP p target
  | iSHL d a imm => pSHL d a imm
  | iADD d a b => pADD d a b
  | iSUB d a b => pSUB d a b
  | iLD d a imm => pLD d a imm
  | iST d a imm => pST d a imm
  | iMOVI d imm => pMOVI d imm
  | iCALL target => pCALL target
  | iRET => pRET
  | iHALT => pHALT
  end.


(** ** Full predicate-selector table

    [pred_nat] and [pred_of_n] in [MinskyNaN16LiteralDecode.v] are the
    restricted inverse used by the four selectors of the supported
    slices.  The NaN16 encoding has eight selectors, tabulated in
    NAN0S_ISA_SPEC.md section 3.4; the full inverse below covers all of
    them.  The puts block only needs [n = 4] (EQ) and [n = 15]
    (unconditional RET). *)

Definition pred_of_n_full (n : nat) : option preg :=
  match n with
  | 0 => Some pNEVER
  | 1 => Some pGT
  | 2 => Some pLT
  | 3 => Some pNE
  | 4 => Some pEQ
  | 5 => Some pGE
  | 6 => Some pLE
  | 15 => Some pALWAYS
  | _ => None
  end.

Lemma pred_of_n_full_pred_nat :
  forall p, pred_of_n_full (pred_nat p) = Some p.
Proof. destruct p; reflexivity. Qed.

(** ** Full fixture decoder *)

Definition decode_word_p (w : N) : option InstrP :=
  if andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)) then
    let op := word_op w in
    let d := word_d w in
    let a := word_a w in
    let imm := word_imm w in
    if Nat.eqb op 0 then
      Some (pBOOL (word_n w) d a (imm mod 16))
    else if Nat.eqb op 1 then Some (pMOVI d imm)
    else if Nat.eqb op 3 then Some (pADD d a (imm mod 16))
    else if Nat.eqb op 4 then Some (pSUB d a (imm mod 16))
    else if Nat.eqb op 5 then Some (pSHL d a imm)
    else if Nat.eqb op 6 then Some (pSHR d a imm)
    else if Nat.eqb op 7 then Some (pCMP a (imm mod 16))
    else if Nat.eqb op 8 then Some (pLD d a imm)
    else if Nat.eqb op 9 then Some (pST d a imm)
    else if Nat.eqb op 10 then
      match pred_of_n_full (word_n w) with
      | Some p => Some (pJMP p imm)
      | None => None
      end
    else if Nat.eqb op 11 then Some (pCALL imm)
    else if Nat.eqb op 12 then
      if Nat.eqb (word_n w) 15 then Some pRET
      else match pred_of_n_full (word_n w) with
           | Some p => Some (pRETP p)
           | None => None
           end
    else if Nat.eqb op 21 then Some (pPUTC d)
    else if Nat.eqb op 255 then
      if Nat.eqb (word_n w) 15 then Some pHALT else None
    else None
  else None.

(** A direct index recursion, so the pointwise fetch lemma below is
    structural and never needs to normalize a [nth] over the whole
    literal image. *)
Fixpoint decode_range_from (i n : nat) : option (list InstrP) :=
  match n with
  | 0 => Some []
  | S k =>
      match decode_word_p (literal_word_at i),
            decode_range_from (S i) k with
      | Some ins, Some rest => Some (ins :: rest)
      | _, _ => None
      end
  end.

Definition decode_range_p (lo hi : nat) : option (list InstrP) :=
  decode_range_from lo (hi - lo).

(** ** The puts slice and the full fixture program

    Word layout of [84,96), from the literal image and the .nas source:

      84  FFF8_014000FF_F8FF  MOVI r4,255
      85  FFF8_08210000_F8FF  LD r2,r1,0
      86  FFF8_01300004_F8FF  MOVI r3,4
      87  7FF8_00520004_F17F  BOOL.8 r5,r2,r4
      88  FFF8_07050000_F8FF  CMP r5,r0
      89  FFF1_0C000000_F17F  RET[EQ]
      90  FFF8_15500000_F8FF  PUTC r5
      91  FFF8_06220008_F8FF  SHR r2,r2,8
      92  FFF8_0433000D_F8FF  SUB r3,r3,r13
      93  7FF1_0A000057_F8FF  JMP[NE] 87
      94  FFF8_0311000D_F8FF  ADD r1,r1,r13
      95  FFF8_0A000055_F8FF  JMP 85 *)

Definition slice_puts : list InstrP := [
  pMOVI 4 255;
  pLD 2 1 0;
  pMOVI 3 4;
  pBOOL 8 5 2 4;
  pCMP 5 0;
  pRETP pEQ;
  pPUTC 5;
  pSHR 2 2 8;
  pSUB 3 3 13;
  pJMP pNE 87;
  pADD 1 1 13;
  pJMP pALWAYS 85
].

Definition slice_prefix84_p : list InstrP :=
  map embed_instr
    (slice_main ++ slice_run100 ++ slice_step_prelude ++ slice_scan ++
     slice_action ++ slice_step_ret ++ slice_next ++ slice_no_trans).

Definition slice_fail_p : list InstrP := map embed_instr slice_fail.

Definition fixture_prog_full : list InstrP :=
  slice_prefix84_p ++ slice_puts ++ slice_fail_p.

(** ** Decode theorems *)

Lemma decode_full_prefix84 :
  decode_range_p 0 84 = Some slice_prefix84_p.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_full_puts :
  decode_range_p 84 96 = Some slice_puts.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_full_fail :
  decode_range_p 96 99 = Some slice_fail_p.
Proof. vm_compute. reflexivity. Qed.

(** The contiguous literal code region [0,99) is exactly the fixture
    program: 29 + 7 + 11 + 20 + 11 + 1 + 2 + 3 + 12 + 3 = 99 words. *)

Theorem literal_full_code_decodes :
  List.length literal_image = 4366 /\
  decode_range_p 0 99 = Some fixture_prog_full /\
  List.length fixture_prog_full = 99.
Proof.
  split; [apply literal_image_4366|split].
  - vm_compute. reflexivity.
  - vm_compute. reflexivity.
Qed.

(** The individual code blocks remain visible.  The finer subdivision
    [0,29), [29,36), ... is the already-proved [Instr] decomposition of
    [MinskyNaN16LiteralImage.v]; here the image-level facts needed for
    the full program are the three contiguous blocks. *)

Theorem literal_code_slices_decode :
  decode_range_p 0 84 = Some slice_prefix84_p /\
  decode_range_p 84 96 = Some slice_puts /\
  decode_range_p 96 99 = Some slice_fail_p.
Proof.
  split; [apply decode_full_prefix84|].
  split; [apply decode_full_puts|apply decode_full_fail].
Qed.

(** ** Pointwise form used by the executor

    The run file fetches by PC.  Instead of evaluating a 99-way boolean
    check, these lemmas derive fetch agreement structurally from
    [decode_range_from]. *)

Definition instrp_default : InstrP := pHALT.

Lemma decode_range_from_succ :
  forall i n,
    decode_range_from i (S n) =
    match decode_word_p (literal_word_at i),
          decode_range_from (S i) n with
    | Some ins, Some rest => Some (ins :: rest)
    | _, _ => None
    end.
Proof. reflexivity. Qed.

Lemma decode_range_from_nth :
  forall (n i : nat) (out : list InstrP) j,
    j < n ->
    decode_range_from i n = Some out ->
    exists x,
      decode_word_p (literal_word_at (i + j)) = Some x /\
      nth_error out j = Some x.
Proof.
  induction n as [|n IH]; intros i out j Hj Hdec.
  - lia.
  - rewrite decode_range_from_succ in Hdec.
    destruct (decode_word_p (literal_word_at i)) as [x|] eqn:E; [|discriminate].
    destruct (decode_range_from (S i) n) as [out'|] eqn:E'; [|discriminate].
    injection Hdec as Hdec. subst out.
    destruct j as [|j].
    + exists x. split; [|reflexivity].
      replace (i + 0) with i by lia. exact E.
    + destruct (IH (S i) out' j ltac:(lia) E') as [y [Hy Hnth]].
      exists y. split.
      * replace (i + S j) with (S i + j) by lia. exact Hy.
      * change (nth_error out' j = Some y). exact Hnth.
Qed.

Lemma decode_range_p_nth :
  forall lo hi out i,
    decode_range_p lo hi = Some out ->
    lo <= i -> i < hi ->
    exists x, decode_word_p (literal_word_at i) = Some x /\
              nth_error out (i - lo) = Some x.
Proof.
  intros lo hi out i Hdec Hlo Hhi.
  unfold decode_range_p in Hdec.
  assert (Hj : i - lo < hi - lo) by lia.
  destruct (decode_range_from_nth (hi - lo) lo out (i - lo) Hj Hdec)
    as [x [Hx Hnth]].
  exists x. split; [|exact Hnth].
  replace (lo + (i - lo)) with i in Hx by lia. exact Hx.
Qed.

Lemma decode_full_pointwise :
  forall i, i < 99 ->
    decode_word_p (literal_word_at i) =
    Some (nth i fixture_prog_full instrp_default).
Proof.
  intros i Hi.
  destruct literal_full_code_decodes as [_ [Hdec _]].
  destruct (decode_range_p_nth 0 99 fixture_prog_full i Hdec ltac:(lia) Hi)
    as [x [Hx Hnth]].
  rewrite Hx.
  f_equal.
  replace (i - 0) with i in Hnth by lia.
  symmetry. eapply nth_error_nth. exact Hnth.
Qed.

Lemma decode_full_pointwise_nth_error :
  forall i, i < 99 ->
    decode_word_p (literal_word_at i) =
    Some (nth i fixture_prog_full instrp_default).
Proof. apply decode_full_pointwise. Qed.

(** ** Assumption audit *)

Print Assumptions literal_full_code_decodes.
Print Assumptions literal_code_slices_decode.
Print Assumptions decode_full_pointwise.
