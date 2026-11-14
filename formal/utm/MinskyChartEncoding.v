(** * Concrete six-byte chart description refinement

    [src/universal_tm.cpp] stores each transition as six byte values at
    address [2 + 6*i], in this order: from, read, write, move+1, to, halt.
    The count occupies address 0.  The following model uses exactly those
    byte positions and checks the entire canonical 184-entry image.

    The result is a byte-layout-to-abstract-interpreter refinement, not a
    proof of the compiler, allocation failures, or all C++ integer casts.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable MinskyAddressRefinement.

Definition encode_chart_row (e : Entry) : list nat :=
  [e_from e; e_read e; e_write e;
   Z.to_nat (e_move e + 1); e_to e;
   if e_halt e then 1%nat else 0%nat].

Definition decode_chart_row (row : list nat) : option Entry :=
  match row with
  | [q; s; w; m; dest; stop] =>
      Some {| e_from := q; e_read := s; e_write := w;
              e_move := Z.of_nat m - 1; e_to := dest;
              e_halt := negb (Nat.eqb stop 0) |}
  | _ => None
  end.

(** Encoding [move + 1] is reversible for every C++-accepted movement.
    This lemma does not rely on the particular Minsky table. *)
Lemma chart_row_roundtrip :
  forall e, -1 <= e_move e ->
    decode_chart_row (encode_chart_row e) = Some e.
Proof.
  intros [q s w m dest stop] Hmove.
  unfold decode_chart_row, encode_chart_row; simpl.
  rewrite Z2Nat.id by lia.
  replace (m + 1 - 1) with m by lia.
  destruct stop; reflexivity.
Qed.

(** The flat image begins at C++ [kEntryBase = 2].  Unallocated positions
    read as blank = 2 in [TuringTape::read]. *)
Definition chart_image : list nat :=
  concat (map encode_chart_row minsky_entries).

Definition chart_byte (position : nat) : nat :=
  if Nat.eqb position 0 then length minsky_entries
  else if Nat.eqb position 1 then blank
  else nth (position - 2)%nat chart_image blank.

Definition chart_row_at (i : nat) : option Entry :=
  let p := (2 + 6 * i)%nat in
  decode_chart_row
    [chart_byte p; chart_byte (p+1)%nat;
     chart_byte (p+2)%nat; chart_byte (p+3)%nat;
     chart_byte (p+4)%nat; chart_byte (p+5)%nat].

Definition chart_lookup (q s : nat) : option Entry :=
  if (Nat.ltb q 23 && Nat.ltb s 8)%bool
  then chart_row_at (q * 8 + s)%nat
  else None.

Definition chart_lookup_eqb (q s : nat) : bool :=
  match chart_lookup q s, find_entry q s with
  | None, None => true
  | Some a, Some b => entry_eqb a b
  | _, _ => false
  end.

Definition chart_all_rows_agree : bool :=
  forallb (fun q => forallb (chart_lookup_eqb q) (seq 0 8)) (seq 0 23).

(** This independent finite certificate checks all 1,104 transition bytes,
    including the signed-move encoding and halting flag, against the
    originally transcribed 184 transition records. *)
Theorem chart_all_rows_checked : chart_all_rows_agree = true.
Proof. vm_compute. reflexivity. Qed.

Lemma chart_lookup_eqb_sound :
  forall q s, chart_lookup_eqb q s = true ->
    chart_lookup q s = find_entry q s.
Proof.
  intros q s H.
  unfold chart_lookup_eqb in H.
  destruct (chart_lookup q s) as [a|] eqn:Ha;
    destruct (find_entry q s) as [b|] eqn:Hb;
    try discriminate; try reflexivity.
  apply entry_eqb_sound in H. subst. reflexivity.
Qed.

Lemma chart_lookup_valid :
  forall q s, (q < 23)%nat -> (s < 8)%nat ->
    chart_lookup q s = find_entry q s.
Proof.
  intros q s Hq Hs.
  assert (Hqin : In q (seq 0 23)) by (apply in_seq; lia).
  assert (Hsin : In s (seq 0 8)) by (apply in_seq; lia).
  pose proof (MinskyTable.forallb_forall _ _ _
    chart_all_rows_checked q Hqin) as Hqok.
  pose proof (MinskyTable.forallb_forall _ _ _
    Hqok s Hsin) as Hsok.
  now apply chart_lookup_eqb_sound.
Qed.

(** Guards outside the table prevent [q,8] aliasing [q+1,0]. *)
Theorem chart_lookup_agrees_all :
  forall q s, chart_lookup q s = find_entry q s.
Proof.
  intros q s.
  destruct (Nat.ltb q 23) eqn:Hq;
    destruct (Nat.ltb s 8) eqn:Hs.
  - apply Nat.ltb_lt in Hq. apply Nat.ltb_lt in Hs.
    now apply chart_lookup_valid.
  - unfold chart_lookup, find_entry. rewrite Hq, Hs. reflexivity.
  - unfold chart_lookup, find_entry. rewrite Hq. reflexivity.
  - unfold chart_lookup, find_entry. rewrite Hq. reflexivity.
Qed.

Definition chart_address_step : AddressConfig -> AddressConfig :=
  address_step_with chart_lookup.

Theorem chart_address_step_refines :
  forall c, chart_address_step c = address_step_indexed c.
Proof.
  intros c. unfold chart_address_step, address_step_indexed,
    address_step_with.
  destruct (a_halted c); [reflexivity |].
  rewrite chart_lookup_agrees_all. reflexivity.
Qed.

Theorem chart_address_run_refines :
  forall fuel c,
    address_run fuel chart_address_step c =
    address_run fuel address_step_indexed c.
Proof.
  induction fuel as [|fuel IH]; intros c; simpl.
  - reflexivity.
  - destruct (a_halted c); [reflexivity |].
    rewrite chart_address_step_refines. apply IH.
Qed.

Theorem zipper_chart_run_bisim :
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run fuel zip) (address_run fuel chart_address_step addr).
Proof.
  intros fuel zip addr H.
  rewrite chart_address_run_refines.
  now apply zipper_address_run_bisim.
Qed.

(** The shared C++ tape is also used for simulated cells at
    [kWorkingTapeBase + head].  The unbounded signed-address semantics
    cannot assert that these regions stay distinct without an invariant.
    This theorem isolates the EXACT alias interval for the description
    slots 0..1105, including the count at address 0. *)
Definition working_chart_address (head : Z) : Z := 1048576 + head.

Theorem working_address_hits_description_iff :
  forall head,
    (0 <= working_chart_address head < 1106) <->
    (-1048576 <= head < -1047470).
Proof.
  intros head. unfold working_chart_address. lia.
Qed.

Corollary working_address_safe_above_description :
  forall head,
    -1047470 <= head -> 1106 <= working_chart_address head.
Proof.
  intros head H. unfold working_chart_address. lia.
Qed.

Print Assumptions chart_all_rows_checked.
Print Assumptions chart_lookup_agrees_all.
Print Assumptions chart_address_step_refines.
Print Assumptions chart_address_run_refines.
Print Assumptions zipper_chart_run_bisim.
Print Assumptions working_address_hits_description_iff.
