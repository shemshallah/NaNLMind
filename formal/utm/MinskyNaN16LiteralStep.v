(** * ISA-OBL-3d step 1: literal NaN16 machine and generic fuel theory

    This module isolates the executable literal machine from the run
    certificates.  The memory representation keeps the immutable image
    ([literal_image]) as a global ROM and stores only the five control
    cells and the 256-cell tape window, plus an overlay for any write
    outside those regions.  For this fixture the overlay stays empty,
    which is checked by computation in the run modules, but the model
    keeps it so that [mem_get]/[mem_set] are total and faithful.

    The generic results proved here are:

      - [mem_get_reset]: the block lookup at the reset state is the
        literal image lookup on [0,4366);
      - [lp_step_fetch]: for every state and every [pc < 99], one
        literal step is exactly the [fixture_prog_full] instruction at
        that [pc] (the "step-to-program agreement");
      - [lp_run_add]: fuel composition for [lp_run];
      - [lp_run_steps_until_spec]: the counting runner returns the
        state after exactly the number of steps it reports.

    None of these reduces a concrete run.  The concrete runs live in
    [MinskyNaN16LiteralChain*.v] and the headline statements in
    [MinskyNaN16LiteralRun.v]. *)

From Coq Require Import List Arith Bool Lia NArith String.
From Coq Require Import Strings.String.
Import ListNotations.
Open Scope string_scope.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16LiteralImage MinskyNaN16LiteralPuts LiteralImageData
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  MinskyNaN16Run MinskyNaN16StepSpec MinskyTable MinskyTableData.

Open Scope nat_scope.

(** ** Image layout *)

Definition code_hi : nat := 99.
Definition ctrl_hi : nat := 104.
Definition tab_hi : nat := 1576.
Definition pad_hi : nat := 4096.
Definition tape_lo : nat := 4096.
Definition tape_hi : nat := 4352.

(** ** Literal state *)

Record MemP := {
  mp_ctrl : list N;               (*  99 .. 103  *)
  mp_tape : list N;               (* 4096 .. 4351 *)
  mp_over : list (nat * N);       (* writes elsewhere; empty for the fixture *)
}.

Record LPState := {
  lp_pc : nat;
  lp_reg : list N;
  lp_mem : MemP;
  lp_k : nat;
  lp_halted : bool;
  lp_out : string;
}.

(** ** Registers *)

Definition lget_regN (r : list N) (i : nat) : N := nth i r 0%N.
Definition lget_reg (r : list N) (i : nat) : nat := N.to_nat (lget_regN r i).

Fixpoint lsetN (l : list N) (i : nat) (v : N) : list N :=
  match l with
  | [] => []
  | x :: xs =>
      match i with
      | 0 => v :: xs
      | S k => x :: lsetN xs k v
      end
  end.

Definition regs0 : list N := repeat 0%N 16.

Definition rom_get (a : nat) : N := nth a literal_image 0%N.

Fixpoint over_get (l : list (nat * N)) (a : nat) : option N :=
  match l with
  | [] => None
  | (b, v) :: t => if Nat.eqb a b then Some v else over_get t a
  end.

Definition mem_get (m : MemP) (a : nat) : N :=
  if a <? code_hi then
    match over_get (mp_over m) a with Some v => v | None => rom_get a end
  else if a <? ctrl_hi then nth (a - code_hi) (mp_ctrl m) 0%N
  else if a <? tape_lo then
    match over_get (mp_over m) a with Some v => v | None => rom_get a end
  else if a <? tape_hi then nth (a - tape_lo) (mp_tape m) 0%N
  else
    match over_get (mp_over m) a with Some v => v | None => rom_get a end.

Definition mem_set (m : MemP) (a : nat) (v : N) : MemP :=
  if a <? code_hi then
    {| mp_ctrl := mp_ctrl m; mp_tape := mp_tape m;
       mp_over := (a, v) :: mp_over m |}
  else if a <? ctrl_hi then
    {| mp_ctrl := lsetN (mp_ctrl m) (a - code_hi) v;
       mp_tape := mp_tape m; mp_over := mp_over m |}
  else if a <? tape_lo then
    {| mp_ctrl := mp_ctrl m; mp_tape := mp_tape m;
       mp_over := (a, v) :: mp_over m |}
  else if a <? tape_hi then
    {| mp_ctrl := mp_ctrl m; mp_tape := lsetN (mp_tape m) (a - tape_lo) v;
       mp_over := mp_over m |}
  else
    {| mp_ctrl := mp_ctrl m; mp_tape := mp_tape m;
       mp_over := (a, v) :: mp_over m |}.

Definition reset_mem : MemP :=
  {| mp_ctrl := firstn 5 (skipn 99 literal_image);
     mp_tape := firstn 256 (skipn 4096 literal_image);
     mp_over := [] |}.

(** ** 32-bit word arithmetic, performed in binary [N] *)

Definition word_mask32 : N := 0xFFFFFFFF%N.
Definition two32N : N := 0x100000000%N.

Definition mod32N (x : N) : N := N.land x word_mask32.
Definition shl32N (a : N) (n : nat) : N :=
  N.land (N.shiftl a (N.of_nat n)) word_mask32.
Definition shr32N (a : N) (n : nat) : N :=
  N.land (N.shiftr a (N.of_nat n)) word_mask32.
Definition bnot32N (x : N) : N :=
  N.land (N.lxor x word_mask32) word_mask32.
Definition sub32N (a b : N) : N :=
  N.land (N.add a (N.sub two32N b)) word_mask32.

Definition bool_resN (tbl : nat) (a b : N) : N :=
  N.add
   (if Nat.eqb (Nat.land tbl 1) 1 then bnot32N (N.lor a b) else 0%N)
   (N.add
    (if Nat.eqb (Nat.land tbl 2) 2 then N.land (bnot32N a) b else 0%N)
    (N.add
     (if Nat.eqb (Nat.land tbl 4) 4 then N.land a (bnot32N b) else 0%N)
     (if Nat.eqb (Nat.land tbl 8) 8 then N.land a b else 0%N))).

Definition nan_mkwordN (v : N) (n : nat) : N :=
  (N.shiftl (nan_head ((n / 4) mod 4)) 48
   + N.shiftl (N.land v word_mask32) 16
   + swap16 (nan_head (n mod 4)))%N.

(** ** One literal instruction *)

Definition lp_exec (L : LPState) (ins : InstrP) : LPState :=
  match ins with
  | pMOVI d imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d (N.of_nat imm);
         lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pLD d a imm =>
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d
                     (N.of_nat (payload_word
                        (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))));
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
                   (Nat.eqb (lget_reg (lp_reg L) a) (lget_reg (lp_reg L) b))
                   (Nat.ltb (lget_reg (lp_reg L) a) (lget_reg (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pJMP p target =>
      {| lp_pc := if pred_passes (pred_nat p) (lp_k L)
                  then target else S (lp_pc L);
         lp_reg := lp_reg L; lp_mem := lp_mem L; lp_k := lp_k L;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHL d a imm =>
      let v := shl32N (lget_regN (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSHR d a imm =>
      let v := shr32N (lget_regN (lp_reg L) a) (imm mod 32) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) false;
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pADD d a b =>
      let s := N.add (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b) in
      let v := mod32N s in
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N) (N.leb two32N s);
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pSUB d a b =>
      let v := sub32N (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d v;
         lp_mem := lp_mem L;
         lp_k := pack_k (N.eqb v 0%N)
                   (N.ltb (lget_regN (lp_reg L) a) (lget_regN (lp_reg L) b));
         lp_halted := lp_halted L; lp_out := lp_out L |}
  | pBOOL tbl d a b =>
      let res := bool_resN tbl (lget_regN (lp_reg L) a)
                               (lget_regN (lp_reg L) b) in
      {| lp_pc := S (lp_pc L);
         lp_reg := lsetN (lp_reg L) d res;
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
         lp_reg := lsetN (lp_reg L) 15 (N.of_nat (S (lp_pc L)));
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

(** ** Reset lookup is the literal image *)

Lemma nth_firstn_lt :
  forall (A : Type) (n i : nat) (l : list A) (d : A),
    i < n -> nth i (firstn n l) d = nth i l d.
Proof.
  intros A n i l d Hi.
  rewrite nth_firstn.
  apply Nat.ltb_lt in Hi. rewrite Hi. reflexivity.
Qed.

Lemma over_get_nil : forall a, over_get [] a = None.
Proof. reflexivity. Qed.

Lemma mem_get_reset :
  forall a, a < 4366 -> mem_get reset_mem a = nth a literal_image 0%N.
Proof.
  intros a Ha.
  unfold mem_get, reset_mem, rom_get, code_hi, ctrl_hi, tape_lo, tape_hi.
  cbn [mp_ctrl mp_tape mp_over].
  rewrite over_get_nil.
  destruct (a <? 99) eqn:E1.
  - reflexivity.
  - destruct (a <? 104) eqn:E2.
    + rewrite nth_firstn.
      apply Nat.ltb_lt in E2. apply Nat.ltb_ge in E1.
      assert (H : (a - 99 <? 5) = true) by (apply Nat.ltb_lt; lia).
      rewrite H. rewrite nth_skipn.
      replace (99 + (a - 99)) with a by lia. reflexivity.
    + destruct (a <? 4096) eqn:E3.
      * reflexivity.
      * destruct (a <? 4352) eqn:E4.
        -- rewrite nth_firstn.
           apply Nat.ltb_lt in E4. apply Nat.ltb_ge in E3.
           assert (H : (a - 4096 <? 256) = true) by (apply Nat.ltb_lt; lia).
           rewrite H. rewrite nth_skipn.
           replace (4096 + (a - 4096)) with a by lia. reflexivity.
        -- reflexivity.
Qed.

(** ** Generic step-to-program agreement *)

Definition code_intact (m : MemP) : Prop :=
  forall i, i < 99 -> mem_get m i = literal_word_at i.

Lemma code_intact_reset : code_intact reset_mem.
Proof.
  intros i Hi. apply mem_get_reset. lia.
Qed.

Lemma lp_step_fetch :
  forall L,
    code_intact (lp_mem L) ->
    lp_pc L < 99 ->
    lp_step L = lp_exec L (nth (lp_pc L) fixture_prog_full instrp_default).
Proof.
  intros L Hc Hpc.
  unfold lp_step.
  rewrite (Hc (lp_pc L) Hpc).
  rewrite decode_full_pointwise by exact Hpc.
  reflexivity.
Qed.

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
      cbn [lp_run].
      rewrite E.
      apply IH. exact H.
Qed.

Lemma lp_run_add_state :
  forall a b L L1,
    lp_run a L = L1 ->
    lp_halted L1 = false ->
    lp_run (a + b) L = lp_run b L1.
Proof.
  intros a b L L1 Ha Hh.
  rewrite <- Ha.
  apply lp_run_add.
  rewrite Ha. exact Hh.
Qed.

(** ** Counting runner

    [lp_run_steps_until] executes while neither halted nor [stop], and
    returns the number of steps actually taken together with the final
    state.  Its specification is the fuel induction used by the run
    certificates: the second component is [lp_run] of the first. *)

Fixpoint lp_run_steps_until (stop : LPState -> bool) (fuel : nat)
    (L : LPState) : nat * LPState :=
  match fuel with
  | 0 => (0, L)
  | S f =>
      if lp_halted L then (0, L)
      else if stop L then (0, L)
      else
        match lp_run_steps_until stop f (lp_step L) with
        | (n, L') => (S n, L')
        end
  end.

Definition lp_run_steps (fuel : nat) (L : LPState) : nat * LPState :=
  lp_run_steps_until (fun _ => false) fuel L.

Definition stop_pc (p : nat) (L : LPState) : bool := Nat.eqb (lp_pc L) p.

Lemma lp_run_steps_until_spec :
  forall stop fuel L,
    snd (lp_run_steps_until stop fuel L) =
    lp_run (fst (lp_run_steps_until stop fuel L)) L.
Proof.
  induction fuel as [|f IH]; intros L.
  - cbn. reflexivity.
  - cbn [lp_run_steps_until].
    destruct (lp_halted L) eqn:Eh.
    + cbn. reflexivity.
    + destruct (stop L) eqn:Es.
      * cbn. reflexivity.
      * destruct (lp_run_steps_until stop f (lp_step L)) as [n L'] eqn:Ep.
        cbn [fst snd].
        pose proof (IH (lp_step L)) as H.
        rewrite Ep in H. cbn [fst snd] in H.
        rewrite H.
        cbn [lp_run]. rewrite Eh. reflexivity.
Qed.

Lemma lp_run_steps_spec :
  forall fuel L,
    snd (lp_run_steps fuel L) =
    lp_run (fst (lp_run_steps fuel L)) L.
Proof. intros. apply lp_run_steps_until_spec. Qed.

(** Concrete scheduling lemmas: if a chunk reports [n] steps, it is
    exactly [lp_run n] of the entry state. *)

Lemma lp_run_steps_until_chunk :
  forall stop fuel L n L',
    lp_run_steps_until stop fuel L = (n, L') ->
    lp_run n L = L'.
Proof.
  intros stop fuel L n L' H.
  pose proof (lp_run_steps_until_spec stop fuel L) as Hs.
  rewrite H in Hs. cbn [fst snd] in Hs. symmetry. exact Hs.
Qed.

Lemma lp_run_steps_chunk :
  forall fuel L n L',
    lp_run_steps fuel L = (n, L') ->
    lp_run n L = L'.
Proof.
  intros fuel L n L' H.
  unfold lp_run_steps in H.
  apply lp_run_steps_until_chunk with (stop := fun _ => false) (fuel := fuel).
  exact H.
Qed.

(** Assumption audit *)

Print Assumptions mem_get_reset.
Print Assumptions lp_step_fetch.
Print Assumptions lp_run_add.
Print Assumptions lp_run_steps_until_spec.
