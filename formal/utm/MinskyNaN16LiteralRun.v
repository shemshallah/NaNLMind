(** * ISA-OBL-3d: literal execution of the full fixture program

    [MinskyNaN16LiteralPuts.v] proves that the literal code region
    [0,99) decodes to [fixture_prog_full], including the [puts] block.
    This file executes that code from the literal image itself.

    The machine below is a literal NaN16 state machine:

      - registers are a 16-element [nat] list;
      - memory is the literal word list, split into five contiguous
        blocks (code, control+table, [.org] padding, tape, strings);
      - flags are the packed [k = 2*Z + L] of the oracle;
      - [PUTC] appends the low byte of its operand to a [string].

    The five-block split is a representation choice only: it preserves
    every address the fixture reads or writes, and [mem_get_reset]
    proves that the initial block lookup is exactly the literal image
    lookup on [0,4366).  A single 4366-element [lset_word] per store is
    too memory-hungry for [vm_compute], hence the split.

    Results:

      - [literal_run100_matches_nrun100]: after the [run100] block has
        executed its 100 Minsky steps (20,247 literal instructions,
        ending back at [pc = 7]), the literal state, head and halt cells
        and the 73-cell tape window at [tbase + 128] agree with
        [nrun 100 fixture_table fixture_table_base fixture_tape_base];
      - [literal_full_run_pass]: from the reset state, 21,025 literal
        instructions reach [halted = true] with the PASS output
        ["MTH MINSKY NATIVE PASS"], state 2, head 166, halt 0, and the
        code cells [0,99) unchanged.

    The traditional OBL-RAW-1 phrase "100 steps" refers to the 100
    Minsky table steps, not to 100 literal instructions.  A single table
    step costs roughly 200 literal instructions; the exact fuel figures
    are recorded below. *)

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

Definition shl32N (a : N) (n : nat) : N :=
  N.land (N.shiftl a (N.of_nat n)) word_mask32.

Definition shr32N (a : N) (n : nat) : N :=
  N.land (N.shiftr a (N.of_nat n)) word_mask32.

Definition bnot32N (x : N) : N :=
  N.land (N.lxor x word_mask32) word_mask32.

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

(** ** Literal instruction semantics *)

Definition lp_exec (L : LPState) (ins : InstrP) : LPState :=
  match ins with
  | pMOVI d imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d imm;
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pLD d a imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d
                     (payload_word
                        (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)));
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pST d a imm =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L;
         lp_mem := mem_set (lp_mem L) (lget_reg (lp_reg L) a + imm)
                     (nan_mkword (lget_reg (lp_reg L) d) 10);
         lp_k := lp_k L; lp_halted := lp_halted L; lp_out := lp_out L |}
  | pCMP a b =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L; lp_mem := lp_mem L;
         lp_k := pack_k
                   (Nat.eqb (lget_reg (lp_reg L) a) (lget_reg (lp_reg L) b))
                   (Nat.ltb (lget_reg (lp_reg L) a) (lget_reg (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pJMP p target =>
      {| lp_pc := if pred_passes (pred_nat p) (lp_k L)
                  then target else S (lp_pc L);
         lp_reg := lp_reg L; lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHL d a imm =>
      let v := shl32 (lget_reg (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (Nat.eqb v 0) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHR d a imm =>
      let v := shr32 (lget_reg (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (Nat.eqb v 0) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pADD d a b =>
      let s := lget_reg (lp_reg L) a + lget_reg (lp_reg L) b in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d (mod32 s);
         lp_mem := lp_mem L;
         lp_k := pack_k (Nat.eqb (mod32 s) 0) (ge32 s);
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSUB d a b =>
      let v := mod32 (lget_reg (lp_reg L) a - lget_reg (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (Nat.eqb v 0)
                   (Nat.ltb (lget_reg (lp_reg L) a) (lget_reg (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pBOOL tbl d a b =>
      let res := bool_res tbl (lget_reg (lp_reg L) a)
                             (lget_reg (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lset_nat (lp_reg L) d res;
         lp_mem := lp_mem L;
         lp_k := pack_k (Nat.eqb res 0) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pPUTC d =>
      {| lp_pc := S (lp_pc L); lp_reg := lp_reg L; lp_mem := lp_mem L;
         lp_k := lp_k L; lp_halted := lp_halted L;
         lp_out := append (lp_out L)
                     (String (Ascii.ascii_of_nat
                                (lget_reg (lp_reg L) d mod 256))
                             EmptyString) |}
  | pCALL target =>
      {| lp_pc := target;
         lp_reg := lset_nat (lp_reg L) 15 (S (lp_pc L));
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

(** ** PASS string *)

Definition pass_string : string := "MTH MINSKY NATIVE PASS"%string.

(** The code region was not written: structural equality of the code
    block with its initial value. *)
Definition code_preserved_bool (m : MemP) : bool :=
  forallb (fun i => N.eqb (nth i (mp_low m) 0%N) (nth i literal_image 0%N))
          (seq 0 99).

(** ** The 100 Minsky steps

    [nrun] is the native step model of [MinskyNaN16StepSpec.v].  Its
    initial memory is the literal-image payload projection, with the
    fixture entry [state=5, head=166, halt=0]. *)

Definition fixture_nstate0 : NState :=
  {| n_state := 5;
     n_head := 166;
     n_halt := 0;
     n_mem := fun a => payload_word (nth a literal_image 0%N) |}.

Definition nrun100 : NState :=
  nrun 100 fixture_table fixture_table_base fixture_tape_base fixture_nstate0.

Definition literal_run100 : LPState := lp_run 20247 lp_reset.

Theorem literal_run100_matches_nrun100 :
  lp_pc literal_run100 = 7 /\
  payload_word (mem_get (lp_mem literal_run100) action_state_addr) =
    n_state nrun100 /\
  payload_word (mem_get (lp_mem literal_run100) action_head_addr) =
    n_head nrun100 /\
  payload_word (mem_get (lp_mem literal_run100) action_halt_addr) =
    n_halt nrun100 /\
  map (fun i =>
         payload_word
           (mem_get (lp_mem literal_run100)
              (fixture_tape_base + 128 + i)))
      (seq 0 73) =
  map (fun i => n_mem nrun100 (fixture_tape_base + 128 + i)) (seq 0 73).
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

(** The native run agrees with the published table trace: state 2,
    head 166, halt 0, and the 73-cell expected tape window. *)

Theorem nrun100_matches_published_trace :
  n_state nrun100 = 2 /\
  n_head nrun100 = 166 /\
  n_halt nrun100 = 0 /\
  map (fun i => n_mem nrun100 (fixture_tape_base + 128 + i)) (seq 0 73)
    = expected_cells.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

Theorem literal_run100_cells :
  payload_word (mem_get (lp_mem literal_run100) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_run100) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_run100) action_halt_addr) = 0 /\
  map (fun i =>
         payload_word
           (mem_get (lp_mem literal_run100)
              (fixture_tape_base + 128 + i)))
      (seq 0 73) = expected_cells.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

(** ** The full program, including the PASS check and puts call *)

Definition literal_final : LPState := lp_run 21025 lp_reset.

Theorem literal_full_run_pass :
  lp_halted literal_final = true /\
  lp_pc literal_final = 28 /\
  payload_word (mem_get (lp_mem literal_final) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_final) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_final) action_halt_addr) = 0 /\
  lp_out literal_final = pass_string /\
  lget_reg (lp_reg literal_final) 1 = 4357 /\
  code_preserved_bool (lp_mem literal_final) = true.
Proof.
  vm_compute. repeat split; reflexivity.
Qed.

(** ** Full-image statement *)

Theorem literal_image_code_and_pass :
  decode_range_p 0 99 = Some fixture_prog_full /\
  List.length literal_image = 4366 /\
  lp_halted literal_final = true /\
  lp_out literal_final = pass_string /\
  payload_word (mem_get (lp_mem literal_final) action_state_addr) = 2 /\
  payload_word (mem_get (lp_mem literal_final) action_head_addr) = 166 /\
  payload_word (mem_get (lp_mem literal_final) action_halt_addr) = 0 /\
  code_preserved_bool (lp_mem literal_final) = true.
Proof.
  destruct literal_full_code_decodes as [Hlen [Hdec Hplen]].
  destruct literal_full_run_pass as
    (Hh & Hpc & Hs & Hhd & Hht & Hout & Hr1 & Hcode).
  repeat split; assumption.
Qed.

(** ** Assumption audit *)

Print Assumptions literal_run100_matches_nrun100.
Print Assumptions nrun100_matches_published_trace.
Print Assumptions literal_full_run_pass.
Print Assumptions literal_image_code_and_pass.
