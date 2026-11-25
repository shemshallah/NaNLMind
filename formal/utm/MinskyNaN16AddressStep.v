(** * Source-semantics bridge for the NaN16 VM layer

    This module relates the address-based source semantics of
    [MinskyAddressRefinement] to the NaN16 runtime state [NState] exposed by
    [MinskyNaN16StepSpec].  The runtime state stores the tape in a flat,
    nonnegative [Mem], so a signed source coordinate [z] is represented at
    address [win_addr base K z = base + (z + K)].  The left window shift [K]
    is the same parameter used by [MinskyNaN16Window.win_mem].

    The representation below records exactly what one runtime step needs:

      - state, head offset and halt flag of the source configuration;
      - the source tape on the window [z + K >= 0];
      - the flat halt cell, which the action block uses to decide whether to
        set the halt flag;
      - the encoded 184-row table in memory, so that the invariant can be
        re-established after the step.

    Under the layout hypotheses

      [action_halt_addr < table_base]          (control cells below the table)
      [table_base + 8 * length nan16_rows <= base]  (table below the window)

    one [nstep] over [nan16_rows] implements one [address_step_scanned].
    The only additional source-side side condition is one cell of left slack,
    [0 < a_head c + K], needed because a left move may bring the represented
    head to offset [0] but never below it. *)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable MinskyAddressRefinement
  MinskyNaN16VM MinskyNaN16Action MinskyNaN16Words MinskyNaN16Lookup
  MinskyNaN16Window MinskyNaN16StepSpec MinskyNaN16SourceArith
  MinskyNaN16ActionRun MinskyNaN16PreserveTable MinskyNaN16PreserveHead.

(** ** Row projections at the runtime word index

    [nan16_row] has length eight; the source-arithmetic lemmas in
    [MinskyNaN16SourceArith] are stated at index [0], while the runtime
    [action_run] reads the same fields at index [1]. *)

Lemma nan16_row_nth_one :
  forall (e : Entry) (k : nat),
    k < 8 ->
    nth k (nan16_row e) 1 = nth k (nan16_row e) 0.
Proof.
  intros e k Hk. apply nth_indep.
  rewrite nan16_row_length. exact Hk.
Qed.

Lemma nan16_row_move_one :
  forall e, nth 3 (nan16_row e) 1 = Z.to_nat (e_move e + 1).
Proof.
  intro e. rewrite nan16_row_nth_one by lia. apply nan16_row_move.
Qed.

Lemma nan16_row_to_one :
  forall e, nth 4 (nan16_row e) 1 = e_to e.
Proof.
  intro e. rewrite nan16_row_nth_one by lia. apply nan16_row_to.
Qed.

Lemma nan16_row_halt_one :
  forall e, nth 5 (nan16_row e) 1 = (if e_halt e then 1 else 0).
Proof.
  intro e. rewrite nan16_row_nth_one by lia. apply nan16_row_halt.
Qed.

Lemma nan16_rows_nth_len :
  forall i, i < length nan16_rows -> length (nth i nan16_rows []) = 8.
Proof.
  intros i Hi.
  exact (@proj1 _ _
    (@Forall_nth (list nat) (fun r => length r = 8) nan16_rows)
    nan16_rows_forall_len i [] Hi).
Qed.

Lemma nan16_rows_nth_len_le :
  forall i, i < length nan16_rows -> length (nth i nan16_rows []) <= 8.
Proof.
  intros i Hi. rewrite nan16_rows_nth_len by exact Hi. lia.
Qed.

(** ** The representation

    [nstate_window_rep table_base base K c ns] says that [ns] is the runtime
    state obtained by placing the source tape [a_tape c] on the window
    [win_addr base K _], by placing the encoded table at [table_base], and by
    mirroring [a_halted c] into the runtime halt flag and halt cell. *)

Definition nstate_window_rep
    (table_base base K : nat) (c : AddressConfig) (ns : NState) : Prop :=
  n_state ns = a_state c /\
  n_head ns = Z.to_nat (a_head c + Z.of_nat K) /\
  (0 <= a_head c + Z.of_nat K)%Z /\
  n_halt ns = (if a_halted c then 1 else 0) /\
  n_mem ns action_halt_addr = (if a_halted c then 1 else 0) /\
  (forall z : Z, (0 <= z + Z.of_nat K)%Z ->
     n_mem ns (win_addr base K z) = a_tape c z) /\
  table_mem_at table_base nan16_rows (n_mem ns).

(** The runtime and source heads read the same cell. *)
Lemma nstate_window_rep_read :
  forall table_base base K (c : AddressConfig) (ns : NState),
    nstate_window_rep table_base base K c ns ->
    n_mem ns (base + n_head ns) = a_tape c (a_head c).
Proof.
  intros table_base base K c ns Hrep.
  destruct Hrep as [Hs [Hh [Hpos [Hnh [Hhcell [Hwin Htab]]]]]].
  rewrite Hh.
  replace (base + Z.to_nat (a_head c + Z.of_nat K))
    with (win_addr base K (a_head c)) by reflexivity.
  apply Hwin. exact Hpos.
Qed.

(** In an active representation the runtime halt flag and halt cell are zero. *)
Lemma nstate_window_rep_active_halt :
  forall table_base base K (c : AddressConfig) (ns : NState),
    nstate_window_rep table_base base K c ns ->
    a_halted c = false ->
    n_halt ns = 0 /\ n_mem ns action_halt_addr = 0.
Proof.
  intros table_base base K c ns Hrep Hhalt.
  destruct Hrep as [Hs [Hh [Hpos [Hnh [Hhcell [Hwin Htab]]]]]].
  rewrite Hnh, Hhalt; cbn.
  rewrite Hhcell, Hhalt; cbn.
  split; reflexivity.
Qed.

(** ** The hit state's flat memory

    [hit_nstate] is a record wrapper around [action_run]; the following
    identity makes the [PreserveHead]/[PreserveTable] frame lemmas applicable
    without unfolding the action block. *)

Lemma hit_nstate_mem :
  forall table_base tape_addr head (m : Mem) row,
    n_mem (hit_nstate table_base tape_addr head m row) =
    snd (action_run table_base tape_addr head m row).
Proof. intros. reflexivity. Qed.

(** ** Layout consequences

    If the control cells are below the table and the table is below the
    window, then every control cell is below the window, and every table
    cell is below the window. *)

Lemma controls_below_base :
  forall table_base base,
    action_halt_addr < table_base ->
    table_base + 8 * length nan16_rows <= base ->
    action_head_addr < base /\
    action_state_addr < base /\
    action_halt_addr < base.
Proof.
  intros table_base base Hctrl Hbelow.
  assert (Htb : table_base <= base).
  { pose proof Hbelow as H. rewrite nan16_rows_length in H. lia. }
  assert (Hhalt : action_halt_addr < table_base) by exact Hctrl.
  assert (Hhead : action_head_addr < table_base).
  { unfold action_head_addr. unfold action_halt_addr in Hctrl. lia. }
  assert (Hstate : action_state_addr < table_base).
  { unfold action_state_addr. unfold action_halt_addr in Hctrl. lia. }
  split; [lia|]. split; [lia|lia].
Qed.

(** ** One-step refinement *)

Theorem nstep_refines_address_step_scanned :
  forall (table_base base K : nat) (c : AddressConfig) (ns : NState),
    nstate_window_rep table_base base K c ns ->
    (0 < a_head c + Z.of_nat K)%Z ->
    action_halt_addr < table_base ->
    table_base + 8 * length nan16_rows <= base ->
    nstate_window_rep table_base base K
      (address_step_scanned c)
      (nstep nan16_rows table_base base ns).
Proof.
  intros table_base base K c ns Hrep Hslack Hctrl Hbelow.
  pose proof Hrep as Hrep0.
  destruct Hrep as [Hs [Hh [Hpos [Hnh [Hhcell [Hwin Htab]]]]]].
  unfold address_step_scanned, address_step_with.
  destruct (a_halted c) eqn:Hhalted.

  - (* ---- halted source: the runtime refuses to step ----------------- *)
    assert (Hnh1 : n_halt ns = 1)
      by (rewrite Hnh; reflexivity).
    assert (Hstep : nstep nan16_rows table_base base ns = ns).
    { unfold nstep. rewrite Hnh1. reflexivity. }
    rewrite Hstep. exact Hrep0.

  - (* ---- active source ---------------------------------------------- *)
    cbn [address_step_with].
    assert (Hn_halt : n_halt ns = 0)
      by (rewrite Hnh; reflexivity).
    assert (Hread : n_mem ns (base + n_head ns) = a_tape c (a_head c)).
    { apply (nstate_window_rep_read table_base base K c ns Hrep0). }
    assert (Hscan :
      scan_index_from 0 (n_state ns) (n_mem ns (base + n_head ns))
        nan16_rows =
      scan_index_from 0 (a_state c) (a_tape c (a_head c)) nan16_rows).
    { rewrite Hs, Hread. reflexivity. }

    (* Global layout facts, used in both lookup branches. *)
    assert (Htb : table_base <= base).
    { pose proof Hbelow as H. rewrite nan16_rows_length in H. lia. }
    assert (Hhalt_tab : action_halt_addr < table_base) by exact Hctrl.
    assert (Hhead_tab : action_head_addr < table_base).
    { unfold action_head_addr. unfold action_halt_addr in Hctrl. lia. }
    assert (Hstate_tab : action_state_addr < table_base).
    { unfold action_state_addr. unfold action_halt_addr in Hctrl. lia. }
    assert (Hhead_lt : action_head_addr < base) by lia.
    assert (Hstate_lt : action_state_addr < base) by lia.
    assert (Hhalt_lt : action_halt_addr < base) by lia.

    destruct (scan_index_from 0 (a_state c) (a_tape c (a_head c)) nan16_rows)
      as [[j row]|] eqn:E.

    + (* ---- matching row: action_run implements address_step_with ------- *)
      destruct (scan_index_nan16_rows_some (a_state c)
        (a_tape c (a_head c)) j row E) as [e [Hlu Hrow]].
      subst row.
      assert (Escan : scan_table (a_state c) (a_tape c (a_head c)) =
                      Some e).
      { rewrite <- (nan16_lookup_agrees_all (a_state c)
          (a_tape c (a_head c))). exact Hlu. }
      rewrite Escan. cbn beta iota zeta.
      assert (Hidx_n : scan_index_from 0 (n_state ns)
        (n_mem ns (base + n_head ns)) nan16_rows = Some (j, nan16_row e)).
      { exact Hscan. }
      rewrite (nstep_active_hit nan16_rows table_base base ns j
        (nan16_row e) Hn_halt Hidx_n).
      replace (base + n_head ns) with (win_addr base K (a_head c))
        by (rewrite Hh; reflexivity).

      pose proof (win_addr_ge_base base K (a_head c)) as Htape_ge.
      assert (Hdis_head : win_addr base K (a_head c) <> action_head_addr)
        by lia.
      assert (Hdis_state : win_addr base K (a_head c) <> action_state_addr)
        by lia.
      assert (Hdis_halt : win_addr base K (a_head c) <> action_halt_addr)
        by lia.
      destruct (nan16_lookup_some_move_range (a_state c)
        (a_tape c (a_head c)) e Hlu) as [Hlo Hhi].

      unfold nstate_window_rep.
      split.
      * (* state *) 
        transitivity (nth 4 (nan16_row e) 1).
        -- apply hit_nstate_state_cell; assumption.
        -- rewrite nan16_row_to_one. reflexivity.
      * split.
        -- (* head *)
           transitivity (action_new_head (n_head ns)
             (nth 3 (nan16_row e) 1)).
           ++ apply hit_nstate_head.
           ++ rewrite Hh, nan16_row_move_one. symmetry.
              apply (action_new_head_win (a_head c) K
                (Z.to_nat (a_head c + Z.of_nat K)) (e_move e)).
              ** exact Hslack.
              ** exact Hlo.
              ** exact Hhi.
              ** reflexivity.
        -- split.
           ++ (* nonnegativity of the new head offset *) cbn. lia.
           ++ split.
              ** (* halt flag *)
                 transitivity
                   (if Nat.eqb (nth 5 (nan16_row e) 1) 0
                    then n_mem ns action_halt_addr else 1).
                 { apply hit_nstate_halt_cell; assumption. }
                 rewrite nan16_row_halt_one.
                 assert (Hhcell0 : n_mem ns action_halt_addr = 0)
                   by (rewrite Hhcell; reflexivity).
                 rewrite Hhcell0.
                 destruct (e_halt e); cbn; reflexivity.
              ** split.
                 { (* halt cell *)
                   rewrite hit_nstate_mem.
                   rewrite (action_run_halt_cell table_base
                     (win_addr base K (a_head c)) (n_head ns)
                     (n_mem ns) (nan16_row e)
                     Hdis_head Hdis_state Hdis_halt).
                   rewrite nan16_row_halt_one.
                   assert (Hhcell0 : n_mem ns action_halt_addr = 0)
                     by (rewrite Hhcell; reflexivity).
                   rewrite Hhcell0.
                   destruct (e_halt e); cbn; reflexivity. }
                 split.
                 { (* tape window *)
                   intros z Hz.
                   rewrite hit_nstate_mem.
                   destruct (Z.eqb z (a_head c)) eqn:Ez.
                   - apply Z.eqb_eq in Ez. subst z.
                     rewrite (action_run_tape table_base
                       (win_addr base K (a_head c)) (n_head ns)
                       (n_mem ns) (nan16_row e)
                       Hdis_head Hdis_state Hdis_halt).
                     rewrite nan16_row_write.
                     cbn.
                     symmetry. apply write_at_head.
                   - apply Z.eqb_neq in Ez.
                     assert (Hne_addr :
                       win_addr base K z <> win_addr base K (a_head c)).
                     { intro Heq.
                       assert (Hzn : (0 <= z + Z.of_nat K)%Z) by exact Hz.
                       assert (Hhn : (0 <= a_head c + Z.of_nat K)%Z)
                         by lia.
                       exact (Ez (win_addr_inj base K z (a_head c)
                         Hzn Hhn Heq)). }
                     assert (Hne_head :
                       win_addr base K z <> action_head_addr).
                     { intro Heq. pose proof (win_addr_ge_base base K z).
                       lia. }
                     assert (Hne_state :
                       win_addr base K z <> action_state_addr).
                     { intro Heq. pose proof (win_addr_ge_base base K z).
                       lia. }
                     assert (Hne_halt :
                       win_addr base K z <> action_halt_addr).
                     { intro Heq. pose proof (win_addr_ge_base base K z).
                       lia. }
                     rewrite (action_run_frame table_base
                       (win_addr base K (a_head c)) (n_head ns)
                       (n_mem ns) (nan16_row e) (win_addr base K z)
                       Hne_addr Hne_head Hne_state Hne_halt).
                     rewrite Hwin by exact Hz.
                     cbn.
                     symmetry. apply write_at_frame. exact Ez. }
                 { (* table invariant *)
                   rewrite hit_nstate_mem.
                   apply (table_mem_at_action_run table_base nan16_rows
                     (n_mem ns) table_base (win_addr base K (a_head c))
                     (n_head ns) (nan16_row e) Htab).
                   - intros i f Hi Hf.
                     apply (table_cell_outside_span table_base nan16_rows
                       (win_addr base K (a_head c)) i f
                       nan16_rows_nth_len_le Hi Hf).
                     right. lia.
                   - intros i f Hi Hf.
                     apply (table_cell_outside_span table_base nan16_rows
                       action_head_addr i f nan16_rows_nth_len_le Hi Hf).
                     left. exact Hhead_tab.
                   - intros i f Hi Hf.
                     apply (table_cell_outside_span table_base nan16_rows
                       action_state_addr i f nan16_rows_nth_len_le Hi Hf).
                     left. exact Hstate_tab.
                   - intros i f Hi Hf.
                     apply (table_cell_outside_span table_base nan16_rows
                       action_halt_addr i f nan16_rows_nth_len_le Hi Hf).
                     left. exact Hhalt_tab. }

    + (* ---- missing row: runtime and source both halt without writing --- *)
      assert (Escan : scan_table (a_state c) (a_tape c (a_head c)) = None).
      { rewrite <- (nan16_lookup_agrees_all (a_state c)
          (a_tape c (a_head c))).
        apply scan_index_nan16_rows_none. exact E. }
      rewrite Escan. cbn beta iota zeta.
      assert (Hidx_n : scan_index_from 0 (n_state ns)
        (n_mem ns (base + n_head ns)) nan16_rows = None).
      { exact Hscan. }
      rewrite (nstep_active_none nan16_rows table_base base ns
        Hn_halt Hidx_n).

      unfold nstate_window_rep.
      split; [exact Hs|].
      split; [exact Hh|].
      split; [exact Hpos|].
      split; [cbn; reflexivity|].
      split.
      * change (set_mem (n_mem ns) action_halt_addr 1 action_halt_addr = 1).
        rewrite set_mem_same. reflexivity.
      * split.
        -- intros z Hz.
           change (set_mem (n_mem ns) action_halt_addr 1
             (win_addr base K z) = a_tape c z).
           rewrite (set_mem_neq (n_mem ns) action_halt_addr 1
             (win_addr base K z)).
           ++ apply Hwin. exact Hz.
           ++ intro Heq. pose proof (win_addr_ge_base base K z). lia.
        -- change (table_mem_at table_base nan16_rows
             (set_mem (n_mem ns) action_halt_addr 1)).
           apply (table_mem_at_set_mem_outside table_base nan16_rows
             (n_mem ns) action_halt_addr 1 Htab).
           intros i f Hi Hf.
           apply (table_cell_outside_span table_base nan16_rows
             action_halt_addr i f nan16_rows_nth_len_le Hi Hf).
           left. exact Hhalt_tab.
Qed.

(** The same statement through the indexed lookup, using
    [address_step_refines]. *)

Corollary nstep_refines_address_step_indexed :
  forall (table_base base K : nat) (c : AddressConfig) (ns : NState),
    nstate_window_rep table_base base K c ns ->
    (0 < a_head c + Z.of_nat K)%Z ->
    action_halt_addr < table_base ->
    table_base + 8 * length nan16_rows <= base ->
    nstate_window_rep table_base base K
      (address_step_indexed c)
      (nstep nan16_rows table_base base ns).
Proof.
  intros. rewrite address_step_refines.
  apply nstep_refines_address_step_scanned; assumption.
Qed.

(** The NaN16 native lookup [nan16_lookup] induces the same address step as
    [scan_table], so the theorem also applies to
    [MinskyNaN16Words.nan16_address_step]. *)

Lemma nan16_address_step_eq_scanned :
  forall c : AddressConfig,
    nan16_address_step c = address_step_scanned c.
Proof.
  intro c. unfold nan16_address_step, address_step_scanned,
    address_step_with.
  destruct (a_halted c); [reflexivity|].
  rewrite nan16_lookup_agrees_all. reflexivity.
Qed.

Corollary nstep_refines_nan16_address_step :
  forall (table_base base K : nat) (c : AddressConfig) (ns : NState),
    nstate_window_rep table_base base K c ns ->
    (0 < a_head c + Z.of_nat K)%Z ->
    action_halt_addr < table_base ->
    table_base + 8 * length nan16_rows <= base ->
    nstate_window_rep table_base base K
      (nan16_address_step c)
      (nstep nan16_rows table_base base ns).
Proof.
  intros. rewrite nan16_address_step_eq_scanned.
  apply nstep_refines_address_step_scanned; assumption.
Qed.

(** Composing with [zipper_address_step_bisim] gives the source zipper
    [MinskyTable.step] form: after one runtime step there is an address
    configuration which both represents the runtime state and is bisimilar
    to the zipper successor. *)

Corollary nstep_refines_zipper_step :
  forall (table_base base K : nat) (zip : Config) (c : AddressConfig)
         (ns : NState),
    config_bisim zip c ->
    nstate_window_rep table_base base K c ns ->
    (0 < a_head c + Z.of_nat K)%Z ->
    action_halt_addr < table_base ->
    table_base + 8 * length nan16_rows <= base ->
    exists c' : AddressConfig,
      nstate_window_rep table_base base K c'
        (nstep nan16_rows table_base base ns) /\
      config_bisim (step zip) c'.
Proof.
  intros table_base base K zip c ns Hbis Hrep Hslack Hctrl Hbelow.
  exists (address_step_indexed c). split.
  - apply nstep_refines_address_step_indexed; assumption.
  - apply zipper_address_step_bisim. exact Hbis.
Qed.

Print Assumptions nstep_refines_address_step_scanned.
Print Assumptions nstep_refines_address_step_indexed.
Print Assumptions nstep_refines_nan16_address_step.
Print Assumptions nstep_refines_zipper_step.
