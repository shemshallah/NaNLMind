(** * ISA-OBL-3d: literal NaN16 machine (definitions only)

    This module isolates the literal NaN16 state machine used by the
    full-fixture run certificates: the five-block memory representation,
    the executable instruction semantics, and the fuel runner [lp_run].

    All concrete runs are certified in separate modules so that the
    20k-instruction prefix evaluation and the 778-instruction tail
    evaluation are compiled by separate Coq processes (and, in CI, by
    separate async workers).  No proof in this file reduces a concrete
    run. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts LiteralImageData
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  MinskyNaN16Run MinskyNaN16StepSpec MinskyTable MinskyTableData.

Open Scope nat_scope.

(** ** Block boundaries of the literal image *)

Definition code_hi : nat := 99.
Definition data_lo : nat := 99.
Definition data_hi : nat := 1576.
Definition pad_lo : nat := 1576.
Definition pad_hi : nat := 4096.
Definition tape_lo : nat := 4096.
Definition tape_hi : nat := 4352.
Definition str_lo : nat := 4352.

(** ** Concrete literal state *)

Record MemP := {
  mp_low : list N;    (*   0 .. 98    : code *)
  mp_data : list N;   (*  99 .. 1575  : control cells and table *)
  mp_pad : list N;    (* 1576 .. 4095 : .org padding *)
  mp_tape : list N;   (* 4096 .. 4351 : tape image *)
  mp_str : list N;    (* 4352 .. 4365 : PASS/FAIL strings *)
}.

Record LPState := {
  lp_pc : nat;
  lp_reg : list N;
  lp_mem : MemP;
  lp_k : nat;
  lp_halted : bool;
  lp_out : string;
}.

(** Registers hold 64-bit NaN16 words.  [lget_regN] is the value used by
    the executor; [lget_reg] is the [nat] projection used by the final
    statements, which only inspect small counters and addresses. *)
Definition lget_regN (r : list N) (i : nat) : N := nth i r 0%N.

Definition lget_reg (r : list N) (i : nat) : nat :=
  N.to_nat (lget_regN r i).

Fixpoint lset_word (l : list N) (i : nat) (v : N) : list N :=
  match l with
  | [] => []
  | x :: xs =>
      match i with
      | 0 => v :: xs
      | S k => x :: lset_word xs k v
      end
  end.

(** Register update on the concrete [N] register file.  The stored value is
    a small [nat] projection (immediate, address, counter or 32-bit result),
    so converting it back to [N] preserves the executor's semantics. *)
Fixpoint lset_nat (l : list N) (i : nat) (v : nat) : list N :=
  match l with
  | [] => []
  | x :: xs =>
      match i with
      | 0 => N.of_nat v :: xs
      | S k => x :: lset_nat xs k v
      end
  end.

Definition regs0 : list N := repeat 0%N 16.

(** ** Block lookup and update

    The branch order puts the small code/table addresses first and
    handles the tape by a single [4096] comparison. *)

Definition mem_get (m : MemP) (a : nat) : N :=
  if a <? tape_lo then
    if a <? data_hi then
      if a <? code_hi then nth a (mp_low m) 0%N
      else nth (a - data_lo) (mp_data m) 0%N
    else nth (a - pad_lo) (mp_pad m) 0%N
  else if a <? tape_hi then nth (a - tape_lo) (mp_tape m) 0%N
  else nth (a - str_lo) (mp_str m) 0%N.

Definition mem_set (m : MemP) (a : nat) (v : N) : MemP :=
  if a <? tape_lo then
    if a <? data_hi then
      if a <? code_hi then
        {| mp_low := lset_word (mp_low m) a v;
           mp_data := mp_data m; mp_pad := mp_pad m;
           mp_tape := mp_tape m; mp_str := mp_str m |}
      else
        {| mp_low := mp_low m;
           mp_data := lset_word (mp_data m) (a - data_lo) v;
           mp_pad := mp_pad m; mp_tape := mp_tape m;
           mp_str := mp_str m |}
    else
      {| mp_low := mp_low m; mp_data := mp_data m;
         mp_pad := lset_word (mp_pad m) (a - pad_lo) v;
         mp_tape := mp_tape m; mp_str := mp_str m |}
  else if a <? tape_hi then
    {| mp_low := mp_low m; mp_data := mp_data m; mp_pad := mp_pad m;
       mp_tape := lset_word (mp_tape m) (a - tape_lo) v;
       mp_str := mp_str m |}
  else
    {| mp_low := mp_low m; mp_data := mp_data m; mp_pad := mp_pad m;
       mp_tape := mp_tape m;
       mp_str := lset_word (mp_str m) (a - str_lo) v |}.

Definition reset_mem : MemP :=
  {| mp_low := firstn 99 literal_image;
     mp_data := firstn 1477 (skipn 99 literal_image);
     mp_pad := firstn 2520 (skipn 1576 literal_image);
     mp_tape := firstn 256 (skipn 4096 literal_image);
     mp_str := skipn 4352 literal_image |}.

(** Initial block lookup is literal-image lookup. *)

Lemma nth_firstn_lt :
  forall (A : Type) (n i : nat) (l : list A) (d : A),
    i < n -> nth i (firstn n l) d = nth i l d.
Proof.
  intros A n i l d Hi.
  rewrite nth_firstn.
  apply Nat.ltb_lt in Hi. rewrite Hi. reflexivity.
Qed.

Lemma mem_get_reset :
  forall a, a < 4366 -> mem_get reset_mem a = nth a literal_image 0%N.
Proof.
  intros a Ha.
  unfold mem_get, reset_mem, tape_lo, data_hi, code_hi, data_lo,
    pad_lo, pad_hi, tape_hi, str_lo.
  cbn [mp_low mp_data mp_pad mp_tape mp_str].
  destruct (a <? 4096) eqn:E1.
  - destruct (a <? 1576) eqn:E2.
    + destruct (a <? 99) eqn:E3.
      * rewrite nth_firstn. rewrite E3. reflexivity.
      * rewrite nth_firstn.
        apply Nat.ltb_lt in E2.
        apply Nat.ltb_ge in E3.
        assert (Hlt : (a - 99 <? 1477) = true)
          by (apply Nat.ltb_lt; lia).
        rewrite Hlt. rewrite nth_skipn.
        replace (99 + (a - 99)) with a by lia. reflexivity.
    + rewrite nth_firstn.
      apply Nat.ltb_lt in E1.
      apply Nat.ltb_ge in E2.
      assert (Hlt : (a - 1576 <? 2520) = true)
        by (apply Nat.ltb_lt; lia).
      rewrite Hlt. rewrite nth_skipn.
      replace (1576 + (a - 1576)) with a by lia. reflexivity.
  - destruct (a <? 4352) eqn:E5.
    + rewrite nth_firstn.
      apply Nat.ltb_lt in E5.
      apply Nat.ltb_ge in E1.
      assert (Hlt : (a - 4096 <? 256) = true)
        by (apply Nat.ltb_lt; lia).
      rewrite Hlt. rewrite nth_skipn.
      replace (4096 + (a - 4096)) with a by lia. reflexivity.
    + apply Nat.ltb_ge in E5.
      rewrite nth_skipn.
      replace (4352 + (a - 4352)) with a by lia. reflexivity.
Qed.

(** ** Executable 32-bit arithmetic

    NaN16 registers are 32-bit payload words.  They are represented as
    binary [N] inside the executor.  Spelling the operations with [nat]
    (for example [x mod 2 ^ 32]) would make the kernel VM allocate four
    billion successors, and packed string words such as [0x4D544820]
    would be expanded to a unary [nat] on every load.  The helpers below
    are the same 32-bit masked operations as the ISA specification. *)

Definition word_mask32 : N := 0xFFFFFFFF%N.
Definition two32 : N := 0x100000000%N.

Definition mod32N (x : N) : N := N.land x word_mask32.

Definition sub32N (a b : N) : N :=
  N.land (N.add a (N.sub two32 b)) word_mask32.

Definition shl32N (a : N) (n : nat) : N :=
  N.land (N.shiftl a (N.of_nat n)) word_mask32.

Definition shr32N (a : N) (n : nat) : N :=
  N.land (N.shiftr a (N.of_nat n)) word_mask32.

Definition bnot32N (x : N) : N :=
  N.land (N.lxor x word_mask32) word_mask32.

(** [nat]-projected 32-bit operations retained for the older nat-facing
    statements.  [lp_exec] must NOT use these on a register that can hold
    a packed character word: [N.to_nat] would build a unary numeral of up
    to [2^32] constructors. *)
Definition mod32 (x : nat) : nat :=
  N.to_nat (N.land (N.of_nat x) word_mask32).

Definition shl32 (a n : nat) : nat :=
  N.to_nat (N.land (N.shiftl (N.of_nat a) (N.of_nat n)) word_mask32).

Definition shr32 (a n : nat) : nat :=
  N.to_nat (N.shiftr (N.of_nat a) (N.of_nat n)).

Definition ge32 (x : nat) : bool :=
  N.leb 0x100000000%N (N.of_nat x).

Definition bnot32 (x : nat) : nat :=
  N.to_nat (N.land (N.lxor (N.of_nat x) word_mask32) word_mask32).

Definition bool_res (tbl a b : nat) : nat :=
  (if Nat.eqb (Nat.land tbl 1) 1 then bnot32 (Nat.lor a b) else 0) +
  (if Nat.eqb (Nat.land tbl 2) 2 then Nat.land (bnot32 a) b else 0) +
  (if Nat.eqb (Nat.land tbl 4) 4 then Nat.land a (bnot32 b) else 0) +
  (if Nat.eqb (Nat.land tbl 8) 8 then Nat.land a b else 0).

(** ** BOOL truth table

    [tbl] is the four-bit [n] field.  The four products are the four
    disjoint bit classes of NAN0S_ISA_SPEC.md section 4.1. *)

Definition bool_resN (tbl : nat) (a b : N) : N :=
  N.add
   (if Nat.eqb (Nat.land tbl 1) 1 then bnot32N (N.lor a b) else 0%N)
   (N.add
    (if Nat.eqb (Nat.land tbl 2) 2 then N.land (bnot32N a) b else 0%N)
    (N.add
     (if Nat.eqb (Nat.land tbl 4) 4 then N.land a (bnot32N b) else 0%N)
     (if Nat.eqb (Nat.land tbl 8) 8 then N.land a b else 0%N))).

(** Store constructor at word level, avoiding a [nat] round-trip. *)
Definition nan_mkwordN (v : N) (n : nat) : N :=
  (N.shiftl (nan_head ((n / 4) mod 4)) 48
   + N.shiftl (N.land v word_mask32) 16
   + swap16 (nan_head (n mod 4)))%N.

(** ** Literal instruction semantics

    Every value that can be a packed 32-bit word is read and written in
    binary [N].  In particular LD, CMP, SHL, SHR, ADD, SUB, BOOL and
    PUTC never project a register (or a memory payload) through unary
    [nat]: the [puts] block loads words such as [0x2048544D], and
    [N.to_nat] would build hundreds of millions of constructors. *)

Definition lp_exec (L : LPState) (ins : InstrP) : LPState :=
  match ins with
  | pMOVI d imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d (N.of_nat imm);
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pLD d a imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d
                     (word_payload
                        (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)));
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pST d a imm =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L;
         lp_mem := mem_set (lp_mem L) (lget_reg (lp_reg L) a + imm)
                     (nan_mkwordN (lget_regN (lp_reg L) d) 10);
         lp_k := lp_k L; lp_halted := lp_halted L; lp_out := lp_out L |}
  | pCMP a b =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L; lp_mem := lp_mem L;
         lp_k := pack_k
                   (N.eqb (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b))
                   (N.ltb (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pJMP p target =>
      {| lp_pc := if pred_passes (pred_nat p) (lp_k L)
                  then target else S (lp_pc L);
         lp_reg := lp_reg L; lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHL d a imm =>
      let v := shl32N (lget_regN (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHR d a imm =>
      let v := shr32N (lget_regN (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pADD d a b =>
      let s := N.add (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b) in
      let v := mod32N s in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) (N.leb two32 s);
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSUB d a b =>
      let v := sub32N (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N)
                   (N.ltb (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pBOOL tbl d a b =>
      let res := bool_resN tbl (lget_regN (lp_reg L) a)
                               (lget_regN (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_word (lp_reg L) d res;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb res 0%N) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pPUTC d =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L; lp_mem := lp_mem L;
         lp_k := lp_k L; lp_halted := lp_halted L;
         lp_out := append (lp_out L)
                     (String (Ascii.ascii_of_nat
                                (N.to_nat (N.land (lget_regN (lp_reg L) d) 255%N)))
                             EmptyString) |}
  | pCALL target =>
      {| lp_pc := target;
         lp_reg := lset_word (lp_reg L) 15 (N.of_nat (S (lp_pc L)));
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pRET =>
      {| lp_pc := lget_reg (lp_reg L) 15; lp_reg := lp_reg L;
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pRETP p =>
      {| lp_pc := if pred_passes (pred_nat p) (lp_k L)
                  then lget_reg (lp_reg L) 15 else S (lp_pc L);
         lp_reg := lp_reg L; lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pHALT =>
      {| lp_pc := lp_pc L; lp_reg := lp_reg L; lp_mem := lp_mem L;
         lp_k := lp_k L; lp_halted := true; lp_out := lp_out L |}
  end.

Definition lp_step (L : LPState) : LPState :=
  match decode_word_p (mem_get (lp_mem L) (lp_pc L)) with
  | Some ins => lp_exec L ins
  | None => L
  end.

Fixpoint lp_run (fuel : nat) (L : LPState) : LPState :=
  match fuel with
  | 0 => L
  | S f => if lp_halted L then L else lp_run f (lp_step L)
  end.

Definition lp_reset : LPState :=
  {| lp_pc := 0; lp_reg := regs0; lp_mem := reset_mem;
     lp_k := 0; lp_halted := false; lp_out := EmptyString |}.

(** ** Fixture initial state and prefix runner *)

(** [nrun] is the native step model of [MinskyNaN16StepSpec.v].  Its
    initial memory is the literal-image payload projection, with the
    fixture entry [state=5, head=166, halt=0]. *)

Definition fixture_nstate0 : NState :=
  {| n_state := 5;
     n_head := 166;
     n_halt := 0;
     n_mem := fun a => payload_word (nth a literal_image 0%N) |}.

Definition nrun100 : NState :=
  nrun 100 fixture_table fixture_table_base fixture_tape_base fixture_nstate0.

(** The already-certified 20,247-instruction prefix.  The concrete value
    of this run is cached in [MinskyNaN16LiteralPrefix.v]; this file only
    records the definition. *)

Definition literal_run100 : LPState := lp_run 20247 lp_reset.

(** ** Fuel composition *)

Lemma lp_run_add :
  forall a b L,
    lp_halted (lp_run a L) = false ->
    lp_run (a + b) L = lp_run b (lp_run a L).
Proof.
  induction a as [|a IH]; intros b L H.
  - cbn. reflexivity.
  - cbn [lp_run] in *.
    destruct (lp_halted L) eqn:E.
    + rewrite E in H. discriminate.
    + replace (S a + b) with (S (a + b)) by lia.
      cbn [lp_run]. rewrite E.
      apply IH. exact H.
Qed.
