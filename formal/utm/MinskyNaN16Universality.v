(** * Final NaN16 run equivalence with the left-infinite source

    This file assembles the top-level theorem of the NaN16 chain:

      left-infinite source halting
        <->  exists K t, K >= t /\
             the closed NaN16 VM run halts within the K-window encoding.

    The K-indexed initial VM is the literal fixture memory: the 184x8 table
    at [fixture_table_base = 104], the flat tape at
    [fixture_tape_base = 4096], and the source tape placed at signed
    coordinates [z] via [win_mem ... K], so the runtime offset is [z + K].

    The one-step source bridge is the checked theorem
    [nstep_refines_address_step_scanned] / [nstep_refines_address_step_indexed]
    of [MinskyNaN16AddressStep.v].  There is no extra bridge premise below.
    The only remaining inputs are the left-infinite well-formedness
    hypotheses and the window bound [K >= t]. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyTableData MinskyAddressRefinement
  MinskyWideSource MinskyConcreteDispatch MinskyLeftInfinite MinskyLeftInfiniteEncode
  MinskyLeftInfiniteEncoding MinskyLeftInfiniteLift MinskyBookRawBuffer
  MinskyLeftInfiniteClockRun MinskyLeftInfiniteUniversality
  MinskyNaN16VM MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16StepSpec
  MinskyNaN16Run MinskyNaN16RunClosed MinskyNaN16RunConcrete
  MinskyNaN16Window MinskyNaN16Words MinskyNaN16Lookup
  MinskyNaN16AddressStep.

Local Open Scope nat_scope.

(** ** Flat fixture memory *)

Definition fixture_words : list nat := concat fixture_table.

Definition fixture_table_cell (k : nat) : nat :=
  nth (k - fixture_table_base) fixture_words 0.

(** [fixture_table] is the encoded word image [nan16_rows] used by the
    source-step bridge. *)
Lemma fixture_table_eq_nan16_rows : fixture_table = nan16_rows.
Proof.
  unfold nan16_rows, nan16_row.
  rewrite fixture_table_is_word_image.
  reflexivity.
Qed.

(** Reading a fixed eight-word row out of the concatenated table. *)
Lemma nth_concat_eight :
  forall (rows : list (list nat)) i f,
    (forall r, In r rows -> length r = 8) ->
    i < length rows ->
    f < 8 ->
    nth (8 * i + f) (concat rows) 0 = nth f (nth i rows []) 0.
Proof.
  intros rows. induction rows as [|r rest IH]; intros i f Hall Hi Hf.
  - simpl in Hi. lia.
  - destruct i as [|i'].
    + replace (8 * 0 + f) with f by lia.
      cbn [concat].
      assert (Hfr : f < length r).
      { rewrite (Hall r (or_introl eq_refl)). exact Hf. }
      rewrite (app_nth1 r (concat rest) 0 (n:=f) Hfr).
      reflexivity.
    + replace (8 * S i' + f) with (8 + (8 * i' + f)) by lia.
      cbn [concat].
      assert (Hr8 : length r = 8) by (apply Hall; now left).
      assert (Hge : 8 + (8 * i' + f) >= length r) by lia.
      rewrite (app_nth2 r (concat rest) 0 (n:=8 + (8 * i' + f)) Hge).
      * replace (8 + (8 * i' + f) - length r) with (8 * i' + f).
        2:{ rewrite Hr8. lia. }
        cbn [nth].
        apply IH.
        -- intros r' Hin. apply Hall. now right.
        -- simpl in Hi. lia.
        -- exact Hf.
Qed.

Lemma fixture_table_rows8_in :
  forall r, In r fixture_table -> length r = 8.
Proof.
  intros r Hin.
  exact (proj1 (@Forall_forall (list nat)
    (fun r => length r = 8) fixture_table) fixture_table_rows8 r Hin).
Qed.

Lemma fixture_table_cell_spec :
  forall i f,
    i < length fixture_table ->
    f < 8 ->
    fixture_table_cell (fixture_table_base + 8 * i + f) =
      nth f (nth i fixture_table []) 0.
Proof.
  intros i f Hi Hf.
  unfold fixture_table_cell.
  replace (fixture_table_base + 8 * i + f - fixture_table_base)
    with (8 * i + f) by lia.
  apply nth_concat_eight.
  - exact fixture_table_rows8_in.
  - exact Hi.
  - exact Hf.
Qed.

(** The fixture table starts above the control cells and ends below the
    tape base. *)
Lemma fixture_table_base_above_halt :
  action_halt_addr < fixture_table_base.
Proof.
  unfold action_halt_addr, fixture_table_base. lia.
Qed.

Lemma fixture_table_fits_below_tape :
  fixture_table_base + 8 * length nan16_rows <= fixture_tape_base.
Proof.
  rewrite nan16_rows_length.
  unfold fixture_table_base, fixture_tape_base. lia.
Qed.

(** ** The K-window memory of an address configuration *)

Definition nan16_addr_mem (K : nat) (c : AddressConfig) : Mem :=
  fun k =>
    if k <? fixture_tape_base then
      if k =? action_head_addr then Z.to_nat (a_head c + Z.of_nat K)
      else if k =? action_state_addr then a_state c
      else if k =? action_halt_addr then (if a_halted c then 1 else 0)
      else if k =? tape_base_addr then fixture_tape_base
      else fixture_table_cell k
    else
      win_mem c fixture_tape_base K k.

Lemma nan16_addr_mem_head :
  forall K c,
    nan16_addr_mem K c action_head_addr =
      Z.to_nat (a_head c + Z.of_nat K).
Proof.
  intros. unfold nan16_addr_mem, action_head_addr, fixture_tape_base.
  cbn. reflexivity.
Qed.

Lemma nan16_addr_mem_state :
  forall K c,
    nan16_addr_mem K c action_state_addr = a_state c.
Proof.
  intros. unfold nan16_addr_mem, action_state_addr, action_head_addr,
    fixture_tape_base.
  cbn. reflexivity.
Qed.

Lemma nan16_addr_mem_halt :
  forall K c,
    nan16_addr_mem K c action_halt_addr =
      (if a_halted c then 1 else 0).
Proof.
  intros. unfold nan16_addr_mem, action_halt_addr, action_state_addr,
    action_head_addr, fixture_tape_base.
  cbn. reflexivity.
Qed.

Lemma nan16_addr_mem_tape_base :
  forall K c,
    nan16_addr_mem K c tape_base_addr = fixture_tape_base.
Proof.
  intros. unfold nan16_addr_mem, tape_base_addr, action_halt_addr,
    action_state_addr, action_head_addr, fixture_tape_base.
  cbn. reflexivity.
Qed.

Lemma nan16_addr_mem_win :
  forall K c z,
    (0 <= z + Z.of_nat K)%Z ->
    nan16_addr_mem K c (win_addr fixture_tape_base K z) = a_tape c z.
Proof.
  intros K c z Hz.
  unfold nan16_addr_mem.
  assert (Hge : fixture_tape_base <= win_addr fixture_tape_base K z)
    by (apply win_addr_ge_base).
  rewrite (proj2 (Nat.ltb_ge _ _) Hge).
  change (win_mem c fixture_tape_base K (win_addr fixture_tape_base K z) =
    a_tape c z).
  apply win_mem_addr. exact Hz.
Qed.

Lemma nan16_addr_mem_table :
  forall K c,
    table_mem_at fixture_table_base fixture_table (nan16_addr_mem K c).
Proof.
  intros K c i f Hi Hf.
  unfold table_mem_at.
  unfold nan16_addr_mem.
  assert (Hrow : length (nth i fixture_table []) = 8).
  { exact (@proj1 _ _
      (@Forall_nth (list nat) (fun r => length r = 8) fixture_table)
      fixture_table_rows8 i [] Hi). }
  assert (Hf8 : f < 8) by lia.
  assert (Hlt : fixture_table_base + 8 * i + f < fixture_tape_base).
  { apply fixture_table_below_tape; assumption. }
  rewrite (proj2 (Nat.ltb_lt _ _) Hlt).
  assert (Hne0 : fixture_table_base + 8 * i + f <> action_head_addr).
  { unfold fixture_table_base, action_head_addr. lia. }
  rewrite (proj2 (Nat.eqb_neq _ _) Hne0).
  assert (Hne1 : fixture_table_base + 8 * i + f <> action_state_addr).
  { unfold fixture_table_base, action_state_addr. lia. }
  rewrite (proj2 (Nat.eqb_neq _ _) Hne1).
  assert (Hne2 : fixture_table_base + 8 * i + f <> action_halt_addr).
  { unfold fixture_table_base, action_halt_addr. lia. }
  rewrite (proj2 (Nat.eqb_neq _ _) Hne2).
  assert (Hne3 : fixture_table_base + 8 * i + f <> tape_base_addr).
  { unfold fixture_table_base, tape_base_addr. lia. }
  rewrite (proj2 (Nat.eqb_neq _ _) Hne3).
  cbn.
  apply fixture_table_cell_spec; [exact Hi|exact Hf8].
Qed.

Lemma nan16_addr_mem_table_nan16_rows :
  forall K c,
    table_mem_at fixture_table_base nan16_rows (nan16_addr_mem K c).
Proof.
  intros. rewrite <- fixture_table_eq_nan16_rows.
  apply nan16_addr_mem_table.
Qed.

(** ** The canonical initial VM for a window *)

Definition nan16_vm_of_addr (K : nat) (c : AddressConfig) : VM :=
  {| vm_pc := 0;
     vm_reg := fun r =>
       match r with
       | 0 => 0
       | 2 => Z.to_nat (a_head c + Z.of_nat K)
       | 13 => 1
       | _ => 0
       end;
     vm_mem := nan16_addr_mem K c;
     vm_zf := false; vm_lf := false; vm_halted := false; vm_link := 0 |}.

Lemma nan16_vm_of_addr_reg0 :
  forall K c, vm_reg (nan16_vm_of_addr K c) 0 = 0.
Proof. reflexivity. Qed.

Lemma nan16_vm_of_addr_reg2 :
  forall K c,
    vm_reg (nan16_vm_of_addr K c) 2 =
      Z.to_nat (a_head c + Z.of_nat K).
Proof. reflexivity. Qed.

Lemma nan16_vm_of_addr_reg13 :
  forall K c, vm_reg (nan16_vm_of_addr K c) 13 = 1.
Proof. reflexivity. Qed.

Lemma nan16_vm_of_addr_entry_ok :
  forall K c,
    entry_ok (nan16_vm_of_addr K c)
      fixture_table fixture_table_base fixture_tape_base.
Proof.
  intros K c. unfold entry_ok. split.
  - apply nan16_vm_of_addr_reg0.
  - split.
    + rewrite nan16_vm_of_addr_reg2. symmetry. apply nan16_addr_mem_head.
    + split.
      * apply nan16_vm_of_addr_reg13.
      * split.
        -- reflexivity.
        -- split.
           ++ apply nan16_addr_mem_tape_base.
           ++ apply nan16_addr_mem_table.
Qed.

(** The initial VM state is exactly the bridge representation. *)
Lemma nan16_vm_of_addr_window_rep :
  forall K c,
    (0 <= a_head c + Z.of_nat K)%Z ->
    nstate_window_rep fixture_table_base fixture_tape_base K c
      (vm_to_nstate (nan16_vm_of_addr K c)).
Proof.
  intros K c Hpos.
  unfold nstate_window_rep. split.
  - change (vm_mem (nan16_vm_of_addr K c) action_state_addr = a_state c).
    apply nan16_addr_mem_state.
  - split.
    + change (vm_reg (nan16_vm_of_addr K c) 2 =
        Z.to_nat (a_head c + Z.of_nat K)).
      reflexivity.
    + split.
      * exact Hpos.
      * split.
        -- change (vm_mem (nan16_vm_of_addr K c) action_halt_addr =
             (if a_halted c then 1 else 0)).
           apply nan16_addr_mem_halt.
        -- split.
           ++ change (vm_mem (nan16_vm_of_addr K c) action_halt_addr =
                (if a_halted c then 1 else 0)).
              apply nan16_addr_mem_halt.
           ++ split.
              ** intros z Hz.
                 change (vm_mem (nan16_vm_of_addr K c)
                   (win_addr fixture_tape_base K z) = a_tape c z).
                 apply nan16_addr_mem_win. exact Hz.
              ** change (table_mem_at fixture_table_base nan16_rows
                   (vm_mem (nan16_vm_of_addr K c))).
                 apply nan16_addr_mem_table_nan16_rows.
Qed.

(** ** The checked one-step bridge in fixture form *)

Lemma nstep_refines_address_step_fixture :
  forall K c ns,
    nstate_window_rep fixture_table_base fixture_tape_base K c ns ->
    (0 < a_head c + Z.of_nat K)%Z ->
    nstate_window_rep fixture_table_base fixture_tape_base K
      (address_step_indexed c)
      (nstep fixture_table fixture_table_base fixture_tape_base ns).
Proof.
  intros K c ns Hrep Hslack.
  rewrite fixture_table_eq_nan16_rows.
  exact (nstep_refines_address_step_indexed fixture_table_base
    fixture_tape_base K c ns Hrep Hslack
    fixture_table_base_above_halt fixture_table_fits_below_tape).
Qed.

(** ** Head arithmetic for the window *)

Lemma address_run_halted :
  forall (fuel : nat) (trans : AddressConfig -> AddressConfig)
         (c : AddressConfig),
    a_halted c = true -> address_run fuel trans c = c.
Proof.
  induction fuel as [|n IH]; intros trans c H.
  - reflexivity.
  - cbn [address_run]. rewrite H. reflexivity.
Qed.

Lemma address_step_indexed_head_ge :
  forall c,
    (a_head (address_step_indexed c) >= a_head c - 1)%Z.
Proof.
  intro c. unfold address_step_indexed, address_step_with.
  destruct (a_halted c) eqn:Eh.
  - cbn. lia.
  - destruct (find_entry (a_state c) (a_tape c (a_head c)))
      as [e|] eqn:El.
    + destruct (find_entry_move_allowed _ _ _ El) as [-> | [-> | ->]];
        cbn; lia.
    + cbn. lia.
Qed.

Lemma address_run_head_ge :
  forall fuel c,
    (a_head (address_run fuel address_step_indexed c) >=
     a_head c - Z.of_nat fuel)%Z.
Proof.
  induction fuel as [|n IH]; intro c.
  - cbn. lia.
  - cbn [address_run].
    destruct (a_halted c) eqn:Eh.
    + rewrite Nat2Z.inj_succ. lia.
    + pose proof (IH (address_step_indexed c)) as Hrec.
      pose proof (address_step_indexed_head_ge c) as Hstep.
      rewrite Nat2Z.inj_succ. lia.
Qed.

(** With initial head [0] and [K >= t], every head reached before time
    [t] leaves at least one cell of slack on the left. *)
Lemma address_run_head_window :
  forall K t c0,
    K >= t ->
    a_head c0 = 0%Z ->
    forall i, i < t ->
      (0 < a_head (address_run i address_step_indexed c0) +
           Z.of_nat K)%Z.
Proof.
  intros K t c0 HK Hhead i Hi.
  pose proof (address_run_head_ge i c0) as Hge.
  rewrite Hhead in Hge.
  assert (Hlt : (Z.of_nat i < Z.of_nat K)%Z)
    by (apply Nat2Z.inj_lt; lia).
  lia.
Qed.

(** ** Lifting the representation through a full run *)

Lemma nan16_addr_run_rep :
  forall t K c ns,
    (forall i, i < t ->
      (0 < a_head (address_run i address_step_indexed c) +
           Z.of_nat K)%Z) ->
    nstate_window_rep fixture_table_base fixture_tape_base K c ns ->
    nstate_window_rep fixture_table_base fixture_tape_base K
      (address_run t address_step_indexed c)
      (nrun t fixture_table fixture_table_base fixture_tape_base ns).
Proof.
  induction t as [|t IH]; intros K c ns Hwin Hrep.
  - cbn [nrun address_run]. exact Hrep.
  - cbn [nrun]. cbn [address_run].
    destruct (a_halted c) eqn:Eh.
    + assert (Hnh : n_halt ns <> 0).
      { destruct Hrep as [_ [_ [_ [Hnh _]]]].
        rewrite Hnh, Eh. discriminate. }
      cbn [address_run].
      rewrite (nstep_halted fixture_table fixture_table_base
        fixture_tape_base ns Hnh).
      pose proof (IH K c ns) as HIH.
      rewrite (address_run_halted t address_step_indexed c Eh) in HIH.
      apply HIH.
      * intros i Hi. assert (HSi : S i < S t) by lia.
        specialize (Hwin (S i) HSi).
        cbn [address_run] in Hwin. rewrite Eh in Hwin.
        rewrite (address_run_halted i address_step_indexed c Eh).
        exact Hwin.
      * exact Hrep.
    + assert (Hguard : (0 < a_head c + Z.of_nat K)%Z).
      { assert (H0 : 0 < S t) by lia.
        pose proof (Hwin 0 H0) as Hg.
        cbn [address_run] in Hg. exact Hg. }
      pose proof (nstep_refines_address_step_fixture K c ns Hrep Hguard)
        as Hstep.
      apply (IH K (address_step_indexed c)
        (nstep fixture_table fixture_table_base fixture_tape_base ns)).
      * intros i Hi. assert (HSi : S i < S t) by lia.
        specialize (Hwin (S i) HSi).
        cbn [address_run] in Hwin. rewrite Eh in Hwin. exact Hwin.
      * exact Hstep.
Qed.

(** ** Reading the halt cell out of the closed fixture run *)

Definition nan16_vm_halted (vm : VM) : Prop :=
  vm_mem vm action_halt_addr <> 0.

Lemma if_one_neq_zero :
  forall b : bool, (if b then 1 else 0) <> 0 -> b = true.
Proof.
  intros []; cbn.
  - reflexivity.
  - intro H. exfalso. apply H. reflexivity.
Qed.

Lemma nan16_vm_run_halt_cell :
  forall n vm,
    entry_ok vm fixture_table fixture_table_base fixture_tape_base ->
    vm_mem (vm_run n vm fixture_table fixture_table_base) action_halt_addr =
      n_halt (nrun n fixture_table fixture_table_base fixture_tape_base
        (vm_to_nstate vm)).
Proof.
  intros n vm Hentry.
  destruct (vm_run_refines_fixture n vm Hentry) as [_ Hrel].
  unfold nstate_rel in Hrel.
  destruct Hrel as [_ [_ [Hh _]]].
  unfold vm_to_nstate in Hh. cbn [n_halt] in Hh.
  exact Hh.
Qed.

(** ** The native configuration family *)

Definition lic_native_init
    (rows : list WideSourceRow) (c : LeftInfiniteConfig) (K : nat) : Config :=
  if lic_halted c then dispatch_halt_at_y [] []
  else lic_q5_encode (lic_head c - Z.of_nat K - 2)
         (lic_lift_cfg c) (lic_book_rows (lic_lift_rows rows)) [].

(** ** Forward direction: a halting source reaches the canonical VM *)

Lemma nan16_source_halt_to_vm :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c ->
    exists K t,
      K >= t /\
      nan16_vm_halted
        (vm_run t
          (nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0))
          fixture_table fixture_table_base).
Proof.
  intros p rows c Hwf Hne Hlen Hok Hhalt.
  destruct (proj1 (lic_lifted_halting_equivalence p rows c Hwf Hne Hlen Hok)
    Hhalt) as [K [t [HKt Hnative]]].
  exists K, t. split; [exact HKt|].
  set (cfg := lic_native_init rows c K).
  set (acfg := embed_config cfg 0).
  set (vm := nan16_vm_of_addr K acfg).
  assert (Hentry : entry_ok vm fixture_table fixture_table_base
    fixture_tape_base) by (apply nan16_vm_of_addr_entry_ok).
  assert (Hhead0 : a_head acfg = 0%Z)
    by (unfold acfg, embed_config; reflexivity).
  assert (Hpos0 : (0 <= a_head acfg + Z.of_nat K)%Z)
    by (rewrite Hhead0; lia).
  assert (Hrep : nstate_window_rep fixture_table_base fixture_tape_base
    K acfg (vm_to_nstate vm))
    by (apply nan16_vm_of_addr_window_rep; exact Hpos0).
  assert (Hwin : forall i, i < t ->
      (0 < a_head (address_run i address_step_indexed acfg) +
           Z.of_nat K)%Z)
    by (intros i Hi; apply (address_run_head_window K t acfg HKt Hhead0 i Hi)).
  pose proof (nan16_addr_run_rep t K acfg (vm_to_nstate vm) Hwin Hrep)
    as Hrunrep.
  pose proof (nan16_vm_run_halt_cell t vm Hentry) as Hcell.
  assert (Hcfg_run : c_halted (run t cfg) = true).
  { unfold cfg, lic_native_init. exact Hnative. }
  pose proof (every_zipper_run_has_address_refinement t cfg 0) as Hbis.
  destruct Hbis as [_ [Hhalt_eq _]].
  assert (Haddr : a_halted (address_run t address_step_indexed acfg) = true).
  { assert (Hacfg : acfg = embed_config cfg 0) by reflexivity.
    rewrite Hacfg. rewrite <- Hhalt_eq. exact Hcfg_run. }
  assert (Hcanon : n_halt (nrun t fixture_table fixture_table_base
    fixture_tape_base (vm_to_nstate vm)) <> 0).
  { destruct Hrunrep as [_ [_ [_ [Hrun_halt _]]]].
    try fold cfg in Hrun_halt.
    try fold acfg in Hrun_halt.
    rewrite Hrun_halt, Haddr. discriminate. }
  unfold nan16_vm_halted.
  rewrite Hcell. exact Hcanon.
Qed.

(** ** Backward direction: any represented VM halt reflects to the source *)

Lemma nan16_vm_halt_to_source :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig)
         (K t : nat) (vm : VM),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    K >= t ->
    entry_ok vm fixture_table fixture_table_base fixture_tape_base ->
    nstate_window_rep fixture_table_base fixture_tape_base K
      (embed_config (lic_native_init rows c K) 0) (vm_to_nstate vm) ->
    nan16_vm_halted (vm_run t vm fixture_table fixture_table_base) ->
    left_infinite_eventually_halts rows c.
Proof.
  intros p rows c K t vm Hwf Hne Hlen Hok HKt Hentry Hrep Hhalt.
  set (cfg := lic_native_init rows c K).
  set (acfg := embed_config cfg 0).
  fold cfg in Hrep.
  fold acfg in Hrep.
  assert (Hhead0 : a_head acfg = 0%Z)
    by (unfold acfg, embed_config; reflexivity).
  assert (Hwin : forall i, i < t ->
      (0 < a_head (address_run i address_step_indexed acfg) +
           Z.of_nat K)%Z)
    by (intros i Hi; apply (address_run_head_window K t acfg HKt Hhead0 i Hi)).
  pose proof (nan16_addr_run_rep t K acfg (vm_to_nstate vm) Hwin Hrep)
    as Hrunrep.
  pose proof (nan16_vm_run_halt_cell t vm Hentry) as Hcell.
  assert (Hnrun : n_halt (nrun t fixture_table fixture_table_base
    fixture_tape_base (vm_to_nstate vm)) <> 0).
  { intro E. apply Hhalt. rewrite Hcell. exact E. }
  destruct Hrunrep as [_ [_ [_ [Hrun_halt _]]]].
  try unfold acfg in Hrun_halt.
  assert (Haddr : a_halted (address_run t address_step_indexed
    (embed_config cfg 0)) = true).
  { apply if_one_neq_zero.
    rewrite <- Hrun_halt. exact Hnrun. }
  pose proof (every_zipper_run_has_address_refinement t cfg 0) as Hbis.
  destruct Hbis as [_ [Hhalt_eq _]].
  assert (Hcfg_run : c_halted (run t cfg) = true).
  { rewrite Hhalt_eq, Haddr. reflexivity. }
  apply (proj2 (lic_lifted_halting_equivalence p rows c Hwf Hne Hlen Hok)).
  exists K, t. split; [exact HKt|].
  unfold cfg, lic_native_init in Hcfg_run. exact Hcfg_run.
Qed.

(** ** Final run-equivalence family theorem

    The VM state is existentially quantified but constrained by the checked
    [nstate_window_rep] representation and the fixture [entry_ok] invariant.
    The existential [K] is the left window and [t] the common native/VM run
    time, with [K >= t]. *)

Theorem nan16_run_halting_equivalence :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c <->
    exists K t (vm : VM),
      K >= t /\
      entry_ok vm fixture_table fixture_table_base fixture_tape_base /\
      nstate_window_rep fixture_table_base fixture_tape_base K
        (embed_config (lic_native_init rows c K) 0) (vm_to_nstate vm) /\
      nan16_vm_halted (vm_run t vm fixture_table fixture_table_base).
Proof.
  intros p rows c Hwf Hne Hlen Hok. split.
  - intro Hsrc.
    destruct (nan16_source_halt_to_vm p rows c Hwf Hne Hlen Hok Hsrc)
      as [K [t [HKt Hhalt]]].
    exists K, t,
      (nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0)).
    split; [exact HKt|].
    split.
    + apply nan16_vm_of_addr_entry_ok.
    + split.
      * apply nan16_vm_of_addr_window_rep.
        unfold embed_config. cbn. pose proof (Nat2Z.is_nonneg K). lia.
      * exact Hhalt.
  - intros [K [t [vm [HKt [Hentry [Hrep Hhalt]]]]]].
    eapply nan16_vm_halt_to_source with (p:=p).
    + exact Hwf.
    + exact Hne.
    + exact Hlen.
    + exact Hok.
    + exact HKt.
    + exact Hentry.
    + exact Hrep.
    + exact Hhalt.
Qed.

(** ** Canonical, VM-constructor form

    The initial VM is the explicit K-indexed family
    [nan16_vm_of_addr K (embed_config (lic_native_init ... K) 0)], so the
    only existential data are [K] and [t]. *)

Theorem nan16_run_halting_equivalence_canonical :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c <->
    exists K t,
      K >= t /\
      nan16_vm_halted
        (vm_run t
          (nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0))
          fixture_table fixture_table_base).
Proof.
  intros p rows c Hwf Hne Hlen Hok. split.
  - intros Hsrc.
    exact (nan16_source_halt_to_vm p rows c Hwf Hne Hlen Hok Hsrc).
  - intros [K [t [HKt Hhalt]]].
    eapply nan16_vm_halt_to_source with (p:=p) (K:=K) (t:=t)
      (vm:=nan16_vm_of_addr K
        (embed_config (lic_native_init rows c K) 0)).
    + exact Hwf.
    + exact Hne.
    + exact Hlen.
    + exact Hok.
    + exact HKt.
    + apply nan16_vm_of_addr_entry_ok.
    + apply nan16_vm_of_addr_window_rep.
      unfold embed_config. cbn. pose proof (Nat2Z.is_nonneg K). lia.
    + exact Hhalt.
Qed.

Print Assumptions nan16_source_halt_to_vm.
Print Assumptions nan16_vm_halt_to_source.
Print Assumptions nan16_run_halting_equivalence.
Print Assumptions nan16_run_halting_equivalence_canonical.
