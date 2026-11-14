(** * Linear scan of the concrete six-byte Minsky description

    The native UniversalTuringMachine::step scans six-byte rows in order,
    comparing the first two bytes before interpreting write/move/to/halt.
    MinskyChartEncoding establishes indexed chart-byte lookup.  This file
    separately models the actual sequential scan over the flattened byte
    image, including first-match behavior, and proves that it agrees with
    the canonical abstract scan for every state and symbol.

    This establishes the pure byte-list decoding/scan portion of the C++
    logic, not correctness of native page allocation, mutation, arithmetic,
    compiler output, or physical separation of description and tape.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable
  MinskyAddressRefinement MinskyChartEncoding.

(** Each recursive call advances by exactly one six-byte row.  The
    pattern's tail is structurally smaller, so this is a total scanner
    even for truncated or malformed byte lists. *)
Fixpoint chart_scan_bytes (q s : nat) (bytes : list nat) : option Entry :=
  match bytes with
  | from :: read_symbol :: write_symbol :: direction :: target :: stop :: rest =>
      match decode_chart_row
        [from; read_symbol; write_symbol; direction; target; stop] with
      | Some e =>
          if (Nat.eqb (e_from e) q && Nat.eqb (e_read e) s)%bool
          then Some e
          else chart_scan_bytes q s rest
      | None => None
      end
  | _ => None
  end.

Lemma chart_scan_bytes_cons :
  forall q s e tail,
    -1 <= e_move e ->
    chart_scan_bytes q s (encode_chart_row e ++ tail) =
      if (Nat.eqb (e_from e) q && Nat.eqb (e_read e) s)%bool
      then Some e else chart_scan_bytes q s tail.
Proof.
  intros q s [f r w m dest stop] tail Hmove.
  simpl in Hmove.
  assert (Hnonnegative : (0 <= m + 1)%Z) by lia.
  unfold encode_chart_row.
  simpl.
  rewrite (Z2Nat.id (m + 1)) by exact Hnonnegative.
  replace (m + 1 - 1) with m by lia.
  destruct stop; reflexivity.
Qed.

(** This is a generic refinement statement: for ANY finite transition
    sequence whose movement encodings are representable, decoding the
    concatenated bytes and scanning them has the same first-match result
    as scanning the transition records directly, including duplicate keys. *)
Theorem chart_scan_bytes_matches_rows :
  forall rows q s,
    (forall e, In e rows -> -1 <= e_move e) ->
    chart_scan_bytes q s (concat (map encode_chart_row rows)) =
    scan_entry q s rows.
Proof.
  induction rows as [|e rest IH]; intros q s Hmoves.
  - reflexivity.
  - simpl.
    rewrite chart_scan_bytes_cons.
    + destruct (Nat.eqb (e_from e) q && Nat.eqb (e_read e) s)%bool.
      * reflexivity.
      * apply IH. intros e' Hin. apply Hmoves. now right.
    + apply Hmoves. now left.
Qed.

Definition minsky_rows_encodable : bool :=
  forallb (fun e => Z.leb (-1) (e_move e)) minsky_entries.

Theorem minsky_rows_encodable_checked : minsky_rows_encodable = true.
Proof. vm_compute. reflexivity. Qed.

Lemma minsky_rows_move_safe :
  forall e, In e minsky_entries -> -1 <= e_move e.
Proof.
  intros e Hin.
  pose proof (MinskyTable.forallb_forall _ _ _
    minsky_rows_encodable_checked e Hin) as H.
  now apply Z.leb_le in H.
Qed.

Definition chart_scan (q s : nat) : option Entry :=
  chart_scan_bytes q s chart_image.

Theorem chart_scan_agrees_all :
  forall q s, chart_scan q s = scan_table q s.
Proof.
  intros q s. unfold chart_scan, chart_image, scan_table.
  apply chart_scan_bytes_matches_rows.
  exact minsky_rows_move_safe.
Qed.

(** Unlike the indexed-lookup proof, these correspondences start with the
    sequential six-byte decoder, as exercised by the native C++ loop. *)
Definition chart_scan_address_step : AddressConfig -> AddressConfig :=
  address_step_with chart_scan.

Theorem chart_scan_address_step_refines :
  forall c, chart_scan_address_step c = address_step_scanned c.
Proof.
  intro c. unfold chart_scan_address_step, address_step_scanned,
    address_step_with.
  destruct (a_halted c); [reflexivity |].
  rewrite chart_scan_agrees_all. reflexivity.
Qed.

Theorem chart_scan_address_run_refines :
  forall fuel c,
    address_run fuel chart_scan_address_step c =
    address_run fuel address_step_scanned c.
Proof.
  induction fuel as [|fuel IH]; intro c; simpl.
  - reflexivity.
  - destruct (a_halted c); [reflexivity |].
    rewrite chart_scan_address_step_refines. apply IH.
Qed.

Theorem zipper_chart_scan_run_bisim :
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run fuel zip)
      (address_run fuel chart_scan_address_step addr).
Proof.
  intros fuel zip addr H.
  rewrite chart_scan_address_run_refines.
  rewrite <- address_run_refines.
  now apply zipper_address_run_bisim.
Qed.

Print Assumptions chart_scan_bytes_matches_rows.
Print Assumptions chart_scan_agrees_all.
Print Assumptions chart_scan_address_run_refines.
Print Assumptions zipper_chart_scan_run_bisim.
