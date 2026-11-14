(** * Address-based Minsky interpreter refinement

    The earlier MinskyTable model uses a two-list tape zipper. The native
    C++ interpreter instead stores tape symbols at signed integer addresses,
    with a separate head coordinate and halted flag. This file supplies
    an address-based formal transition system using the SAME checked 184
    transitions, with no host interpreter in the proof.

    Every state/symbol lookup and every fuel-bounded execution of the
    indexed model is equal to the linear-scan model, including malformed
    inputs, halting writes, and negative tape addresses. It also checks
    the published trace independently in address space.

    This is a proof about the abstract address-tape semantics. The actual
    C++ chart-page allocator, compiler and machine code remain separate
    obligations, and no C++ binary-verification claim is made here.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTable MinskyTableData.

Record AddressConfig := {
  a_state : nat;
  a_head : Z;
  a_tape : Z -> nat;
  a_halted : bool
}.

Definition write_at (t : Z -> nat) (head : Z) (symbol : nat) : Z -> nat :=
  fun p => if Z.eqb p head then symbol else t p.

Lemma write_at_head :
  forall t h s, write_at t h s h = s.
Proof.
  intros t h s. unfold write_at.
  rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma write_at_frame :
  forall t h s p, p <> h -> write_at t h s p = t p.
Proof.
  intros t h s p Hne. unfold write_at.
  apply Z.eqb_neq in Hne. rewrite Hne. reflexivity.
Qed.

(** A representation invariant for the entire unbounded tape.  The first
    clause reads cells at and to the right of the head, and the second
    reads the cells to its left, nearest first.  Both representations
    implicitly fill absent cells with the same blank symbol. *)
Definition tape_bisim (t : Tape) (h : Z) (memory : Z -> nat) : Prop :=
  (forall i : nat,
      memory (h + Z.of_nat i) = nth i (t_right t) blank) /\
  (forall i : nat,
      memory (h - Z.of_nat (S i)) = nth i (t_left t) blank).

(** A constructive embedding: every zipper tape has an equivalent tape
    in the signed-address representation, at ANY chosen head coordinate. *)
Definition embed_tape (t : Tape) (h : Z) : Z -> nat :=
  fun p =>
    if (h <=? p)%Z
    then nth (Z.to_nat (p - h)) (t_right t) blank
    else nth (Z.to_nat (h - p - 1)) (t_left t) blank.

Lemma embed_tape_bisim :
  forall t h, tape_bisim t h (embed_tape t h).
Proof.
  intros t h. unfold tape_bisim, embed_tape. split; intros i.
  - assert (Hge : (h <=? h + Z.of_nat i)%Z = true).
    { apply Z.leb_le. lia. }
    rewrite Hge.
    replace (Z.to_nat (h + Z.of_nat i - h)) with i by lia.
    reflexivity.
  - assert (Hlt : (h <=? h - Z.of_nat (S i))%Z = false).
    { apply Z.leb_gt. lia. }
    rewrite Hlt.
    replace (Z.to_nat (h - (h - Z.of_nat (S i)) - 1))
      with i by lia.
    reflexivity.
Qed.

Lemma tape_bisim_read :
  forall t h memory, tape_bisim t h memory ->
    read t = memory h.
Proof.
  intros t h memory [Hr _].
  specialize (Hr 0%nat). simpl in Hr.
  replace (h + 0) with h in Hr by lia.
  unfold read. destruct (t_right t); simpl in *; symmetry; exact Hr.
Qed.

Lemma tape_bisim_write :
  forall t h memory symbol,
    tape_bisim t h memory ->
    tape_bisim (write t symbol) h (write_at memory h symbol).
Proof.
  intros t h memory symbol [Hr Hl].
  split.
  - intros [|i].
    + simpl. replace (h + 0) with h by lia.
      rewrite write_at_head.
      unfold write. simpl. destruct (t_right t); reflexivity.
    + unfold write. simpl.
      rewrite write_at_frame by lia.
      specialize (Hr (S i)).
      destruct (t_right t) as [|x xs].
      * destruct i; simpl in *; exact Hr.
      * simpl in *; exact Hr.
  - intros i. unfold write. simpl.
    rewrite write_at_frame by lia.
    apply Hl.
Qed.

Lemma tape_bisim_move_left :
  forall t h memory,
    tape_bisim t h memory ->
    tape_bisim (move_left t) (h - 1) memory.
Proof.
  intros t h memory [Hr Hl].
  unfold move_left.
  destruct (t_left t) as [|x xs] eqn:Hleft; split.
  - intros [|i].
    + simpl. replace (h - 1 + 0) with
        (h - Z.of_nat 1) by lia.
      specialize (Hl 0%nat).
      simpl in Hl. exact Hl.
    + simpl. rewrite <- (Hr i). f_equal. lia.
  - intros i.
    specialize (Hl (S i)).
    replace (h - 1 - Z.of_nat (S i)) with
      (h - Z.of_nat (S (S i))) by lia.
    destruct i; simpl in *; exact Hl.
  - intros [|i].
    + simpl. replace (h - 1 + 0) with
        (h - Z.of_nat 1) by lia.
      specialize (Hl 0%nat).
      simpl in Hl. exact Hl.
    + simpl. rewrite <- (Hr i). f_equal. lia.
  - intros i.
    specialize (Hl (S i)).
    replace (h - 1 - Z.of_nat (S i)) with
      (h - Z.of_nat (S (S i))) by lia.
    simpl in Hl. exact Hl.
Qed.

Lemma tape_bisim_move_right :
  forall t h memory,
    tape_bisim t h memory ->
    tape_bisim (move_right t) (h + 1) memory.
Proof.
  intros t h memory [Hr Hl].
  unfold move_right.
  destruct (t_right t) as [|x xs] eqn:Hright; split.
  - intros i.
    specialize (Hr (S i)).
    replace (h + 1 + Z.of_nat i) with
      (h + Z.of_nat (S i)) by lia.
    destruct i; simpl in *; exact Hr.
  - intros [|i].
    + simpl. specialize (Hr 0%nat). simpl in Hr.
      transitivity (memory (h + 0)).
      * f_equal. lia.
      * exact Hr.
    + simpl. rewrite <- (Hl i). f_equal. lia.
  - intros i.
    specialize (Hr (S i)).
    replace (h + 1 + Z.of_nat i) with
      (h + Z.of_nat (S i)) by lia.
    simpl in Hr. exact Hr.
  - intros [|i].
    + simpl. specialize (Hr 0%nat). simpl in Hr.
      transitivity (memory (h + 0)).
      * f_equal. lia.
      * exact Hr.
    + simpl. rewrite <- (Hl i). f_equal. lia.
Qed.

Lemma tape_bisim_move_tape :
  forall t h memory direction,
    (direction = -1 \/ direction = 0 \/ direction = 1) ->
    tape_bisim t h memory ->
    tape_bisim (move_tape t direction) (h + direction) memory.
Proof.
  intros t h memory direction Hdirection Htape.
  destruct Hdirection as [-> | [-> | ->]]; unfold move_tape; simpl.
  - replace (h + -1) with (h - 1) by lia.
    apply tape_bisim_move_left. exact Htape.
  - replace (h + 0) with h by lia. exact Htape.
  - apply tape_bisim_move_right. exact Htape.
Qed.

(** A finite, kernel-evaluated certificate rules out unexpected movement
    directions in all 184 entries.  It is this fact that allows the exact
    C++ address update [+ direction] to match zipper movement. *)
Definition move_allowed (e : Entry) : bool :=
  (Z.eqb (e_move e) (-1) || Z.eqb (e_move e) 0) ||
  Z.eqb (e_move e) 1.

Lemma minsky_moves_allowed :
  forallb move_allowed minsky_entries = true.
Proof. vm_compute. reflexivity. Qed.

Lemma minsky_entry_move_allowed :
  forall e, In e minsky_entries ->
    e_move e = -1 \/ e_move e = 0 \/ e_move e = 1.
Proof.
  intros e Hin.
  pose proof (MinskyTable.forallb_forall _ _ _
    minsky_moves_allowed e Hin) as H.
  unfold move_allowed in H.
  apply orb_true_iff in H as [H | H].
  - apply orb_true_iff in H as [H | H].
    + left. now apply Z.eqb_eq.
    + right. left. now apply Z.eqb_eq.
  - right. right. now apply Z.eqb_eq.
Qed.

Lemma find_entry_move_allowed :
  forall q s e, find_entry q s = Some e ->
    e_move e = -1 \/ e_move e = 0 \/ e_move e = 1.
Proof.
  intros q s e Hfind.
  unfold find_entry in Hfind.
  destruct ((q <? 23)%nat && (s <? 8)%nat); try discriminate.
  apply minsky_entry_move_allowed.
  eapply nth_error_In. exact Hfind.
Qed.

Definition address_halt (c : AddressConfig) : AddressConfig :=
  {| a_state := a_state c;
     a_head := a_head c;
     a_tape := a_tape c;
     a_halted := true |}.

(** This is the observable transition order in
    [UniversalTuringMachine::step]: read, scan, write, set state, move head,
    then set the halt flag. Missing transitions halt without writing. *)
Definition address_step_with
    (lookup : nat -> nat -> option Entry) (c : AddressConfig) : AddressConfig :=
  if a_halted c then c
  else
    match lookup (a_state c) (a_tape c (a_head c)) with
    | None => address_halt c
    | Some e =>
        {| a_state := e_to e;
           a_head := a_head c + e_move e;
           a_tape := write_at (a_tape c) (a_head c) (e_write e);
           a_halted := e_halt e |}
    end.

Definition address_step_indexed : AddressConfig -> AddressConfig :=
  address_step_with find_entry.

Definition address_step_scanned : AddressConfig -> AddressConfig :=
  address_step_with scan_table.

(** This is the missing representation-level bridge.  It states equality
    of state, halt flag, and EVERY tape cell (not just a bounded trace).
    The address head may be negative and the tape may be arbitrarily long. *)
Definition config_bisim (zip : Config) (addr : AddressConfig) : Prop :=
  c_state zip = a_state addr /\
  c_halted zip = a_halted addr /\
  tape_bisim (c_tape zip) (a_head addr) (a_tape addr).

Definition embed_config (c : Config) (h : Z) : AddressConfig :=
  {| a_state := c_state c;
     a_head := h;
     a_tape := embed_tape (c_tape c) h;
     a_halted := c_halted c |}.

Lemma embed_config_bisim :
  forall c h, config_bisim c (embed_config c h).
Proof.
  intros c h. unfold config_bisim, embed_config. simpl.
  split; [reflexivity |]. split; [reflexivity |].
  apply embed_tape_bisim.
Qed.

Theorem zipper_address_step_bisim :
  forall zip addr,
    config_bisim zip addr ->
    config_bisim (step zip) (address_step_indexed addr).
Proof.
  intros [q t stopped] [qa h memory stopped_a]
    [Hstate [Hhalt Htape]].
  simpl in *. subst qa stopped_a.
  unfold step, address_step_indexed, address_step_with.
  simpl.
  destruct stopped eqn:Hstopped.
  - unfold config_bisim. simpl.
    split; [reflexivity |]. split; [reflexivity |]. exact Htape.
  - rewrite <- (tape_bisim_read t h memory Htape).
    destruct (find_entry q (read t)) as [e|] eqn:Hlookup.
    + destruct (e_halt e) eqn:Hentryhalt.
      * unfold config_bisim. simpl.
        split; [reflexivity |]. split; [reflexivity |].
        apply tape_bisim_move_tape.
        -- eapply find_entry_move_allowed. exact Hlookup.
        -- apply tape_bisim_write. exact Htape.
      * unfold config_bisim. simpl.
        split; [reflexivity |]. split; [reflexivity |].
        apply tape_bisim_move_tape.
        -- eapply find_entry_move_allowed. exact Hlookup.
        -- apply tape_bisim_write. exact Htape.
    + unfold config_bisim. simpl.
      split; [reflexivity |]. split; [reflexivity |]. exact Htape.
Qed.

Theorem address_step_refines :
  forall c, address_step_indexed c = address_step_scanned c.
Proof.
  intros c. unfold address_step_indexed, address_step_scanned,
    address_step_with.
  destruct (a_halted c); [reflexivity |].
  rewrite find_entry_scan_all. reflexivity.
Qed.

Fixpoint address_run (fuel : nat)
    (transition : AddressConfig -> AddressConfig) (c : AddressConfig) :
    AddressConfig :=
  match fuel with
  | 0%nat => c
  | S n =>
      if a_halted c then c
      else address_run n transition (transition c)
  end.

Theorem address_run_refines :
  forall fuel c,
    address_run fuel address_step_indexed c =
    address_run fuel address_step_scanned c.
Proof.
  induction fuel as [|n IH]; intros c; simpl.
  - reflexivity.
  - destruct (a_halted c); [reflexivity |].
    rewrite (address_step_refines c). apply IH.
Qed.

(** The native [UniversalTuringMachine::run] increments its returned count
    only when [step()] returns true.  A halting transition executes and
    updates the final configuration, but is NOT included in this count.
    This alternate run semantics models that observable convention. *)
Fixpoint address_run_cpp_counted (fuel : nat) (c : AddressConfig) :
    nat * AddressConfig :=
  match fuel with
  | 0%nat => (0%nat, c)
  | S n =>
      if a_halted c then (0%nat, c)
      else
        let next := address_step_scanned c in
        if a_halted next then (0%nat, next)
        else
          let '(completed, final) := address_run_cpp_counted n next in
          (S completed, final)
  end.

(** The counted and fuel-driven runs have identical FINAL machine states;
    only their reported step counts differ on a halting transition. *)
Theorem address_cpp_counted_final_agree :
  forall fuel c,
    snd (address_run_cpp_counted fuel c) =
    address_run fuel address_step_scanned c.
Proof.
  induction fuel as [|n IH]; intros c; simpl.
  - reflexivity.
  - destruct (a_halted c) eqn:Hhalt; [reflexivity |].
    destruct (a_halted (address_step_scanned c)) eqn:Hnext.
    + destruct n as [|n']; simpl; [reflexivity |].
      rewrite Hnext. reflexivity.
    + destruct (address_run_cpp_counted n (address_step_scanned c))
        as [completed final] eqn:Hrun.
      simpl. specialize (IH (address_step_scanned c)).
      rewrite Hrun in IH. simpl in IH. exact IH.
Qed.

Corollary address_cpp_counted_final_indexed :
  forall fuel c,
    snd (address_run_cpp_counted fuel c) =
    address_run fuel address_step_indexed c.
Proof.
  intros fuel c.
  rewrite (address_cpp_counted_final_agree fuel c).
  symmetry. apply address_run_refines.
Qed.

Theorem zipper_address_run_bisim :
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run fuel zip)
      (address_run fuel address_step_indexed addr).
Proof.
  induction fuel as [|fuel IH]; intros zip addr Hsim; simpl.
  - exact Hsim.
  - destruct Hsim as [Hstate [Hhalt Htape]].
    destruct (c_halted zip) eqn:Hstopped.
    + rewrite <- Hhalt. simpl.
      unfold config_bisim.
      split; [exact Hstate |]. split; [exact Hhalt |]. exact Htape.
    + rewrite <- Hhalt. simpl.
      apply IH. apply zipper_address_step_bisim.
      unfold config_bisim.
      split; [exact Hstate |]. split; [exact Hhalt |]. exact Htape.
Qed.

Corollary every_zipper_run_has_address_refinement :
  forall fuel zip h,
    config_bisim (run fuel zip)
      (address_run fuel address_step_indexed (embed_config zip h)).
Proof.
  intros fuel zip h.
  apply zipper_address_run_bisim.
  apply embed_config_bisim.
Qed.

Corollary zipper_address_scanned_run_bisim :
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run_scan fuel zip)
      (address_run fuel address_step_scanned addr).
Proof.
  intros fuel zip addr Hsim.
  rewrite <- (run_indexed_scan_agree_all fuel zip).
  rewrite <- (address_run_refines fuel addr).
  apply zipper_address_run_bisim. exact Hsim.
Qed.

Theorem address_halt_writes_before_flag :
  forall c e,
    a_halted c = false ->
    find_entry (a_state c) (a_tape c (a_head c)) = Some e ->
    e_halt e = true ->
    address_step_indexed c =
      {| a_state := e_to e;
         a_head := a_head c + e_move e;
         a_tape := write_at (a_tape c) (a_head c) (e_write e);
         a_halted := true |}.
Proof.
  intros c e Hrunning Hentry Hhalt.
  unfold address_step_indexed, address_step_with.
  rewrite Hrunning, Hentry, Hhalt. reflexivity.
Qed.

(** Initial memory is the published Minsky tape at absolute positions
    0..72; all other signed positions contain the blank symbol 2. *)
Definition list_tape (cells : list nat) : Z -> nat :=
  fun p => if (p <? 0)%Z then blank
           else nth (Z.to_nat p) cells blank.

Definition initial_address_config : AddressConfig :=
  {| a_state := 5;
     a_head := 38;
     a_tape := list_tape initial_cells;
     a_halted := false |}.

Definition trace_final_ok (c : AddressConfig) : bool :=
  Nat.eqb (a_state c) 2 &&
  Z.eqb (a_head c) 38 &&
  negb (a_halted c) &&
  forallb (fun i : nat =>
    Nat.eqb (a_tape c (Z.of_nat i)) (nth i expected_cells blank))
    (seq 0 73).

(** A second, independent kernel computation of the 100-step reference
    trace, now using signed-address functional tape representation. *)
Theorem address_trace_100 :
  trace_final_ok (address_run 100 address_step_indexed
                    initial_address_config) = true.
Proof. vm_compute. reflexivity. Qed.

Corollary address_trace_100_scanned :
  trace_final_ok (address_run 100 address_step_scanned
                    initial_address_config) = true.
Proof.
  rewrite <- (address_run_refines 100 initial_address_config).
  exact address_trace_100.
Qed.

Print Assumptions address_step_refines.
Print Assumptions address_run_refines.
Print Assumptions address_cpp_counted_final_agree.
Print Assumptions address_cpp_counted_final_indexed.
Print Assumptions zipper_address_step_bisim.
Print Assumptions zipper_address_run_bisim.
Print Assumptions zipper_address_scanned_run_bisim.
Print Assumptions every_zipper_run_has_address_refinement.
Print Assumptions address_halt_writes_before_flag.
Print Assumptions address_trace_100.
