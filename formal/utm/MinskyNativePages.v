(** * Separately stored, 4096-cell paged Minsky interpreter

    This module models the current C++ layout: description bytes and working
    cells have distinct backing stores.  Working addresses are partitioned
    into 4096-cell pages by Euclidean quotient/remainder, including negative
    addresses.  The native step scans six-byte description rows and checks
    signed-64-bit head overflow AFTER its write/state update.

    No assumption is made that an allocator always succeeds.  These theorems
    concern the value semantics of correctly allocated pages, not C++ object
    lifetime, allocation, serialization, or generated machine code.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable MinskyAddressRefinement
  MinskyChartEncoding MinskyChartScan MinskyNativeBounds.

Definition page_size : Z := 4096.
Definition page_key (p : Z) : Z := p / page_size.
Definition page_offset (p : Z) : Z := p mod page_size.

Lemma page_offset_range :
  forall p, 0 <= page_offset p < page_size.
Proof.
  intro p. unfold page_offset, page_size.
  apply Z.mod_pos_bound. lia.
Qed.

Lemma page_join :
  forall p, page_key p * page_size + page_offset p = p.
Proof.
  intro p. unfold page_key, page_offset, page_size.
  pose proof (Z.div_mod p 4096) as H.
  lia.
Qed.

Lemma page_coordinates_injective :
  forall p q,
    page_key p = page_key q ->
    page_offset p = page_offset q -> p = q.
Proof.
  intros p q Hkey Hoff.
  pose proof (page_join p).
  pose proof (page_join q).
  lia.
Qed.

(** C++ uses integer truncation followed by a negative-remainder correction.
    These concrete boundary examples ensure the Euclidean model uses the
    same page and slot convention at negative addresses. *)
Example negative_one_page : (page_key (-1), page_offset (-1)) = (-1, 4095).
Proof. vm_compute. reflexivity. Qed.
Example negative_boundary_page :
  (page_key (-4096), page_offset (-4096)) = (-1, 0).
Proof. vm_compute. reflexivity. Qed.
Example negative_boundary_minus_one_page :
  (page_key (-4097), page_offset (-4097)) = (-2, 4095).
Proof. vm_compute. reflexivity. Qed.
Example signed64_low_page :
  (page_key signed64_min, page_offset signed64_min) =
  (-2251799813685248, 0).
Proof. vm_compute. reflexivity. Qed.

Definition PageMemory := Z -> Z -> nat.

Definition page_read (work : PageMemory) (p : Z) : nat :=
  work (page_key p) (page_offset p).

Definition page_write (work : PageMemory) (p : Z) (value : nat) :
    PageMemory :=
  fun key offset =>
    if (Z.eqb key (page_key p) && Z.eqb offset (page_offset p))%bool
    then value else work key offset.

Lemma page_read_write_here :
  forall work p value, page_read (page_write work p value) p = value.
Proof.
  intros work p value. unfold page_read, page_write.
  now rewrite !Z.eqb_refl.
Qed.

Lemma page_read_write_elsewhere :
  forall work p q value, q <> p ->
    page_read (page_write work p value) q = page_read work q.
Proof.
  intros work p q value Hneq.
  unfold page_read, page_write.
  destruct ((Z.eqb (page_key q) (page_key p) &&
             Z.eqb (page_offset q) (page_offset p))%bool) eqn:Hmatch;
    [| reflexivity].
  apply andb_true_iff in Hmatch as [Hkey Hoff].
  apply Z.eqb_eq in Hkey.
  apply Z.eqb_eq in Hoff.
  exfalso. apply Hneq.
  now apply page_coordinates_injective.
Qed.

Definition page_refines (work : PageMemory) (memory : Z -> nat) : Prop :=
  forall p, page_read work p = memory p.

Definition embed_pages (memory : Z -> nat) : PageMemory :=
  fun key offset => memory (key * page_size + offset).

Lemma embed_pages_refines :
  forall memory, page_refines (embed_pages memory) memory.
Proof.
  intros memory p. unfold page_read, embed_pages.
  now rewrite page_join.
Qed.

Lemma page_write_refines :
  forall work memory p value,
    page_refines work memory ->
    page_refines (page_write work p value)
                 (write_at memory p value).
Proof.
  intros work memory p value Hread q.
  destruct (Z.eq_dec q p) as [Heq | Hneq].
  - subst q. rewrite page_read_write_here, write_at_head.
    reflexivity.
  - rewrite page_read_write_elsewhere by exact Hneq.
    rewrite write_at_frame by exact Hneq.
    exact (Hread q).
Qed.

Record PagedConfig := {
  p_description : list nat;
  p_state : nat;
  p_head : Z;
  p_work : PageMemory;
  p_halted : bool
}.

Definition signed64_valid (x : Z) : bool :=
  (signed64_min <=? x) && (x <=? signed64_max).

(** Post-write overflow handling matches UniversalTuringMachine::step:
    a failed head addition preserves the old head, commits the write/state,
    and halts.  Description bytes cannot be modified by a working write. *)
Definition paged_step (c : PagedConfig) : PagedConfig :=
  if p_halted c then c
  else
    match chart_scan_bytes (p_state c) (page_read (p_work c) (p_head c))
                           (p_description c) with
    | None =>
        {| p_description := p_description c;
           p_state := p_state c;
           p_head := p_head c;
           p_work := p_work c;
           p_halted := true |}
    | Some e =>
        let next := p_head c + e_move e in
        {| p_description := p_description c;
           p_state := e_to e;
           p_head := if signed64_valid next then next else p_head c;
           p_work := page_write (p_work c) (p_head c) (e_write e);
           p_halted := if signed64_valid next then e_halt e else true |}
    end.

Fixpoint paged_run (fuel : nat) (c : PagedConfig) : PagedConfig :=
  match fuel with
  | O => c
  | S n => if p_halted c then c else paged_run n (paged_step c)
  end.

Definition paged_refines (c : PagedConfig) (a : AddressConfig) : Prop :=
  p_description c = chart_image /\
  p_state c = a_state a /\
  p_head c = a_head a /\
  p_halted c = a_halted a /\
  page_refines (p_work c) (a_tape a).

Definition embed_paged (a : AddressConfig) : PagedConfig :=
  {| p_description := chart_image;
     p_state := a_state a;
     p_head := a_head a;
     p_work := embed_pages (a_tape a);
     p_halted := a_halted a |}.

Lemma embed_paged_refines :
  forall a, paged_refines (embed_paged a) a.
Proof.
  intro a. unfold paged_refines, embed_paged; simpl.
  repeat split; try reflexivity.
  apply embed_pages_refines.
Qed.

Lemma paged_lookup_refines :
  forall c a,
    paged_refines c a ->
    chart_scan_bytes (p_state c) (page_read (p_work c) (p_head c))
                     (p_description c) =
    find_entry (a_state a) (a_tape a (a_head a)).
Proof.
  intros c a [Hdesc [Hstate [Hhead [_ Hwork]]]].
  rewrite Hdesc, Hstate, Hhead, Hwork.
  change (chart_scan (a_state a) (a_tape a (a_head a)) =
          find_entry (a_state a) (a_tape a (a_head a))).
  rewrite chart_scan_agrees_all.
  symmetry. apply find_entry_scan_all.
Qed.

Lemma signed64_valid_if :
  forall x, signed64_min <= x <= signed64_max ->
    signed64_valid x = true.
Proof.
  intros x [Hlo Hhi]. unfold signed64_valid.
  apply andb_true_iff. split; apply Z.leb_le; lia.
Qed.

(** A one-step simulation, requiring exactly the local head margin which
    rules out overflow for the three allowed Minsky movements. *)
Theorem paged_step_refines :
  forall c a,
    paged_refines c a ->
    signed64_min + 1 <= a_head a <= signed64_max - 1 ->
    paged_refines (paged_step c) (address_step_indexed a).
Proof.
  intros c a Href Hmargin.
  pose proof (paged_lookup_refines c a Href) as Hlookup.
  destruct Href as [Hdesc [Hstate [Hhead [Hhalt Hwork]]]].
  unfold paged_step, address_step_indexed, address_step_with.
  rewrite Hhalt.
  destruct (a_halted a) eqn:Ha.
  - unfold paged_refines; simpl.
    repeat split; try assumption; reflexivity.
  - rewrite Hlookup.
    destruct (find_entry (a_state a) (a_tape a (a_head a)))
      as [e |] eqn:He.
    + pose proof (find_entry_move_allowed _ _ _ He) as Hmove.
      assert (Hvalid : signed64_valid (p_head c + e_move e) = true).
      { apply signed64_valid_if. rewrite Hhead.
        destruct Hmove as [-> | [-> | ->]]; lia. }
      rewrite Hvalid.
      unfold paged_refines; simpl.
      repeat split; try assumption; try reflexivity; try lia.
      now apply page_write_refines.
    + unfold paged_refines; simpl.
      repeat split; try assumption; reflexivity.
Qed.

Theorem paged_step_description_immutable :
  forall c, p_description (paged_step c) = p_description c.
Proof.
  intros [desc state head work halted].
  unfold paged_step; simpl.
  destruct halted; [reflexivity |].
  destruct (chart_scan_bytes state (page_read work head) desc)
    as [e|]; [destruct (signed64_valid (head + e_move e))|];
    reflexivity.
Qed.

Theorem paged_run_description_immutable :
  forall fuel c, p_description (paged_run fuel c) = p_description c.
Proof.
  induction fuel as [|n IH]; intro c; simpl.
  - reflexivity.
  - destruct (p_halted c); [reflexivity |].
    rewrite IH. apply paged_step_description_immutable.
Qed.

(** Full finite-run simulation under a fuel-sized initial margin.  The
    margin is symmetric only because all table movements are in {-1,0,1}.
    No description/tape separation condition is needed: they are distinct
    fields and description immutability is proved above. *)
Theorem paged_run_refines :
  forall fuel c a,
    paged_refines c a ->
    signed64_min + Z.of_nat fuel <= a_head a <=
      signed64_max - Z.of_nat fuel ->
    paged_refines (paged_run fuel c)
                  (address_run fuel address_step_indexed a).
Proof.
  induction fuel as [|n IH]; intros c a Href Hmargin; simpl.
  - exact Href.
  - destruct (a_halted a) eqn:Ha.
    + destruct Href as [Hd [Hs [Hh [Hhalt Hwork]]]].
      assert (Hp : p_halted c = true).
      { rewrite Hhalt. exact Ha. }
      rewrite Hp. repeat split; assumption.
    + assert (Hnative : p_halted c = false).
      { destruct Href as [_ [_ [_ [Hhalt _]]]].
        rewrite Hhalt. exact Ha. }
      rewrite Hnative.
      assert (Hstep : paged_refines (paged_step c)
                             (address_step_indexed a)).
      { apply paged_step_refines; [exact Href |].
        replace (Z.of_nat (S n)) with (Z.of_nat n + 1) in Hmargin
          by lia. lia. }
      apply IH; [exact Hstep |].
      pose proof (indexed_step_head_delta a) as Hdelta.
      replace (Z.of_nat (S n)) with (Z.of_nat n + 1) in Hmargin
        by lia.
      lia.
Qed.

Corollary any_address_run_has_paged_refinement :
  forall fuel a,
    signed64_min + Z.of_nat fuel <= a_head a <=
      signed64_max - Z.of_nat fuel ->
    paged_refines (paged_run fuel (embed_paged a))
                  (address_run fuel address_step_indexed a).
Proof.
  intros fuel a Hbound.
  apply paged_run_refines; [apply embed_paged_refines | exact Hbound].
Qed.

Print Assumptions page_coordinates_injective.
Print Assumptions page_write_refines.
Print Assumptions paged_step_refines.
Print Assumptions paged_run_refines.
Print Assumptions paged_run_description_immutable.
