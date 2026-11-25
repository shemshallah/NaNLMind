(** * Discharging [step_ok] from explicit layout hypotheses

    [MinskyNaN16Run.v] reduces the run-level refinement to a single
    native-step obligation

      [step_ok vm table table_base tbase]
        = [entry_ok (step_entry vm table table_base) ...]
          /\ [nstate_rel (vm_to_nstate (step_entry ...)) (nstep ...)].

    This file discharges that obligation without axioms.

    Structure of the proof:

    - [step_entry_spec] (imported from [MinskyNaN16StepEntrySpec.v])
      supplies the [nstate_rel] half; it only needs the per-row layout,
      which we derive from global table/tape disjointness.
    - [step_entry_entry_ok] proves the [entry_ok] half.  Each of the six
      fields of [entry_ok] is a projection of the native execution
      specification ([prelude_halted], [prelude_ready],
      [native_step_refines]) plus two memory frames:
        * the tape-base cell 99 is not overwritten by the action
          ([action_run_frame] plus [tape_base_addr <> tape cell]);
        * the table cells are not overwritten by the action
          ([table_mem_at_action_run] plus table/tape disjointness).
    - [native_step_reg13] is the only register frame not exported by the
      native step specification: register 13 is read but never written
      by the scan, action and no-transition blocks.

    All frame facts are proved here, so the parallel modules
    [MinskyNaN16PreserveTable] / [MinskyNaN16PreserveHead] are not
    required.  If those modules land with the same facts, the local
    lemmas [table_mem_at_action_run] and [native_step_reg13] can be
    replaced by them without changing the final statement.

    The final interface [step_ok_of_layout] has no axioms and no
    [Admitted]; the remaining assumptions are exactly the explicit
    layout/disjointness hypotheses listed in its statement. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16Run MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16PreludeReady MinskyNaN16Step
  MinskyNaN16StepNone MinskyNaN16StepSpec MinskyNaN16StepEntrySpec
  MinskyNaN16ScanPhase MinskyNaN16ActionRun.

(** Keep the two large phase functions opaque: all reasoning goes through
    their exported specifications. *)
Opaque native_step nstep.

(** ** Auxiliary facts about the first-match scan *)

Lemma scan_index_from_lt :
  forall i state sym table j row,
    scan_index_from i state sym table = Some (j, row) ->
    i <= j /\ j < i + length table.
Proof.
  intros i state sym table.
  revert i state sym.
  induction table as [|r rest IH]; intros i state sym j row Hidx.
  - cbn [scan_index_from] in Hidx. discriminate.
  - cbn [scan_index_from] in Hidx.
    destruct (andb (Nat.eqb (nth 0 r 0) state)
      (Nat.eqb (nth 1 r 0) sym)) eqn:E.
    + injection Hidx as Hj Hrow. subst j row.
      split; [lia|cbn [length]; lia].
    + apply IH in Hidx. destruct Hidx as [Hle Hlt].
      split; [lia|cbn [length]; lia].
Qed.

Lemma nth_length8 :
  forall (table : list (list nat)) i,
    Forall (fun r => length r = 8) table ->
    i < length table ->
    length (nth i table []) = 8.
Proof.
  intros table i Hf Hi.
  exact (@proj1 _ _
    (@Forall_nth (list nat) (fun r => length r = 8) table) Hf i [] Hi).
Qed.

Lemma Forall_nth_error :
  forall (A : Type) (P : A -> Prop) (l : list A) (n : nat) (x : A),
    Forall P l -> nth_error l n = Some x -> P x.
Proof.
  intros A P l n x Hf Hn.
  apply nth_error_In in Hn.
  exact (@proj1 _ _ (@Forall_forall A P l) Hf x Hn).
Qed.

(** ** Table frame lemmas *)

Lemma table_mem_at_set_mem :
  forall (start : nat) (table : list (list nat)) (m : Mem) (a v : nat),
    table_mem_at start table m ->
    (forall i f, i < length table -> f < length (nth i table []) ->
      start + 8 * i + f <> a) ->
    table_mem_at start table (set_mem m a v).
Proof.
  intros start table m a v Htab Hdis i f Hi Hf.
  unfold table_mem_at in Htab.
  rewrite (set_mem_neq m a v (start + 8 * i + f))
    by (apply Hdis; assumption).
  exact (Htab i f Hi Hf).
Qed.

(** The action phase only writes the tape cell, the head cell, the state
    cell and (optionally) the halt cell.  If none of those is a table
    cell, the table invariant survives. *)

Lemma table_mem_at_action_run :
  forall (start : nat) (table : list (list nat))
         (row_addr tape_addr head : nat) (m : Mem) (row : list nat),
    table_mem_at start table m ->
    (forall i f, i < length table -> f < length (nth i table []) ->
      start + 8 * i + f <> tape_addr) ->
    (forall i f, i < length table -> f < length (nth i table []) ->
      start + 8 * i + f <> action_head_addr) ->
    (forall i f, i < length table -> f < length (nth i table []) ->
      start + 8 * i + f <> action_state_addr) ->
    (forall i f, i < length table -> f < length (nth i table []) ->
      start + 8 * i + f <> action_halt_addr) ->
    table_mem_at start table
      (snd (action_run row_addr tape_addr head m row)).
Proof.
  intros start table row_addr tape_addr head m row
    Htab Htape Hhead Hstate Hhalt.
  unfold action_run. cbn zeta.
  destruct (Nat.eqb (nth 5 row 1) 0); cbn.
  - apply table_mem_at_set_mem.
    + apply table_mem_at_set_mem.
      * apply table_mem_at_set_mem.
        -- exact Htab.
        -- exact Htape.
      * exact Hhead.
    + exact Hstate.
  - apply table_mem_at_set_mem.
    + apply table_mem_at_set_mem.
      * apply table_mem_at_set_mem.
        -- apply table_mem_at_set_mem.
           ++ exact Htab.
           ++ exact Htape.
        -- exact Hhead.
      * exact Hstate.
    + exact Hhalt.
Qed.

(** The head cell of [action_run] is the new head, regardless of whether
    the tape cell happens to coincide with one of the processor cells:
    the head cell is written after the tape cell. *)

Lemma action_run_head_cell_general :
  forall (row_addr tape_addr head : nat) (m : Mem) (row : list nat),
    snd (action_run row_addr tape_addr head m row) action_head_addr =
      action_new_head head (nth 3 row 1).
Proof.
  intros row_addr tape_addr head m row.
  unfold action_run. cbn zeta.
  destruct (Nat.eqb (nth 5 row 1) 0); cbn; reflexivity.
Qed.

(** Keep the action result opaque now that its two frame lemmas are proved,
    so that [cbn] on the step specification never unfolds it. *)
Opaque action_run.

(** ** Register frames for the native blocks *)

Definition ins_writes (ins : Instr) (k : nat) : Prop :=
  match ins with
  | iSHL d _ _ | iADD d _ _ | iSUB d _ _ | iLD d _ _ | iMOVI d _ =>
      d = k
  | _ => False
  end.

Lemma set_reg_frame :
  forall (r : Reg) (d v k : nat),
    k <> d ->
    set_reg r d v k = r k.
Proof.
  intros r d v k Hne. unfold set_reg.
  destruct (Nat.eqb k d) eqn:E.
  - exfalso. apply Hne. apply Nat.eqb_eq in E. exact E.
  - reflexivity.
Qed.

Lemma exec_instr_reg_frame :
  forall (prog : list Instr) (vm : VM) (k : nat),
    (forall pc ins, nth_error prog pc = Some ins -> ~ ins_writes ins k) ->
    vm_reg (exec_instr prog vm) k = vm_reg vm k.
Proof.
  intros prog vm k H.
  unfold exec_instr.
  destruct (nth_error prog (vm_pc vm)) as [ins|] eqn:E.
  - specialize (H (vm_pc vm) ins E).
    destruct ins; cbn [ins_writes] in H; cbn; try reflexivity;
      match goal with
      | |- set_reg _ ?d _ k = _ =>
          apply set_reg_frame; intro Heq; apply H; symmetry; exact Heq
      end.
  - reflexivity.
Qed.

Lemma run_until_reg_frame :
  forall (fuel : nat) (prog : list Instr) (stop : nat -> bool)
         (vm : VM) (k : nat),
    (forall pc ins, nth_error prog pc = Some ins -> ~ ins_writes ins k) ->
    vm_reg (run_until fuel prog stop vm) k = vm_reg vm k.
Proof.
  intros fuel. induction fuel as [|fuel IH];
    intros prog stop vm k H.
  - reflexivity.
  - cbn [run_until].
    destruct (orb (stop (vm_pc vm)) (vm_halted vm)) eqn:E.
    + reflexivity.
    + rewrite (IH prog stop (exec_instr prog vm) k H).
      apply exec_instr_reg_frame. exact H.
Qed.

Lemma scan_block_no_reg13 :
  forall pc ins, nth_error scan_block pc = Some ins -> ~ ins_writes ins 13.
Proof.
  intros pc ins Hn.
  assert (Hf : Forall (fun ins => ~ ins_writes ins 13) scan_block).
  { repeat constructor; cbn [ins_writes]; intro H;
      try discriminate; contradiction. }
  exact (Forall_nth_error _ _ _ _ _ Hf Hn).
Qed.

Lemma action_block_no_reg13 :
  forall pc ins, nth_error action_block pc = Some ins -> ~ ins_writes ins 13.
Proof.
  intros pc ins Hn.
  assert (Hf : Forall (fun ins => ~ ins_writes ins 13) action_block).
  { repeat constructor; cbn [ins_writes]; intro H;
      try discriminate; contradiction. }
  exact (Forall_nth_error _ _ _ _ _ Hf Hn).
Qed.

Lemma no_trans_block_no_reg13 :
  forall pc ins,
    nth_error no_trans_block pc = Some ins -> ~ ins_writes ins 13.
Proof.
  intros pc ins Hn.
  assert (Hf : Forall (fun ins => ~ ins_writes ins 13) no_trans_block).
  { repeat constructor; cbn [ins_writes]; intro H;
      try discriminate; contradiction. }
  exact (Forall_nth_error _ _ _ _ _ Hf Hn).
Qed.

(** The native step preserves register 13 (it is a read-only predicate
    register for the scan and the action). *)

Lemma native_step_reg13 :
  forall (vm : VM) (table : list (list nat)) (table_base tape_base : nat),
    vm_reg vm 13 = 1 ->
    vm_reg (native_step vm table table_base tape_base) 13 = 1.
Proof.
  intros vm table table_base tape_base H13.
  destruct (scan_index_from 0 (vm_reg vm 1)
    (vm_mem vm (tape_base + vm_reg vm 2)) table) as [[j row]|] eqn:Eidx.
  - rewrite (native_step_hit vm table table_base tape_base j row Eidx).
    set (vs := run_until (step_scan_fuel table) scan_block scan_stop vm).
    assert (H13s : vm_reg vs 13 = 1).
    { unfold vs. rewrite (run_until_reg_frame (step_scan_fuel table)
        scan_block scan_stop vm 13 scan_block_no_reg13). exact H13. }
    rewrite (run_until_reg_frame (step_hit_fuel row) action_block action_stop
      (action_init vs) 13 action_block_no_reg13).
    cbn [action_init]. exact H13s.
  - rewrite (native_step_none vm table table_base tape_base Eidx).
    set (vs := run_until (step_scan_fuel table) scan_block scan_stop vm).
    assert (H13s : vm_reg vs 13 = 1).
    { unfold vs. rewrite (run_until_reg_frame (step_scan_fuel table)
        scan_block scan_stop vm 13 scan_block_no_reg13). exact H13. }
    rewrite (run_until_reg_frame 2 no_trans_block no_trans_stop
      (no_trans_init vs) 13 no_trans_block_no_reg13).
    cbn [no_trans_init]. exact H13s.
Qed.

(** ** From global disjointness to the per-row layout of [step_entry_spec] *)

Lemma row_layout_of_table_disjoint :
  forall (table : list (list nat)) (table_base tbase head j : nat),
    j < length table ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> tbase + head) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_head_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_state_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_halt_addr) ->
    (forall f, f < 8 -> table_base + 8 * j + f <> tbase + head) /\
    action_head_addr <> table_base + 8 * j + 4 /\
    action_state_addr <> table_base + 8 * j + 5 /\
    action_head_addr <> table_base + 8 * j + 5.
Proof.
  intros table table_base tbase head j Hj
    Hdis_tape Hdis_head Hdis_state Hdis_halt.
  split.
  - intros f Hf. apply (Hdis_tape j f Hj Hf).
  - split.
    + intro E. apply (Hdis_head j 4 Hj ltac:(lia)). symmetry. exact E.
    + split.
      * intro E. apply (Hdis_state j 5 Hj ltac:(lia)). symmetry. exact E.
      * intro E. apply (Hdis_head j 5 Hj ltac:(lia)). symmetry. exact E.
Qed.

(** ** The [entry_ok] half of [step_ok] *)

Lemma step_entry_entry_ok :
  forall (vm : VM) (table : list (list nat)) (table_base tbase : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> tbase + vm_reg vm 2) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_head_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_state_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_halt_addr) ->
    tape_base_addr <> tbase + vm_reg vm 2 ->
    entry_ok (step_entry vm table table_base) table table_base tbase.
Proof.
  intros vm table table_base tbase Hentry Hlen Hshort Hlen8
    Hdis_tape Hdis_head Hdis_state Hdis_halt Htb.
  destruct Hentry as [Hr0 [Hr2loc [Hr13 [Hhalt [Hmemtb Hmemtab]]]]].
  assert (Hmemr : vm_mem (restart vm) = vm_mem vm)
    by (unfold restart; reflexivity).
  assert (Hr0r : vm_reg (restart vm) 0 = 0)
    by (unfold restart; exact Hr0).
  assert (Hr2r : vm_reg (restart vm) 2 = vm_reg vm 2)
    by (unfold restart; reflexivity).
  assert (Hr13r : vm_reg (restart vm) 13 = 1)
    by (unfold restart; exact Hr13).
  assert (Hhaltr : vm_halted (restart vm) = false)
    by (unfold restart; exact Hhalt).
  unfold step_entry.
  destruct (Nat.eqb (vm_mem vm action_halt_addr) 0) eqn:Ehalt.
  - (* ---- active branch: run the prelude, then one native step ---- *)
    apply Nat.eqb_eq in Ehalt.
    set (vp := run_until 11 (prelude_block table_base) (fun _ => false)
                (restart vm)).
    pose proof (prelude_ready table_base (restart vm)
      ltac:(unfold restart; reflexivity) Hr0r Hr13r Hhaltr
      ltac:(unfold restart; exact Ehalt)) as Hpre.
    cbn zeta in Hpre. fold vp in Hpre.
    destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr3p [Hr4p [Hr5p [Hr6p
      [Hr8p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]]]]]]].
    rewrite Hmemr in Hr1p, Hr2p, Hr3p, Hr4p, Hmemp.
    set (vscan := restart vp).
    assert (Hr2s : vm_reg vscan 2 = vm_reg vm 2).
    { unfold vscan, restart. change (vm_reg vp 2 = vm_reg vm 2).
      rewrite Hr2p. symmetry. exact Hr2loc. }
    assert (Hr3s : vm_reg vscan 3 =
        vm_mem vm tape_base_addr + vm_reg vscan 2).
    { unfold vscan, restart.
      change (vm_reg vp 3 = vm_mem vm tape_base_addr + vm_reg vp 2).
      rewrite Hr3p, Hr2p. reflexivity. }
    assert (Hr0s : vm_reg vscan 0 = 0).
    { unfold vscan, restart. change (vm_reg vp 0 = 0). exact Hr0p. }
    assert (Hr13s : vm_reg vscan 13 = 1).
    { unfold vscan, restart. change (vm_reg vp 13 = 1). exact Hr13p. }
    assert (Hhalts : vm_halted vscan = false).
    { unfold vscan, restart. change (vm_halted vp = false). exact Hhaltp. }
    assert (Hmems : vm_mem vscan = vm_mem vm).
    { unfold vscan, restart. change (vm_mem vp = vm_mem vm). exact Hmemp. }
    assert (Hready : scan_ready vscan 0 (vm_mem vscan action_state_addr)
        (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2))
        table_base (vm_mem vscan)).
    { unfold scan_ready. split; [reflexivity|].
      split.
      { unfold vscan, restart.
        change (vm_reg vp 1 = vm_mem vp action_state_addr).
        rewrite Hr1p, Hmemp. reflexivity. }
      split.
      { unfold vscan, restart.
        change (vm_reg vp 4 =
          vm_mem vp (vm_mem vm tape_base_addr + vm_reg vp 2)).
        rewrite Hr4p, Hmemp, Hr3p, Hr2p. reflexivity. }
      split.
      { unfold vscan, restart. change (vm_reg vp 5 = table_base).
        exact Hr5p. }
      split.
      { unfold vscan, restart. change (vm_reg vp 6 = 184). exact Hr6p. }
      split.
      { unfold vscan, restart. change (vm_reg vp 8 = 0). exact Hr8p. }
      split.
      { unfold vscan, restart. change (vm_reg vp 13 = 1). exact Hr13p. }
      split; [reflexivity|].
      { unfold vscan, restart. change (vm_halted vp = false). exact Hhaltp. } }
    assert (Hidx : scan_index_from 0 (vm_mem vscan action_state_addr)
        (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table =
        scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table).
    { unfold vscan, restart.
      change (scan_index_from 0 (vm_mem vp action_state_addr)
        (vm_mem vp (vm_mem vm tape_base_addr + vm_reg vp 2)) table =
        scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table).
      rewrite Hmemp, Hr2p, Hr2loc. reflexivity. }
    assert (Hlayout_v : forall j0 row0,
      scan_index_from 0 (vm_mem vscan action_state_addr)
        (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table =
        Some (j0, row0) ->
      (forall f, f < 8 -> table_base + 8 * j0 + f <>
        vm_mem vm tape_base_addr + vm_reg vscan 2) /\
      action_head_addr <> table_base + 8 * j0 + 4 /\
      action_state_addr <> table_base + 8 * j0 + 5 /\
      action_head_addr <> table_base + 8 * j0 + 5).
    { intros j0 row0 Hsome.
      assert (Hsome' : scan_index_from 0 (vm_mem vm action_state_addr)
          (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table =
          Some (j0, row0)) by (rewrite <- Hidx; exact Hsome).
      assert (Hj : j0 < length table).
      { apply scan_index_from_lt in Hsome'. destruct Hsome' as [_ Hlt]. lia. }
      destruct (row_layout_of_table_disjoint table table_base tbase
        (vm_reg vm 2) j0 Hj Hdis_tape Hdis_head Hdis_state Hdis_halt)
        as [Hl1 [Hl2 [Hl3 Hl4]]].
      split.
      { intros f Hf. rewrite Hmemtb, Hr2s. apply Hl1; exact Hf. }
      split; [exact Hl2|split; [exact Hl3|exact Hl4]]. }
    pose proof (native_step_refines vscan (vm_mem vscan action_state_addr)
      (vm_reg vscan 2) table_base (vm_mem vm tape_base_addr) table
      (vm_mem vscan) Hlen Hshort Hlen8
      ltac:(rewrite Hmems; exact Hmemtab) Hready eq_refl Hr3s Hr0s
      ltac:(rewrite Hmems; exact Ehalt) Hlayout_v) as Hspec.
    destruct (scan_index_from 0 (vm_mem vscan action_state_addr)
      (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table)
      as [[j row]|] eqn:Eidx.
    + (* hit: the action block fires *)
      assert (Hlenrow : length row = 8).
      { apply (scan_index_from_length 0 (vm_mem vscan action_state_addr)
          (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table
          j row Eidx Hlen8). }
      assert (Hnth3 : nth 3 row 1 = nth 3 row 0).
      { apply nth_indep. rewrite Hlenrow. lia. }
      destruct Hspec as [Hpc' [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
      split; [exact Hr0'|].
      split.
      { rewrite Hr2'.
        assert (Hheadmem : vm_mem (native_step vscan table table_base
            (vm_mem vm tape_base_addr)) action_head_addr =
            action_new_head (vm_reg vscan 2) (nth 3 row 0)).
        { rewrite (Hmem' action_head_addr).
          rewrite (action_run_head_cell_general (table_base + 8 * j)
            (vm_mem vm tape_base_addr + vm_reg vscan 2)
            (vm_reg vscan 2) (vm_mem vscan) row).
          rewrite Hnth3. reflexivity. }
        rewrite Hheadmem. reflexivity. }
      split.
      { apply native_step_reg13. exact Hr13s. }
      split.
      { exact Hhalt'. }
      split.
      { assert (Htbcell : snd (action_run (table_base + 8 * j)
            (vm_mem vm tape_base_addr + vm_reg vscan 2)
            (vm_reg vscan 2) (vm_mem vscan) row) tape_base_addr =
            vm_mem vscan tape_base_addr).
        { apply action_run_frame.
          - rewrite Hmemtb, Hr2s. exact Htb.
          - unfold tape_base_addr, action_head_addr. lia.
          - unfold tape_base_addr, action_state_addr. lia.
          - unfold tape_base_addr, action_halt_addr. lia. }
        rewrite (Hmem' tape_base_addr), Htbcell, Hmems, Hmemtb.
        reflexivity. }
      { assert (Htab' : table_mem_at table_base table
          (snd (action_run (table_base + 8 * j)
            (vm_mem vm tape_base_addr + vm_reg vscan 2)
            (vm_reg vscan 2) (vm_mem vscan) row))).
        { apply table_mem_at_action_run.
          - unfold table_mem_at. rewrite Hmems. exact Hmemtab.
          - intros i f Hi Hf. rewrite (nth_length8 table i Hlen8 Hi) in Hf.
            rewrite Hmemtb, Hr2s. apply Hdis_tape; assumption.
          - intros i f Hi Hf. rewrite (nth_length8 table i Hlen8 Hi) in Hf.
            apply Hdis_head; assumption.
          - intros i f Hi Hf. rewrite (nth_length8 table i Hlen8 Hi) in Hf.
            apply Hdis_state; assumption.
          - intros i f Hi Hf. rewrite (nth_length8 table i Hlen8 Hi) in Hf.
            apply Hdis_halt; assumption. }
        unfold table_mem_at in Htab' |- *.
        intros i f Hi Hf.
        rewrite (Hmem' (table_base + 8 * i + f)).
        exact (Htab' i f Hi Hf). }
    + (* no transition: the halt cell is set *)
      destruct Hspec as [Hpc' [Hmem' [Hr2' [Hr0' Hhalt']]]].
      split; [exact Hr0'|].
      split.
      { rewrite Hr2', Hmem'.
        rewrite (set_mem_neq (vm_mem vscan) action_halt_addr 1
          action_head_addr) by (unfold action_head_addr, action_halt_addr; lia).
        rewrite Hr2s, Hmems. exact Hr2loc. }
      split.
      { apply native_step_reg13. exact Hr13s. }
      split.
      { exact Hhalt'. }
      split.
      { rewrite Hmem'.
        rewrite (set_mem_neq (vm_mem vscan) action_halt_addr 1
          tape_base_addr) by (unfold tape_base_addr, action_halt_addr; lia).
        rewrite Hmems, Hmemtb. reflexivity. }
      { rewrite Hmem'.
        apply table_mem_at_set_mem.
        - unfold table_mem_at. rewrite Hmems. exact Hmemtab.
        - intros i f Hi Hf. rewrite (nth_length8 table i Hlen8 Hi) in Hf.
          apply Hdis_halt; assumption. }
  - (* ---- halted branch: the prelude only returns to pc 11 ---- *)
    assert (Hne : vm_mem vm action_halt_addr <> 0).
    { intro E. rewrite E in Ehalt. rewrite Nat.eqb_refl in Ehalt.
      discriminate. }
    set (vp := run_until 3 (prelude_block table_base) (fun _ => false)
                (restart vm)).
    pose proof (prelude_halted table_base (restart vm)
      ltac:(unfold restart; reflexivity) Hr0r Hr13r Hhaltr Hne) as Hpre.
    cbn zeta in Hpre. fold vp in Hpre.
    destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]].
    rewrite Hmemr in Hmemp.
    split; [exact Hr0p|].
    split.
    { rewrite Hr2p, Hr2r, Hmemp. exact Hr2loc. }
    split; [exact Hr13p|].
    split; [exact Hhaltp|].
    split.
    { rewrite Hmemp. exact Hmemtb. }
    { rewrite Hmemp. exact Hmemtab. }
Qed.

(** ** Main theorem: [step_ok] from explicit layout hypotheses *)

Theorem step_ok_of_layout :
  forall (vm : VM) (table : list (list nat)) (table_base tbase : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    (* the tape cell [tbase + head] is not a table cell *)
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> tbase + vm_reg vm 2) ->
    (* no table cell is the head, state or halt cell *)
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_head_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_state_addr) ->
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> action_halt_addr) ->
    (* the tape-base cell 99 is not the current tape cell *)
    tape_base_addr <> tbase + vm_reg vm 2 ->
    step_ok vm table table_base tbase.
Proof.
  intros vm table table_base tbase Hentry Hlen Hshort Hlen8
    Hdis_tape Hdis_head Hdis_state Hdis_halt Htb.
  pose proof Hentry as Hentry0.
  destruct Hentry0 as [Hr0 [Hr2loc [Hr13 [Hhalt [Hmemtb Hmemtab]]]]].
  split.
  - apply step_entry_entry_ok; assumption.
  - rewrite <- Hmemtb.
    apply (step_entry_spec vm table_base table Hr0 Hr2loc Hr13 Hhalt
      Hlen Hshort Hlen8 Hmemtab).
    intros j row Hsome.
    assert (Hj : j < length table).
    { apply scan_index_from_lt in Hsome. destruct Hsome as [_ Hlt]. lia. }
    destruct (row_layout_of_table_disjoint table table_base tbase
      (vm_reg vm 2) j Hj Hdis_tape Hdis_head Hdis_state Hdis_halt)
      as [Hl1 [Hl2 [Hl3 Hl4]]].
    split.
    { intros f Hf. rewrite Hmemtb. apply Hl1; exact Hf. }
    split; [exact Hl2|split; [exact Hl3|exact Hl4]].
Qed.

(** No axioms are used. *)
Print Assumptions step_ok_of_layout.
