(** * A formal NaN16 ISA subset for the native Minsky fixture

    STATUS: Layer 2 scaffold.  This file models the instruction subset
    used by [mth/tests/mth_minsky_test.nas] (labels/PCs, registers,
    memory, flags, predicates), the native scan block, and the
    table-memory invariant.  It does NOT yet contain the scan-loop,
    step, or run100 refinement theorem.  Those are the next proof
    obligations; do not cite this module as a Coq <-> NaN0S VM
    certificate.

    The model is a trusted-ISA boundary: it is a direct semantics of the
    instructions used by the fixture, checked against the .nas text by a
    transcription gate.  It is not a refinement of [third_party/nan0s/core/nan16.c].
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTableData MinskyTable MinskyNaN16Words.

Open Scope nat_scope.

(** ** Registers, memory, flags *)

Definition Reg := nat -> nat.
Definition Mem := nat -> nat.

Record VM := {
  vm_pc : nat;
  vm_reg : Reg;
  vm_mem : Mem;
  vm_zf : bool;
  vm_lf : bool;
  vm_halted : bool;
  vm_link : nat;
}.

Definition reg0 : Reg := fun _ => 0.

Definition vm0 : VM :=
  {| vm_pc := 0; vm_reg := reg0; vm_mem := fun _ => 0;
     vm_zf := false; vm_lf := false; vm_halted := false; vm_link := 0 |}.

Definition set_reg (r : Reg) (d v : nat) : Reg :=
  fun k => if Nat.eqb k d then v else r k.

Definition get_reg (r : Reg) (d : nat) : nat := r d.

(** ** Predicates (the NaN16 [n] field)

    The native encoding has [k = 2*Z + L] and jumps when
    [(n >> k) & 1].  The predicates used by the fixture are EQ, NE, LT,
    GE, GT, LE, ALWAYS, NEVER. *)

Inductive preg :=
| pEQ | pNE | pLT | pGE | pGT | pLE | pALWAYS | pNEVER.

Definition pred_holds (p : preg) (zf lf : bool) : bool :=
  match p with
  | pEQ => zf
  | pNE => negb zf
  | pLT => lf
  | pGE => orb zf (negb lf)
  | pGT => andb (negb zf) (negb lf)
  | pLE => orb zf lf
  | pALWAYS => true
  | pNEVER => false
  end.

(** ** Instructions *)

Inductive Instr :=
| iCMP (a b : nat)
| iJMP (p : preg) (target : nat)
| iSHL (d a imm : nat)
| iADD (d a b : nat)
| iSUB (d a b : nat)
| iLD (d a imm : nat)
| iST (d a imm : nat)
| iMOVI (d imm : nat)
| iCALL (target : nat)
| iRET
| iHALT.

Definition instr_succ (pc : nat) : nat := S pc.

Definition exec_instr (prog : list Instr) (vm : VM) : VM :=
  match nth_error prog (vm_pc vm) with
  | None => {| vm_pc := vm_pc vm; vm_reg := vm_reg vm;
               vm_mem := vm_mem vm; vm_zf := vm_zf vm; vm_lf := vm_lf vm;
               vm_halted := true; vm_link := vm_link vm |}
  | Some ins =>
      let r := vm_reg vm in
      let m := vm_mem vm in
      match ins with
      | iCMP a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          {| vm_pc := instr_succ (vm_pc vm); vm_reg := r; vm_mem := m;
             vm_zf := Nat.eqb A B; vm_lf := Nat.ltb A B;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iJMP p target =>
          let pc' := if pred_holds p (vm_zf vm) (vm_lf vm)
                     then target else instr_succ (vm_pc vm) in
          {| vm_pc := pc'; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iSHL d a imm =>
          let A := get_reg r a in
          let v := Nat.shiftl A imm in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iADD d a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          let v := A + B in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := false;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iSUB d a b =>
          let A := get_reg r a in
          let B := get_reg r b in
          let v := A - B in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := Nat.eqb v 0; vm_lf := Nat.ltb A B;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iLD d a imm =>
          let A := get_reg r a in
          let v := m (A + imm) in
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d v; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iST d a imm =>
          let A := get_reg r a in
          let v := get_reg r d in
          let m' := fun k => if Nat.eqb k (A + imm) then v else m k in
          {| vm_pc := instr_succ (vm_pc vm); vm_reg := r; vm_mem := m';
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iMOVI d imm =>
          {| vm_pc := instr_succ (vm_pc vm);
             vm_reg := set_reg r d imm; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iCALL target =>
          {| vm_pc := target; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := instr_succ (vm_pc vm) |}
      | iRET =>
          {| vm_pc := vm_link vm; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := vm_halted vm; vm_link := vm_link vm |}
      | iHALT =>
          {| vm_pc := vm_pc vm; vm_reg := r; vm_mem := m;
             vm_zf := vm_zf vm; vm_lf := vm_lf vm;
             vm_halted := true; vm_link := vm_link vm |}
      end
  end.

Fixpoint run_until (fuel : nat) (prog : list Instr) (stop : nat -> bool)
    (vm : VM) : VM :=
  match fuel with
  | 0 => vm
  | S k =>
      if orb (stop (vm_pc vm)) (vm_halted vm)
      then vm
      else run_until k prog stop (exec_instr prog vm)
  end.

(** ** The native scan block

    This is the exact control-flow block starting at label [scan] in
    [mth/tests/mth_minsky_test.nas].  The match and no-match exits are
    represented by [scan_match_pc] and [scan_none_pc]; the rest of the
    step routine is built in the next module. *)

Definition scan_block : list Instr :=
  [ iCMP 8 6;
    iJMP pGE 13;
    iSHL 7 8 3;
    iADD 7 7 5;
    iLD 9 7 0;
    iCMP 9 1;
    iJMP pNE 11;
    iLD 9 7 1;
    iCMP 9 4;
    iJMP pNE 11;
    iJMP pALWAYS 14;
    iADD 8 8 13;
    iJMP pALWAYS 0;
    iHALT;
    iHALT ].

Definition scan_match_pc : nat := 14.
Definition scan_none_pc : nat := 13.

Definition scan_stop (pc : nat) : bool :=
  orb (Nat.eqb pc scan_match_pc) (Nat.eqb pc scan_none_pc).

Definition scan_init (i state sym base : nat) (m : Mem) : VM :=
  {| vm_pc := 0;
     vm_reg := set_reg (set_reg (set_reg (set_reg (set_reg (set_reg reg0
       1 state) 4 sym) 5 base) 6 184) 8 i) 13 1;
     vm_mem := m; vm_zf := false; vm_lf := false;
     vm_halted := false; vm_link := 0 |}.

(** ** The table-memory invariant *)

Definition table_mem_at (start : nat) (table : list (list nat)) (m : Mem) : Prop :=
  forall i f, i < length table -> f < length (nth i table []) ->
    m (start + 8 * i + f) = nth f (nth i table []) 0.

Definition table_mem (base : nat) (table : list (list nat)) (m : Mem) : Prop :=
  table_mem_at base table m.

(** ** The list-level scan *)

Fixpoint scan_index_from (i : nat) (state sym : nat)
    (table : list (list nat)) : option (nat * list nat) :=
  match table with
  | [] => None
  | row :: rest =>
      if andb (Nat.eqb (nth 0 row 0) state) (Nat.eqb (nth 1 row 0) sym)
      then Some (i, row)
      else scan_index_from (S i) state sym rest
  end.

Lemma scan_index_from_ge :
  forall i state sym table,
    table = [] ->
    scan_index_from i state sym table = None.
Proof. intros; subst; reflexivity. Qed.

(** ** First semantic smoke test: a matching row reaches the match exit *)



(** ** The scan loop invariant *)

Definition scan_ready (vm : VM) (i state sym start : nat) (m : Mem) : Prop :=
  vm_pc vm = 0 /\
  vm_reg vm 1 = state /\
  vm_reg vm 4 = sym /\
  vm_reg vm 5 = start /\
  vm_reg vm 6 = 184 /\
  vm_reg vm 8 = i /\
  vm_reg vm 13 = 1 /\
  vm_mem vm = m /\
  vm_halted vm = false.

Lemma scan_ready_init :
  forall i state sym start m,
    scan_ready (scan_init i state sym start m) i state sym start m.
Proof.
  intros. unfold scan_ready, scan_init. cbn. repeat split; reflexivity.
Qed.

Lemma table_mem_at_head0 :
  forall start row rest m,
    0 < length row ->
    table_mem_at start (row :: rest) m ->
    m start = nth 0 row 0.
Proof.
  intros start row rest m Hlen H.
  unfold table_mem_at in H.
  specialize (H 0 0).
  assert (Hj : 0 < S (length rest)) by lia.
  assert (Hf : 0 < length row) by exact Hlen.
  specialize (H Hj Hf).
  cbn in H.
  replace (start + 0 + 0) with start in H by lia. exact H.
Qed.

Lemma table_mem_at_head1 :
  forall start row rest m,
    1 < length row ->
    table_mem_at start (row :: rest) m ->
    m (start + 1) = nth 1 row 0.
Proof.
  intros start row rest m Hlen H.
  unfold table_mem_at in H.
  specialize (H 0 1).
  assert (Hj : 0 < S (length rest)) by lia.
  specialize (H Hj Hlen).
  replace (start + 8 * 0 + 1) with (start + 1) in H by lia.
  exact H.
Qed.

Lemma table_mem_at_tail :
  forall start row rest m,
    table_mem_at start (row :: rest) m ->
    table_mem_at (start + 8) rest m.
Proof.
  intros start row rest m H.
  unfold table_mem_at in *.
  intros j f Hj Hf.
  specialize (H (S j) f).
  simpl in H.
  assert (Hj' : S j < S (length rest)) by lia.
  specialize (H Hj' Hf).
  change (m (start + 8 * S j + f) = nth f (nth j rest []) 0) in H.
  assert (Haddr : start + 8 * S j + f = start + 8 + 8 * j + f) by lia.
  rewrite Haddr in H. exact H.
Qed.

Lemma run_until_stop :
  forall fuel prog stop vm,
    orb (stop (vm_pc vm)) (vm_halted vm) = true ->
    run_until fuel prog stop vm = vm.
Proof.
  induction fuel as [|fuel IH]; intros prog stop vm H.
  - reflexivity.
  - cbn [run_until]. rewrite H. reflexivity.
Qed.


Lemma run_until_succ :
  forall fuel prog stop vm,
    run_until (S fuel) prog stop vm =
    if orb (stop (vm_pc vm)) (vm_halted vm)
    then vm else run_until fuel prog stop (exec_instr prog vm).
Proof. reflexivity. Qed.

Lemma run_until_split :
  forall f1 f2 prog stop vm,
    run_until (f1 + f2) prog stop vm =
    run_until f2 prog stop (run_until f1 prog stop vm).
Proof.
  induction f1 as [|f1 IH]; intros f2 prog stop vm.
  - reflexivity.
  - replace (S f1 + f2) with (S (f1 + f2)) by lia.
    rewrite run_until_succ.
    destruct (orb (stop (vm_pc vm)) (vm_halted vm)) eqn:E.
    + rewrite run_until_succ. rewrite E. cbn.
      rewrite (run_until_stop f2 prog stop vm E). reflexivity.
    + rewrite run_until_succ. rewrite E.
      apply IH.
Qed.

(** ** Explicit one-step reductions for the scan block *)

Lemma run_one_false :
  forall fuel prog stop vm,
    orb (stop (vm_pc vm)) (vm_halted vm) = false ->
    run_until (S fuel) prog stop vm =
    run_until fuel prog stop (exec_instr prog vm).
Proof.
  intros. rewrite run_until_succ. rewrite H. reflexivity.
Qed.

Lemma exec_instr_pc :
  forall (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error scan_block pc = Some ins ->
    vm_pc (exec_instr scan_block vm) =
    match ins with
    | iJMP p target =>
        if pred_holds p (vm_zf vm) (vm_lf vm) then target else S pc
    | iCALL target => target
    | iRET => vm_link vm
    | iHALT => pc
    | _ => S pc
    end.
Proof.
  intros vm pc ins Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins.
  destruct ins; cbn; reflexivity.
Qed.

Lemma exec_instr_CMP_zf :
  forall (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error scan_block pc = Some (iCMP a b) ->
    vm_zf (exec_instr scan_block vm) =
      Nat.eqb (vm_reg vm a) (vm_reg vm b).
Proof.
  intros vm pc a b Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn. reflexivity.
Qed.

Lemma exec_instr_CMP_lf :
  forall (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error scan_block pc = Some (iCMP a b) ->
    vm_lf (exec_instr scan_block vm) =
      Nat.ltb (vm_reg vm a) (vm_reg vm b).
Proof.
  intros vm pc a b Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn. reflexivity.
Qed.

Lemma exec_instr_not_halted :
  forall (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error scan_block pc = Some ins ->
    ins <> iHALT ->
    vm_halted (exec_instr scan_block vm) = vm_halted vm.
Proof.
  intros vm pc ins Hpc Hins Hne.
  unfold exec_instr. rewrite Hpc, Hins.
  destruct ins; try reflexivity.
  exfalso. apply Hne. reflexivity.
Qed.

(** ** Projections for the scan prefix, step by step *)

Lemma scan_pc_after_0 :
  forall vm, vm_pc vm = 0 -> vm_pc (exec_instr scan_block vm) = 1.
Proof.
  intros vm H.
  rewrite (exec_instr_pc vm 0 (iCMP 8 6) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_1 :
  forall vm, vm_pc vm = 1 ->
    vm_pc (exec_instr scan_block vm) =
      if pred_holds pGE (vm_zf vm) (vm_lf vm) then 13 else 2.
Proof.
  intros vm H.
  rewrite (exec_instr_pc vm 1 (iJMP pGE 13) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_2 :
  forall vm, vm_pc vm = 2 -> vm_pc (exec_instr scan_block vm) = 3.
Proof.
  intros vm H.
  rewrite (exec_instr_pc vm 2 (iSHL 7 8 3) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_3 :
  forall vm, vm_pc vm = 3 -> vm_pc (exec_instr scan_block vm) = 4.
Proof.
  intros vm H.
  rewrite (exec_instr_pc vm 3 (iADD 7 7 5) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_4 :
  forall vm, vm_pc vm = 4 -> vm_pc (exec_instr scan_block vm) = 5.
Proof.
  intros vm H.
  rewrite (exec_instr_pc vm 4 (iLD 9 7 0) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_reg8_after_0 :
  forall vm, vm_pc vm = 0 -> vm_reg (exec_instr scan_block vm) 8 = vm_reg vm 8.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_zf_after_0 :
  forall vm, vm_pc vm = 0 ->
    vm_zf (exec_instr scan_block vm) = Nat.eqb (vm_reg vm 8) (vm_reg vm 6).
Proof.
  intros vm H. exact (exec_instr_CMP_zf vm 0 8 6 H eq_refl).
Qed.

Lemma scan_lf_after_0 :
  forall vm, vm_pc vm = 0 ->
    vm_lf (exec_instr scan_block vm) = Nat.ltb (vm_reg vm 8) (vm_reg vm 6).
Proof.
  intros vm H. exact (exec_instr_CMP_lf vm 0 8 6 H eq_refl).
Qed.

Lemma scan_flags_after_1 :
  forall vm, vm_pc vm = 1 ->
    vm_zf (exec_instr scan_block vm) = vm_zf vm /\
    vm_lf (exec_instr scan_block vm) = vm_lf vm.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. split; reflexivity.
Qed.

Lemma scan_reg7_after_2 :
  forall vm, vm_pc vm = 2 ->
    vm_reg (exec_instr scan_block vm) 7 = Nat.shiftl (vm_reg vm 8) 3.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_zf_after_2 :
  forall vm, vm_pc vm = 2 ->
    vm_zf (exec_instr scan_block vm) = Nat.eqb (Nat.shiftl (vm_reg vm 8) 3) 0.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_lf_after_2 :
  forall vm, vm_pc vm = 2 -> vm_lf (exec_instr scan_block vm) = false.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_reg7_after_3 :
  forall vm, vm_pc vm = 3 ->
    vm_reg (exec_instr scan_block vm) 7 = vm_reg vm 7 + vm_reg vm 5.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_zf_after_3 :
  forall vm, vm_pc vm = 3 ->
    vm_zf (exec_instr scan_block vm) = Nat.eqb (vm_reg vm 7 + vm_reg vm 5) 0.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_lf_after_3 :
  forall vm, vm_pc vm = 3 -> vm_lf (exec_instr scan_block vm) = false.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_reg9_after_4 :
  forall vm, vm_pc vm = 4 ->
    vm_reg (exec_instr scan_block vm) 9 = vm_mem vm (vm_reg vm 7 + 0).
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_reg7_after_4 :
  forall vm, vm_pc vm = 4 -> vm_reg (exec_instr scan_block vm) 7 = vm_reg vm 7.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. reflexivity.
Qed.

Lemma scan_flags_after_4 :
  forall vm, vm_pc vm = 4 ->
    vm_zf (exec_instr scan_block vm) = vm_zf vm /\
    vm_lf (exec_instr scan_block vm) = vm_lf vm.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. split; reflexivity.
Qed.



(** ** A first computed prefix: five instructions, no early stop *)

Definition never_stop (_ : nat) : bool := false.

Lemma scan_prefix5_never_pc :
  forall i state sym start m,
    i < 184 ->
    vm_pc (run_until 5 scan_block never_stop
      (scan_init i state sym start m)) = 5.
Proof.
  intros i state sym start m Hlt.
  destruct (Nat.eqb i 184) eqn:E1.
  { apply Nat.eqb_eq in E1. lia. }
  destruct (Nat.ltb i 184) eqn:L1.
  2:{ apply Nat.ltb_ge in L1. lia. }
  cbn.
  rewrite E1.
  assert (Hleb : (i <=? 183) = true) by (apply Nat.leb_le; lia).
  rewrite Hleb.
  cbn. reflexivity.
Qed.

Lemma scan_prefix5_stop_pc :
  forall i state sym start m,
    i < 184 ->
    vm_pc (run_until 5 scan_block scan_stop
      (scan_init i state sym start m)) = 5.
Proof.
  intros i state sym start m Hlt.
  destruct (Nat.eqb i 184) eqn:E1.
  { apply Nat.eqb_eq in E1. lia. }
  destruct (Nat.ltb i 184) eqn:L1.
  2:{ apply Nat.ltb_ge in L1. lia. }
  cbn.
  rewrite E1.
  assert (Hleb : (i <=? 183) = true) by (apply Nat.leb_le; lia).
  rewrite Hleb.
  cbn. reflexivity.
Qed.

Lemma scan_prefix5_stop_vm :
  forall i state sym start m,
    i < 184 ->
    let vm' := run_until 5 scan_block scan_stop
      (scan_init i state sym start m) in
    vm_pc vm' = 5 /\
    vm_reg vm' 7 = start + 8 * i /\
    vm_reg vm' 9 = m (start + 8 * i) /\
    vm_reg vm' 1 = state /\
    vm_reg vm' 4 = sym /\
    vm_reg vm' 8 = i /\
    vm_mem vm' = m /\
    vm_halted vm' = false.
Proof.
  intros i state sym start m Hlt.
  destruct (Nat.eqb i 184) eqn:E1.
  { apply Nat.eqb_eq in E1. lia. }
  destruct (Nat.ltb i 184) eqn:L1.
  2:{ apply Nat.ltb_ge in L1. lia. }
  cbn.
  rewrite E1.
  assert (Hleb : (i <=? 183) = true) by (apply Nat.leb_le; lia).
  rewrite Hleb.
  cbn.
  repeat split; try reflexivity; try (apply f_equal; lia); try lia.
Qed.


Lemma scan_pc_after_5 :
  forall vm, vm_pc vm = 5 -> vm_pc (exec_instr scan_block vm) = 6.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 5 (iCMP 9 1) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_zf_after_5 :
  forall vm, vm_pc vm = 5 ->
    vm_zf (exec_instr scan_block vm) = Nat.eqb (vm_reg vm 9) (vm_reg vm 1).
Proof. intros vm H. exact (exec_instr_CMP_zf vm 5 9 1 H eq_refl). Qed.

Lemma scan_lf_after_5 :
  forall vm, vm_pc vm = 5 ->
    vm_lf (exec_instr scan_block vm) = Nat.ltb (vm_reg vm 9) (vm_reg vm 1).
Proof. intros vm H. exact (exec_instr_CMP_lf vm 5 9 1 H eq_refl). Qed.

Lemma scan_pc_after_6 :
  forall vm, vm_pc vm = 6 ->
    vm_pc (exec_instr scan_block vm) =
      if pred_holds pNE (vm_zf vm) (vm_lf vm) then 11 else 7.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 6 (iJMP pNE 11) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_7 :
  forall vm, vm_pc vm = 7 -> vm_pc (exec_instr scan_block vm) = 8.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 7 (iLD 9 7 1) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_reg9_after_7 :
  forall vm, vm_pc vm = 7 ->
    vm_reg (exec_instr scan_block vm) 9 = vm_mem vm (vm_reg vm 7 + 1).
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block].
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_8 :
  forall vm, vm_pc vm = 8 -> vm_pc (exec_instr scan_block vm) = 9.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 8 (iCMP 9 4) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_zf_after_8 :
  forall vm, vm_pc vm = 8 ->
    vm_zf (exec_instr scan_block vm) = Nat.eqb (vm_reg vm 9) (vm_reg vm 4).
Proof. intros vm H. exact (exec_instr_CMP_zf vm 8 9 4 H eq_refl). Qed.

Lemma scan_lf_after_8 :
  forall vm, vm_pc vm = 8 ->
    vm_lf (exec_instr scan_block vm) = Nat.ltb (vm_reg vm 9) (vm_reg vm 4).
Proof. intros vm H. exact (exec_instr_CMP_lf vm 8 9 4 H eq_refl). Qed.

Lemma scan_pc_after_9 :
  forall vm, vm_pc vm = 9 ->
    vm_pc (exec_instr scan_block vm) =
      if pred_holds pNE (vm_zf vm) (vm_lf vm) then 11 else 10.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 9 (iJMP pNE 11) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_10 :
  forall vm, vm_pc vm = 10 -> vm_pc (exec_instr scan_block vm) = 14.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 10 (iJMP pALWAYS 14) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_hit_suffix :
  forall (vm : VM) i state sym start row rest m,
    vm_pc vm = 5 ->
    vm_reg vm 7 = start + 8 * i ->
    vm_reg vm 9 = m (start + 8 * i) ->
    vm_reg vm 1 = state ->
    vm_reg vm 4 = sym ->
    vm_mem vm = m ->
    vm_halted vm = false ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    1 < length row ->
    nth 0 row 0 = state ->
    nth 1 row 0 = sym ->
    vm_pc (run_until 7 scan_block scan_stop vm) = 14.
Proof.
  intros vm i state sym start row rest m
    Hpc Hr7 Hr9 Hr1 Hr4 Hmem Hhalt Hmemtab Hrow0 Hrow1 Hfrom Hread.
  set (v1 := exec_instr scan_block vm).
  set (v2 := exec_instr scan_block v1).
  set (v3 := exec_instr scan_block v2).
  set (v4 := exec_instr scan_block v3).
  set (v5 := exec_instr scan_block v4).
  set (v6 := exec_instr scan_block v5).
  (* step 1 *)
  rewrite (run_one_false 6 scan_block scan_stop vm).
  2:{ unfold scan_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 6) by (unfold v1; apply scan_pc_after_5; exact Hpc).
  assert (Hzf1 : vm_zf v1 = true).
  { unfold v1. rewrite (scan_zf_after_5 vm Hpc). rewrite Hr9, Hr1.
    rewrite (table_mem_at_head0 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hfrom. rewrite Nat.eqb_refl. reflexivity. }
  assert (Hlf1 : vm_lf v1 = false).
  { unfold v1. rewrite (scan_lf_after_5 vm Hpc). rewrite Hr9, Hr1.
    rewrite (table_mem_at_head0 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hfrom. apply Nat.ltb_irrefl. }
  assert (Hh1 : vm_halted v1 = false).
  { unfold v1. rewrite (exec_instr_not_halted vm 5 (iCMP 9 1) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  assert (Hr7_1 : vm_reg v1 7 = start + 8 * i).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn. exact Hr7. }
  assert (Hr4_1 : vm_reg v1 4 = sym).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn. exact Hr4. }
  assert (Hmem1 : vm_mem v1 = m).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn. exact Hmem. }
  (* step 2 *)
  rewrite (run_one_false 5 scan_block scan_stop v1).
  2:{ unfold scan_stop. rewrite Hpc1, Hh1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 7).
  { unfold v2. rewrite (scan_pc_after_6 v1 Hpc1), Hzf1, Hlf1. cbn. reflexivity. }
  assert (Hh2 : vm_halted v2 = false).
  { unfold v2. rewrite (exec_instr_not_halted v1 6 (iJMP pNE 11) Hpc1 eq_refl
      ltac:(discriminate)). exact Hh1. }
  assert (Hr7_2 : vm_reg v2 7 = start + 8 * i).
  { unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn. exact Hr7_1. }
  assert (Hmem2 : vm_mem v2 = m).
  { unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn. exact Hmem1. }
  (* step 3 *)
  rewrite (run_one_false 4 scan_block scan_stop v2).
  2:{ unfold scan_stop. rewrite Hpc2, Hh2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 8) by (unfold v3; apply scan_pc_after_7; exact Hpc2).
  assert (Hh3 : vm_halted v3 = false).
  { unfold v3. rewrite (exec_instr_not_halted v2 7 (iLD 9 7 1) Hpc2 eq_refl
      ltac:(discriminate)). exact Hh2. }
  assert (Hr9_3 : vm_reg v3 9 = m (start + 8 * i + 1)).
  { unfold v3. rewrite (scan_reg9_after_7 v2 Hpc2), Hr7_2, Hmem2.
    apply f_equal. lia. }
  assert (Hr4_3 : vm_reg v3 4 = sym).
  { unfold v3. unfold exec_instr. rewrite Hpc2. cbn [nth_error scan_block]. cbn.
    unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    exact Hr4_1. }
  (* step 4 *)
  rewrite (run_one_false 3 scan_block scan_stop v3).
  2:{ unfold scan_stop. rewrite Hpc3, Hh3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 9) by (unfold v4; apply scan_pc_after_8; exact Hpc3).
  assert (Hzf4 : vm_zf v4 = true).
  { unfold v4. rewrite (scan_zf_after_8 v3 Hpc3). rewrite Hr9_3, Hr4_3.
    rewrite (table_mem_at_head1 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hread. rewrite Nat.eqb_refl. reflexivity. }
  assert (Hlf4 : vm_lf v4 = false).
  { unfold v4. rewrite (scan_lf_after_8 v3 Hpc3). rewrite Hr9_3, Hr4_3.
    rewrite (table_mem_at_head1 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hread. apply Nat.ltb_irrefl. }
  assert (Hh4 : vm_halted v4 = false).
  { unfold v4. rewrite (exec_instr_not_halted v3 8 (iCMP 9 4) Hpc3 eq_refl
      ltac:(discriminate)). exact Hh3. }
  (* step 5 *)
  rewrite (run_one_false 2 scan_block scan_stop v4).
  2:{ unfold scan_stop. rewrite Hpc4, Hh4. cbn. reflexivity. }
  fold v5.
  assert (Hpc5 : vm_pc v5 = 10).
  { unfold v5. rewrite (scan_pc_after_9 v4 Hpc4), Hzf4, Hlf4. cbn. reflexivity. }
  assert (Hh5 : vm_halted v5 = false).
  { unfold v5. rewrite (exec_instr_not_halted v4 9 (iJMP pNE 11) Hpc4 eq_refl
      ltac:(discriminate)). exact Hh4. }
  (* step 6 *)
  rewrite (run_one_false 1 scan_block scan_stop v5).
  2:{ unfold scan_stop. rewrite Hpc5, Hh5. cbn. reflexivity. }
  fold v6.
  assert (Hpc6 : vm_pc v6 = 14) by (unfold v6; apply scan_pc_after_10; exact Hpc5).
  assert (Hh6 : vm_halted v6 = false).
  { unfold v6. rewrite (exec_instr_not_halted v5 10 (iJMP pALWAYS 14) Hpc5 eq_refl
      ltac:(discriminate)). exact Hh5. }
  (* the scan stop fires at pc 14 *)
  cbn [run_until scan_stop orb].
  rewrite Hpc6, Hh6.
  cbn.
  exact Hpc6.
Qed.

Lemma scan_pc_after_11 :
  forall vm, vm_pc vm = 11 -> vm_pc (exec_instr scan_block vm) = 12.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 11 (iADD 8 8 13) H eq_refl).
  cbn. reflexivity.
Qed.

Lemma scan_reg8_after_11 :
  forall vm, vm_pc vm = 11 ->
    vm_reg (exec_instr scan_block vm) 8 = vm_reg vm 8 + vm_reg vm 13.
Proof.
  intros vm H. unfold exec_instr. rewrite H. cbn [nth_error scan_block].
  cbn. reflexivity.
Qed.

Lemma scan_pc_after_12 :
  forall vm, vm_pc vm = 12 -> vm_pc (exec_instr scan_block vm) = 0.
Proof.
  intros vm H. rewrite (exec_instr_pc vm 12 (iJMP pALWAYS 0) H eq_refl).
  cbn. reflexivity.
Qed.

(** ** Register/memory preservation for the miss path *)

Lemma scan_reg_preserved_5 :
  forall vm d, vm_pc vm = 5 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_reg_preserved_6 :
  forall vm d, vm_pc vm = 6 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_reg_preserved_11 :
  forall vm d, vm_pc vm = 11 -> d <> 8 ->
    vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn.
  unfold set_reg. destruct (Nat.eqb d 8) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma scan_reg_preserved_12 :
  forall vm d, vm_pc vm = 12 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_5 :
  forall vm, vm_pc vm = 5 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_6 :
  forall vm, vm_pc vm = 6 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_11 :
  forall vm, vm_pc vm = 11 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_12 :
  forall vm, vm_pc vm = 12 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_miss_from :
  forall vm i state sym start row rest m,
    vm_pc vm = 5 ->
    vm_reg vm 7 = start + 8 * i ->
    vm_reg vm 9 = m (start + 8 * i) ->
    vm_reg vm 1 = state ->
    vm_reg vm 4 = sym ->
    vm_reg vm 8 = i ->
    vm_reg vm 5 = start ->
    vm_reg vm 6 = 184 ->
    vm_reg vm 13 = 1 ->
    vm_mem vm = m ->
    vm_halted vm = false ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    nth 0 row 0 <> state ->
    scan_ready (run_until 4 scan_block scan_stop vm) (S i) state sym start m.
Proof.
  intros vm i state sym start row rest m
    Hpc Hr7 Hr9 Hr1 Hr4 Hr8 Hr5 Hr6 Hr13 Hmem Hhalt Hmemtab Hrow0 Hneq.
  destruct (Nat.eqb (nth 0 row 0) state) eqn:Efrom.
  { apply Nat.eqb_eq in Efrom. contradiction. }
  set (v1 := exec_instr scan_block vm).
  rewrite (run_one_false 3 scan_block scan_stop vm).
  2:{ unfold scan_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 6) by (unfold v1; apply scan_pc_after_5; exact Hpc).
  assert (Hzf1 : vm_zf v1 = false).
  { unfold v1. rewrite (scan_zf_after_5 vm Hpc). rewrite Hr9, Hr1.
    rewrite (table_mem_at_head0 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    exact Efrom. }
  assert (Hh1 : vm_halted v1 = false).
  { unfold v1. rewrite (exec_instr_not_halted vm 5 (iCMP 9 1) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  set (v2 := exec_instr scan_block v1).
  rewrite (run_one_false 2 scan_block scan_stop v1).
  2:{ unfold scan_stop. rewrite Hpc1, Hh1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 11).
  { unfold v2. rewrite (scan_pc_after_6 v1 Hpc1), Hzf1. cbn. reflexivity. }
  assert (Hh2 : vm_halted v2 = false).
  { unfold v2. rewrite (exec_instr_not_halted v1 6 (iJMP pNE 11) Hpc1 eq_refl
      ltac:(discriminate)). exact Hh1. }
  set (v3 := exec_instr scan_block v2).
  rewrite (run_one_false 1 scan_block scan_stop v2).
  2:{ unfold scan_stop. rewrite Hpc2, Hh2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 12) by (unfold v3; apply scan_pc_after_11; exact Hpc2).
  assert (Hh3 : vm_halted v3 = false).
  { unfold v3. rewrite (exec_instr_not_halted v2 11 (iADD 8 8 13) Hpc2 eq_refl
      ltac:(discriminate)). exact Hh2. }
  set (v4 := exec_instr scan_block v3).
  rewrite (run_one_false 0 scan_block scan_stop v3).
  2:{ unfold scan_stop. rewrite Hpc3, Hh3. cbn. reflexivity. }
  cbn [run_until].
  fold v4.
  assert (Hpc4 : vm_pc v4 = 0) by (unfold v4; apply scan_pc_after_12; exact Hpc3).
  assert (Hh4 : vm_halted v4 = false).
  { unfold v4. rewrite (exec_instr_not_halted v3 12 (iJMP pALWAYS 0) Hpc3 eq_refl
      ltac:(discriminate)). exact Hh3. }
  unfold scan_ready.
  repeat split.
  - exact Hpc4.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 1 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_11 v2 1 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 1 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 1 Hpc). exact Hr1.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 4 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_11 v2 4 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 4 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 4 Hpc). exact Hr4.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 5 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_11 v2 5 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 5 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 5 Hpc). exact Hr5.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 6 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_11 v2 6 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 6 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 6 Hpc). exact Hr6.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 8 Hpc3).
    unfold v3. rewrite (scan_reg8_after_11 v2 Hpc2).
    unfold v2. rewrite (scan_reg_preserved_6 v1 8 Hpc1).
    rewrite (scan_reg_preserved_6 v1 13 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 8 Hpc).
    rewrite (scan_reg_preserved_5 vm 13 Hpc).
    rewrite Hr8, Hr13. lia.
  - unfold v4. rewrite (scan_reg_preserved_12 v3 13 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_11 v2 13 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 13 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 13 Hpc). exact Hr13.
  - unfold v4. rewrite (scan_mem_preserved_12 v3 Hpc3).
    unfold v3. rewrite (scan_mem_preserved_11 v2 Hpc2).
    unfold v2. rewrite (scan_mem_preserved_6 v1 Hpc1).
    unfold v1. rewrite (scan_mem_preserved_5 vm Hpc). exact Hmem.
  - exact Hh4.
Qed.

Lemma scan_reg_preserved_7 :
  forall vm d, vm_pc vm = 7 -> d <> 9 ->
    vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn.
  unfold set_reg. destruct (Nat.eqb d 9) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma scan_reg_preserved_8 :
  forall vm d, vm_pc vm = 8 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_reg_preserved_9 :
  forall vm d, vm_pc vm = 9 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_7 :
  forall vm, vm_pc vm = 7 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_8 :
  forall vm, vm_pc vm = 8 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_mem_preserved_9 :
  forall vm, vm_pc vm = 9 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_miss_read :
  forall vm i state sym start row rest m,
    vm_pc vm = 5 ->
    vm_reg vm 7 = start + 8 * i ->
    vm_reg vm 9 = m (start + 8 * i) ->
    vm_reg vm 1 = state ->
    vm_reg vm 4 = sym ->
    vm_reg vm 8 = i ->
    vm_reg vm 5 = start ->
    vm_reg vm 6 = 184 ->
    vm_reg vm 13 = 1 ->
    vm_mem vm = m ->
    vm_halted vm = false ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    1 < length row ->
    nth 0 row 0 = state ->
    nth 1 row 0 <> sym ->
    scan_ready (run_until 7 scan_block scan_stop vm) (S i) state sym start m.
Proof.
  intros vm i state sym start row rest m
    Hpc Hr7 Hr9 Hr1 Hr4 Hr8 Hr5 Hr6 Hr13 Hmem Hhalt Hmemtab
    Hrow0 Hrow1 Hfrom Hread_neq.
  destruct (Nat.eqb (nth 1 row 0) sym) eqn:Eread.
  { apply Nat.eqb_eq in Eread. contradiction. }
  set (v1 := exec_instr scan_block vm).
  rewrite (run_one_false 6 scan_block scan_stop vm).
  2:{ unfold scan_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 6) by (unfold v1; apply scan_pc_after_5; exact Hpc).
  assert (Hzf1 : vm_zf v1 = true).
  { unfold v1. rewrite (scan_zf_after_5 vm Hpc). rewrite Hr9, Hr1.
    rewrite (table_mem_at_head0 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hfrom, Nat.eqb_refl. reflexivity. }
  assert (Hlf1 : vm_lf v1 = false).
  { unfold v1. rewrite (scan_lf_after_5 vm Hpc). rewrite Hr9, Hr1.
    rewrite (table_mem_at_head0 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    rewrite Hfrom. apply Nat.ltb_irrefl. }
  assert (Hh1 : vm_halted v1 = false).
  { unfold v1. rewrite (exec_instr_not_halted vm 5 (iCMP 9 1) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  set (v2 := exec_instr scan_block v1).
  rewrite (run_one_false 5 scan_block scan_stop v1).
  2:{ unfold scan_stop. rewrite Hpc1, Hh1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 7).
  { unfold v2. rewrite (scan_pc_after_6 v1 Hpc1), Hzf1, Hlf1. cbn. reflexivity. }
  assert (Hh2 : vm_halted v2 = false).
  { unfold v2. rewrite (exec_instr_not_halted v1 6 (iJMP pNE 11) Hpc1 eq_refl
      ltac:(discriminate)). exact Hh1. }
  assert (Hr7_2 : vm_reg v2 7 = start + 8 * i).
  { unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    exact Hr7. }
  assert (Hmem2 : vm_mem v2 = m).
  { unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    exact Hmem. }
  set (v3 := exec_instr scan_block v2).
  rewrite (run_one_false 4 scan_block scan_stop v2).
  2:{ unfold scan_stop. rewrite Hpc2, Hh2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 8) by (unfold v3; apply scan_pc_after_7; exact Hpc2).
  assert (Hh3 : vm_halted v3 = false).
  { unfold v3. rewrite (exec_instr_not_halted v2 7 (iLD 9 7 1) Hpc2 eq_refl
      ltac:(discriminate)). exact Hh2. }
  assert (Hr9_3 : vm_reg v3 9 = m (start + 8 * i + 1)).
  { unfold v3. rewrite (scan_reg9_after_7 v2 Hpc2), Hr7_2, Hmem2.
    apply f_equal. lia. }
  assert (Hr4_3 : vm_reg v3 4 = sym).
  { unfold v3. unfold exec_instr. rewrite Hpc2. cbn [nth_error scan_block]. cbn.
    unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    exact Hr4. }
  set (v4 := exec_instr scan_block v3).
  rewrite (run_one_false 3 scan_block scan_stop v3).
  2:{ unfold scan_stop. rewrite Hpc3, Hh3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 9) by (unfold v4; apply scan_pc_after_8; exact Hpc3).
  assert (Hzf4 : vm_zf v4 = false).
  { unfold v4. rewrite (scan_zf_after_8 v3 Hpc3). rewrite Hr9_3, Hr4_3.
    rewrite (table_mem_at_head1 (start + 8 * i) row rest m ltac:(lia) Hmemtab).
    exact Eread. }
  assert (Hh4 : vm_halted v4 = false).
  { unfold v4. rewrite (exec_instr_not_halted v3 8 (iCMP 9 4) Hpc3 eq_refl
      ltac:(discriminate)). exact Hh3. }
  set (v5 := exec_instr scan_block v4).
  rewrite (run_one_false 2 scan_block scan_stop v4).
  2:{ unfold scan_stop. rewrite Hpc4, Hh4. cbn. reflexivity. }
  fold v5.
  assert (Hpc5 : vm_pc v5 = 11).
  { unfold v5. rewrite (scan_pc_after_9 v4 Hpc4), Hzf4. cbn. reflexivity. }
  assert (Hh5 : vm_halted v5 = false).
  { unfold v5. rewrite (exec_instr_not_halted v4 9 (iJMP pNE 11) Hpc4 eq_refl
      ltac:(discriminate)). exact Hh4. }
  set (v6 := exec_instr scan_block v5).
  rewrite (run_one_false 1 scan_block scan_stop v5).
  2:{ unfold scan_stop. rewrite Hpc5, Hh5. cbn. reflexivity. }
  fold v6.
  assert (Hpc6 : vm_pc v6 = 12) by (unfold v6; apply scan_pc_after_11; exact Hpc5).
  assert (Hh6 : vm_halted v6 = false).
  { unfold v6. rewrite (exec_instr_not_halted v5 11 (iADD 8 8 13) Hpc5 eq_refl
      ltac:(discriminate)). exact Hh5. }
  set (v7 := exec_instr scan_block v6).
  rewrite (run_one_false 0 scan_block scan_stop v6).
  2:{ unfold scan_stop. rewrite Hpc6, Hh6. cbn. reflexivity. }
  cbn [run_until].
  fold v7.
  assert (Hpc7 : vm_pc v7 = 0) by (unfold v7; apply scan_pc_after_12; exact Hpc6).
  assert (Hh7 : vm_halted v7 = false).
  { unfold v7. rewrite (exec_instr_not_halted v6 12 (iJMP pALWAYS 0) Hpc6 eq_refl
      ltac:(discriminate)). exact Hh6. }
  unfold scan_ready.
  repeat split.
  - exact Hpc7.
  - (* r1 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 1 Hpc6).
    unfold v6. rewrite (scan_reg_preserved_11 v5 1 Hpc5 ltac:(lia)).
    unfold v5. rewrite (scan_reg_preserved_9 v4 1 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 1 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 1 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 1 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 1 Hpc). exact Hr1.
  - (* r4 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 4 Hpc6).
    unfold v6. rewrite (scan_reg_preserved_11 v5 4 Hpc5 ltac:(lia)).
    unfold v5. rewrite (scan_reg_preserved_9 v4 4 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 4 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 4 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 4 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 4 Hpc). exact Hr4.
  - (* r5 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 5 Hpc6).
    unfold v6. rewrite (scan_reg_preserved_11 v5 5 Hpc5 ltac:(lia)).
    unfold v5. rewrite (scan_reg_preserved_9 v4 5 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 5 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 5 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 5 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 5 Hpc). exact Hr5.
  - (* r6 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 6 Hpc6).
    unfold v6. rewrite (scan_reg_preserved_11 v5 6 Hpc5 ltac:(lia)).
    unfold v5. rewrite (scan_reg_preserved_9 v4 6 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 6 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 6 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 6 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 6 Hpc). exact Hr6.
  - (* r8 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 8 Hpc6).
    unfold v6. rewrite (scan_reg8_after_11 v5 Hpc5).
    unfold v5. rewrite (scan_reg_preserved_9 v4 8 Hpc4),
      (scan_reg_preserved_9 v4 13 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 8 Hpc3),
      (scan_reg_preserved_8 v3 13 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 8 Hpc2 ltac:(lia)),
      (scan_reg_preserved_7 v2 13 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 8 Hpc1),
      (scan_reg_preserved_6 v1 13 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 8 Hpc),
      (scan_reg_preserved_5 vm 13 Hpc).
    rewrite Hr8, Hr13. lia.
  - (* r13 *)
    unfold v7. rewrite (scan_reg_preserved_12 v6 13 Hpc6).
    unfold v6. rewrite (scan_reg_preserved_11 v5 13 Hpc5 ltac:(lia)).
    unfold v5. rewrite (scan_reg_preserved_9 v4 13 Hpc4).
    unfold v4. rewrite (scan_reg_preserved_8 v3 13 Hpc3).
    unfold v3. rewrite (scan_reg_preserved_7 v2 13 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_6 v1 13 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_5 vm 13 Hpc). exact Hr13.
  - (* mem *)
    unfold v7. rewrite (scan_mem_preserved_12 v6 Hpc6).
    unfold v6. rewrite (scan_mem_preserved_11 v5 Hpc5).
    unfold v5. rewrite (scan_mem_preserved_9 v4 Hpc4).
    unfold v4. rewrite (scan_mem_preserved_8 v3 Hpc3).
    unfold v3. rewrite (scan_mem_preserved_7 v2 Hpc2).
    unfold v2. rewrite (scan_mem_preserved_6 v1 Hpc1).
    unfold v1. rewrite (scan_mem_preserved_5 vm Hpc). exact Hmem.
  - exact Hh7.
Qed.

Lemma scan_reg_preserved_0 :
  forall vm d, vm_pc vm = 0 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_reg_preserved_1 :
  forall vm d, vm_pc vm = 1 -> vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity.
Qed.

Lemma scan_reg_preserved_2 :
  forall vm d, vm_pc vm = 2 -> d <> 7 ->
    vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn.
  unfold set_reg. destruct (Nat.eqb d 7) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma scan_reg_preserved_3 :
  forall vm d, vm_pc vm = 3 -> d <> 7 ->
    vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn.
  unfold set_reg. destruct (Nat.eqb d 7) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma scan_reg_preserved_4 :
  forall vm d, vm_pc vm = 4 -> d <> 9 ->
    vm_reg (exec_instr scan_block vm) d = vm_reg vm d.
Proof.
  intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn.
  unfold set_reg. destruct (Nat.eqb d 9) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma scan_mem_preserved_0 :
  forall vm, vm_pc vm = 0 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity. Qed.

Lemma scan_mem_preserved_1 :
  forall vm, vm_pc vm = 1 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity. Qed.

Lemma scan_mem_preserved_2 :
  forall vm, vm_pc vm = 2 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity. Qed.

Lemma scan_mem_preserved_3 :
  forall vm, vm_pc vm = 3 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity. Qed.

Lemma scan_mem_preserved_4 :
  forall vm, vm_pc vm = 4 -> vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H. cbn [nth_error scan_block]. cbn. reflexivity. Qed.

Lemma scan_prefix5_ready :
  forall (vm : VM) i state sym start m,
    i < 184 ->
    scan_ready vm i state sym start m ->
    let vm5 := run_until 5 scan_block scan_stop vm in
    vm_pc vm5 = 5 /\
    vm_reg vm5 7 = start + 8 * i /\
    vm_reg vm5 9 = m (start + 8 * i) /\
    vm_reg vm5 1 = state /\
    vm_reg vm5 4 = sym /\
    vm_reg vm5 8 = i /\
    vm_reg vm5 5 = start /\
    vm_reg vm5 6 = 184 /\
    vm_reg vm5 13 = 1 /\
    vm_mem vm5 = m /\
    vm_halted vm5 = false.
Proof.
  intros vm i state sym start m Hlt Hready.
  unfold scan_ready in Hready.
  destruct Hready as [Hpc [Hr1 [Hr4 [Hr5 [Hr6 [Hr8 [Hr13 [Hmem Hhalt]]]]]]]].
  set (v1 := exec_instr scan_block vm).
  set (v2 := exec_instr scan_block v1).
  set (v3 := exec_instr scan_block v2).
  set (v4 := exec_instr scan_block v3).
  set (v5 := exec_instr scan_block v4).
  rewrite (run_one_false 4 scan_block scan_stop vm).
  2:{ unfold scan_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 1) by (unfold v1; apply scan_pc_after_0; exact Hpc).
  assert (Hzf1 : vm_zf v1 = false).
  { unfold v1. rewrite (scan_zf_after_0 vm Hpc). rewrite Hr8, Hr6.
    apply Nat.eqb_neq. lia. }
  assert (Hlf1 : vm_lf v1 = true).
  { unfold v1. rewrite (scan_lf_after_0 vm Hpc). rewrite Hr8, Hr6.
    apply Nat.ltb_lt. lia. }
  assert (Hh1 : vm_halted v1 = false).
  { unfold v1. rewrite (exec_instr_not_halted vm 0 (iCMP 8 6) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  rewrite (run_one_false 3 scan_block scan_stop v1).
  2:{ unfold scan_stop. rewrite Hpc1, Hh1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 2).
  { unfold v2. rewrite (scan_pc_after_1 v1 Hpc1), Hzf1, Hlf1. cbn. reflexivity. }
  assert (Hh2 : vm_halted v2 = false).
  { unfold v2. rewrite (exec_instr_not_halted v1 1 (iJMP pGE 13) Hpc1 eq_refl
      ltac:(discriminate)). exact Hh1. }
  rewrite (run_one_false 2 scan_block scan_stop v2).
  2:{ unfold scan_stop. rewrite Hpc2, Hh2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 3) by (unfold v3; apply scan_pc_after_2; exact Hpc2).
  assert (Hr7_3 : vm_reg v3 7 = Nat.shiftl i 3).
  { unfold v3. rewrite (scan_reg7_after_2 v2 Hpc2).
    unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    rewrite Hr8. reflexivity. }
  assert (Hh3 : vm_halted v3 = false).
  { unfold v3. rewrite (exec_instr_not_halted v2 2 (iSHL 7 8 3) Hpc2 eq_refl
      ltac:(discriminate)). exact Hh2. }
  rewrite (run_one_false 1 scan_block scan_stop v3).
  2:{ unfold scan_stop. rewrite Hpc3, Hh3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 4) by (unfold v4; apply scan_pc_after_3; exact Hpc3).
  assert (Hr7_4 : vm_reg v4 7 = Nat.shiftl i 3 + start).
  { unfold v4. rewrite (scan_reg7_after_3 v3 Hpc3), Hr7_3.
    unfold v3. unfold exec_instr. rewrite Hpc2. cbn [nth_error scan_block]. cbn.
    unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    rewrite Hr5. reflexivity. }
  assert (Hh4 : vm_halted v4 = false).
  { unfold v4. rewrite (exec_instr_not_halted v3 3 (iADD 7 7 5) Hpc3 eq_refl
      ltac:(discriminate)). exact Hh3. }
  rewrite (run_one_false 0 scan_block scan_stop v4).
  2:{ unfold scan_stop. rewrite Hpc4, Hh4. cbn. reflexivity. }
  cbn [run_until].
  fold v5.
  assert (Hpc5 : vm_pc v5 = 5) by (unfold v5; apply scan_pc_after_4; exact Hpc4).
  assert (Hh5 : vm_halted v5 = false).
  { unfold v5. rewrite (exec_instr_not_halted v4 4 (iLD 9 7 0) Hpc4 eq_refl
      ltac:(discriminate)). exact Hh4. }
  assert (Hr9_5 : vm_reg v5 9 = m (start + 8 * i)).
  { unfold v5. rewrite (scan_reg9_after_4 v4 Hpc4), Hr7_4.
    unfold v4. unfold exec_instr. rewrite Hpc3. cbn [nth_error scan_block]. cbn.
    unfold v3. unfold exec_instr. rewrite Hpc2. cbn [nth_error scan_block]. cbn.
    unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error scan_block]. cbn.
    unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error scan_block]. cbn.
    rewrite Hmem. apply f_equal. cbn. lia. }
  repeat split.
  - exact Hpc5.
  - (* r7 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 7 Hpc4 ltac:(lia)).
    rewrite Hr7_4. cbn. lia.
  - exact Hr9_5.
  - (* r1 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 1 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 1 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 1 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 1 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 1 Hpc). exact Hr1.
  - (* r4 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 4 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 4 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 4 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 4 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 4 Hpc). exact Hr4.
  - (* r8 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 8 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 8 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 8 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 8 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 8 Hpc). exact Hr8.
  - (* r5 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 5 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 5 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 5 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 5 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 5 Hpc). exact Hr5.
  - (* r6 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 6 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 6 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 6 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 6 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 6 Hpc). exact Hr6.
  - (* r13 *)
    unfold v5. rewrite (scan_reg_preserved_4 v4 13 Hpc4 ltac:(lia)).
    unfold v4. rewrite (scan_reg_preserved_3 v3 13 Hpc3 ltac:(lia)).
    unfold v3. rewrite (scan_reg_preserved_2 v2 13 Hpc2 ltac:(lia)).
    unfold v2. rewrite (scan_reg_preserved_1 v1 13 Hpc1).
    unfold v1. rewrite (scan_reg_preserved_0 vm 13 Hpc). exact Hr13.
  - (* mem *)
    unfold v5. rewrite (scan_mem_preserved_4 v4 Hpc4).
    unfold v4. rewrite (scan_mem_preserved_3 v3 Hpc3).
    unfold v3. rewrite (scan_mem_preserved_2 v2 Hpc2).
    unfold v2. rewrite (scan_mem_preserved_1 v1 Hpc1).
    unfold v1. rewrite (scan_mem_preserved_0 vm Hpc). exact Hmem.
  - exact Hh5.
Qed.

Lemma scan_iter_hit :
  forall (vm : VM) i state sym start row rest m,
    i < 184 ->
    scan_ready vm i state sym start m ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    1 < length row ->
    nth 0 row 0 = state ->
    nth 1 row 0 = sym ->
    vm_pc (run_until 12 scan_block scan_stop vm) = 14.
Proof.
  intros vm i state sym start row rest m Hlt Hready Hmemtab
    Hrow0 Hrow1 Hfrom Hread.
  replace 12 with (5 + 7) by lia.
  rewrite (run_until_split 5 7 scan_block scan_stop vm).
  set (vm5 := run_until 5 scan_block scan_stop vm).
  pose proof (scan_prefix5_ready vm i state sym start m Hlt Hready) as H5.
  cbn zeta in H5.
  fold vm5 in H5.
  destruct H5 as [Hpc5 [Hr7 [Hr9 [Hr1 [Hr4 [Hr8 [Hr5 [Hr6 [Hr13 [Hmem Hhalt]]]]]]]]]].
  exact (scan_hit_suffix vm5 i state sym start row rest m
    Hpc5 Hr7 Hr9 Hr1 Hr4 Hmem Hhalt Hmemtab Hrow0 Hrow1 Hfrom Hread).
Qed.

Lemma scan_iter_miss_from :
  forall (vm : VM) i state sym start row rest m,
    i < 184 ->
    scan_ready vm i state sym start m ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    nth 0 row 0 <> state ->
    scan_ready (run_until 9 scan_block scan_stop vm) (S i) state sym start m.
Proof.
  intros vm i state sym start row rest m Hlt Hready Hmemtab Hrow0 Hneq.
  replace 9 with (5 + 4) by lia.
  rewrite (run_until_split 5 4 scan_block scan_stop vm).
  set (vm5 := run_until 5 scan_block scan_stop vm).
  pose proof (scan_prefix5_ready vm i state sym start m Hlt Hready) as H5.
  cbn zeta in H5.
  fold vm5 in H5.
  destruct H5 as [Hpc5 [Hr7 [Hr9 [Hr1 [Hr4 [Hr8 [Hr5 [Hr6 [Hr13 [Hmem Hhalt]]]]]]]]]].
  exact (scan_miss_from vm5 i state sym start row rest m
    Hpc5 Hr7 Hr9 Hr1 Hr4 Hr8 Hr5 Hr6 Hr13 Hmem Hhalt Hmemtab Hrow0 Hneq).
Qed.

Lemma scan_iter_miss_read :
  forall (vm : VM) i state sym start row rest m,
    i < 184 ->
    scan_ready vm i state sym start m ->
    table_mem_at (start + 8 * i) (row :: rest) m ->
    0 < length row ->
    1 < length row ->
    nth 0 row 0 = state ->
    nth 1 row 0 <> sym ->
    scan_ready (run_until 12 scan_block scan_stop vm) (S i) state sym start m.
Proof.
  intros vm i state sym start row rest m Hlt Hready Hmemtab
    Hrow0 Hrow1 Hfrom Hread_neq.
  replace 12 with (5 + 7) by lia.
  rewrite (run_until_split 5 7 scan_block scan_stop vm).
  set (vm5 := run_until 5 scan_block scan_stop vm).
  pose proof (scan_prefix5_ready vm i state sym start m Hlt Hready) as H5.
  cbn zeta in H5.
  fold vm5 in H5.
  destruct H5 as [Hpc5 [Hr7 [Hr9 [Hr1 [Hr4 [Hr8 [Hr5 [Hr6 [Hr13 [Hmem Hhalt]]]]]]]]]].
  exact (scan_miss_read vm5 i state sym start row rest m
    Hpc5 Hr7 Hr9 Hr1 Hr4 Hr8 Hr5 Hr6 Hr13 Hmem Hhalt Hmemtab
    Hrow0 Hrow1 Hfrom Hread_neq).
Qed.
