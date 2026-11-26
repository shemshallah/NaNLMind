(** * Literal executor to Coq VM: static memory bridge

    This file starts the literal-image -> Coq-VM refinement of
    [UNIVERSALITY_TASK_GRAPH] item 1.  The full bridge needs a general
    executor simulation and a loader semantics; this module proves the
    input-independent half:

      the literal machine's actual memory [lp_mem lp_reset], read through
      [mem_get], carries exactly the 184x8 table that the Coq VM's
      [nan16_addr_mem] exposes, for every window [K] and every source
      configuration [c].

    It also connects the literal tape-base and control cells to the same
    memory model.  No C or Python is involved; this is raw Coq.

    The table identity is not a re-computation of [fixture_table]: it is
    routed through [literal_table_slice_eq_fixture], which ties the image
    words at [104..1575] to [fixture_table], and through
    [nan16_addr_mem_table], which ties [fixture_table] to the VM memory. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.
Open Scope nat_scope.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralMachine
  MinskyNaN16LiteralDecode MinskyNaN16LiteralImage
  MinskyNaN16Action MinskyNaN16Prelude
  MinskyNaN16RunConcrete MinskyNaN16Universality.

(** [lp_reset]'s memory is the concrete reset memory, definitionally. *)
Lemma mem_get_lp_reset :
  forall a, mem_get (lp_mem lp_reset) a = mem_get reset_mem a.
Proof. intro a. reflexivity. Qed.

(** ** A list helper for the image-side table rows *)

Lemma nth_map_seq_lt :
  forall (A : Type) (f : nat -> A) (start m n : nat) (d : A),
    n < m ->
    nth n (map f (seq start m)) d = f (start + n).
Proof.
  intros A f start m n d H.
  revert start m H.
  induction n as [|n IH]; intros start m H.
  - destruct m as [|m]; [lia|].
    simpl. replace (start + 0) with start by lia. reflexivity.
  - destruct m as [|m]; [lia|].
    simpl. replace (start + S n) with (S start + n) by lia.
    apply IH. lia.
Qed.

(** Row [i] of the literal table slice, extracted from the computed
    [literal_table_rows] value. *)
Lemma nth_literal_table_row :
  forall i,
    i < List.length fixture_table ->
    nth i literal_table_rows [] =
      map (fun f =>
             payload_word
               (literal_word_at (fixture_table_base + 8 * i + f)))
          (seq 0 8).
Proof.
  intros i Hi.
  unfold literal_table_rows.
  rewrite (nth_map_seq_lt (list nat)
    (fun i0 =>
       map (fun f =>
              payload_word
                (literal_word_at (fixture_table_base + 8 * i0 + f)))
           (seq 0 8))
    0 (List.length fixture_table) i []) by exact Hi.
  replace (0 + i) with i by lia.
  reflexivity.
Qed.

(** The payload of the literal word at table row [i], field [f] is the
    corresponding [fixture_table] entry. *)
Lemma literal_table_payload_row :
  forall i f,
    i < List.length fixture_table ->
    f < 8 ->
    payload_word
      (literal_word_at (fixture_table_base + 8 * i + f)) =
    nth f (nth i fixture_table []) 0.
Proof.
  intros i f Hi Hf.
  pose proof (nth_literal_table_row i Hi) as Hrow.
  rewrite literal_table_slice_eq_fixture in Hrow.
  rewrite Hrow.
  rewrite (nth_map_seq_lt nat
    (fun f0 =>
       payload_word
         (literal_word_at (fixture_table_base + 8 * i + f0)))
    0 8 f 0%nat) by exact Hf.
  replace (0 + f) with f by lia.
  reflexivity.
Qed.

(** ** The VM table is the literal executor's table *)

Theorem literal_table_matches_nan16_addr_mem :
  forall K c i f,
    i < List.length fixture_table ->
    f < 8 ->
    nan16_addr_mem K c (fixture_table_base + 8 * i + f) =
    payload_word
      (mem_get (lp_mem lp_reset) (fixture_table_base + 8 * i + f)).
Proof.
  intros K c i f Hi Hf.
  assert (Hrow : List.length (nth i fixture_table []) = 8).
  { exact (@proj1 _ _
      (@Forall_nth (list nat) (fun r => List.length r = 8) fixture_table)
      fixture_table_rows8 i [] Hi). }
  assert (Hf' : f < List.length (nth i fixture_table [])) by lia.
  pose proof (nan16_addr_mem_table K c i f Hi Hf') as Htab.
  unfold table_mem_at in Htab.
  rewrite Htab.
  rewrite mem_get_lp_reset.
  assert (Hlt4366 : fixture_table_base + 8 * i + f < 4366).
  { pose proof (fixture_table_below_tape i f Hi Hf) as Hlt.
    unfold fixture_tape_base in Hlt. lia. }
  rewrite (mem_get_reset (fixture_table_base + 8 * i + f)) by exact Hlt4366.
  change (nth f (nth i fixture_table []) 0 =
          payload_word
            (literal_word_at (fixture_table_base + 8 * i + f))).
  symmetry. apply literal_table_payload_row; assumption.
Qed.

(** ** Control and tape-base cells *)

Lemma literal_memory_eq_image :
  forall a, a < 4366 ->
    mem_get (lp_mem lp_reset) a = literal_word_at a.
Proof.
  intros a Ha.
  rewrite mem_get_lp_reset.
  unfold literal_word_at.
  apply mem_get_reset. exact Ha.
Qed.

Theorem literal_control_cells_payload :
  payload_word (mem_get (lp_mem lp_reset) 99) = 4096 /\
  payload_word (mem_get (lp_mem lp_reset) 100) = 0 /\
  payload_word (mem_get (lp_mem lp_reset) 101) = 0 /\
  payload_word (mem_get (lp_mem lp_reset) 102) = 0.
Proof.
  destruct literal_data_cells as (H99 & H100 & H101 & H102 & H103).
  repeat split.
Qed.

Theorem literal_tape_base_matches_nan16_addr_mem :
  forall K c,
    nan16_addr_mem K c tape_base_addr =
    payload_word (mem_get (lp_mem lp_reset) tape_base_addr).
Proof.
  intros K c.
  vm_compute.
  reflexivity.
Qed.

(** ** Assumption audit *)

Print Assumptions literal_table_matches_nan16_addr_mem.
Print Assumptions literal_control_cells_payload.
Print Assumptions literal_tape_base_matches_nan16_addr_mem.

(** ** Executor state relation *)

(** The cached literal machine [LPState] and the older one-step machine
    [LState] carry the same architectural state, differing only in
    representation: [LPState] stores binary [N] registers and a
    five-block [MemP], while [LState] stores [nat] registers and a total
    memory function.  [lp_to_LState] is the pointwise view used by the
    existing [R] relation and one-step lemmas. *)

Definition lp_to_LState (L : LPState) : LState :=
  {| l_pc := lp_pc L;
     l_reg := fun i => N.to_nat (lget_regN (lp_reg L) i);
     l_mem := fun a => mem_get (lp_mem L) a;
     l_k := lp_k L;
     l_halted := lp_halted L |}.

Definition vm_of_lp (L : LPState) : VM :=
  vm_reset (fun a => mem_get (lp_mem L) a).

Definition Rlp (L : LPState) (vm : VM) : Prop :=
  R (lp_to_LState L) vm.

Lemma nth_repeat_zero :
  forall n k, nth n (repeat 0%N k) 0%N = 0%N.
Proof.
  intros n. induction n as [|n IH]; intros k.
  - destruct k; cbn; reflexivity.
  - destruct k; cbn; [reflexivity|apply IH].
Qed.

Lemma lget_regN_regs0 :
  forall i, lget_regN regs0 i = 0%N.
Proof.
  intro i. unfold lget_regN, regs0. apply nth_repeat_zero.
Qed.

