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

