(** * Frame lemmas for the table-memory invariant

    A native step writes only the tape cell [tape_addr] and the three
    control cells [action_head_addr], [action_state_addr] and
    [action_halt_addr] (see [action_run]).  This module isolates the
    memory-frame reasoning needed to show that such a step preserves

      - [table_mem_at] over the encoded program table, and
      - the tape-base cell [tape_base_addr].

    Nothing here depends on how the table or the tape are laid out: all
    separation conditions are explicit hypotheses.  The [*_span]
    corollaries turn them into the interval side conditions that a
    concrete layout proof will discharge. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionRun MinskyNaN16StepEntrySpec MinskyNaN16Prelude.

Open Scope nat_scope.

(** ** Writing a single cell outside the table region *)

Lemma table_mem_at_set_mem_outside :
  forall (start : nat) (table : list (list nat)) (m : Mem) (a v : nat),
    table_mem_at start table m ->
    (forall i f, i < length table ->
       f < length (nth i table []) -> start + 8 * i + f <> a) ->
    table_mem_at start table (set_mem m a v).
Proof.
  intros start table m a v Htab Hdis i f Hi Hf.
  unfold table_mem_at in Htab.
  rewrite (set_mem_neq m a v (start + 8 * i + f) (Hdis i f Hi Hf)).
  apply Htab; assumption.
Qed.

(** Pointwise-equal memories agree on the table region.  This is the
    bridge used to transfer the invariant through [action_run]. *)

Lemma table_mem_at_mem_eq :
  forall (start : nat) (table : list (list nat)) (m m' : Mem),
    (forall k, m k = m' k) ->
    table_mem_at start table m ->
    table_mem_at start table m'.
Proof.
  intros start table m m' Heq Htab i f Hi Hf.
  unfold table_mem_at in Htab.
  rewrite <- (Heq (start + 8 * i + f)).
  apply Htab; assumption.
Qed.

(** ** Region-based side conditions

    In the concrete layout every row has at most eight cells, so the
    table occupies the half-open interval [start, start + 8 * length
    table).  An address outside that interval is outside every cell. *)

Lemma table_cell_outside_span :
  forall (start : nat) (table : list (list nat)) (a i f : nat),
    (forall i, i < length table -> length (nth i table []) <= 8) ->
    i < length table ->
    f < length (nth i table []) ->
    (a < start \/ start + 8 * length table <= a) ->
    start + 8 * i + f <> a.
Proof.
  intros start table a i f Hrow8 Hi Hf Hout Heq.
  specialize (Hrow8 i Hi).
  assert (Hf8 : f < 8) by lia.
  destruct Hout as [Hlow | Hhigh]; lia.
Qed.

Corollary table_mem_at_set_mem_span :
  forall (start : nat) (table : list (list nat)) (m : Mem) (a v : nat),
    table_mem_at start table m ->
    (forall i, i < length table -> length (nth i table []) <= 8) ->
    (a < start \/ start + 8 * length table <= a) ->
    table_mem_at start table (set_mem m a v).
Proof.
  intros start table m a v Htab Hrows Hout.
  apply (table_mem_at_set_mem_outside start table m a v Htab).
  intros i f Hi Hf.
  exact (table_cell_outside_span start table a i f Hrows Hi Hf Hout).
Qed.

(** ** Preservation by the native action phase *)

Lemma table_mem_at_action_run :
  forall (start : nat) (table : list (list nat)) (m : Mem)
         (row_addr tape_addr head : nat) (row : list nat),
    table_mem_at start table m ->
    (forall i f, i < length table ->
       f < length (nth i table []) -> start + 8 * i + f <> tape_addr) ->
    (forall i f, i < length table ->
       f < length (nth i table []) -> start + 8 * i + f <> action_head_addr) ->
    (forall i f, i < length table ->
       f < length (nth i table []) -> start + 8 * i + f <> action_state_addr) ->
    (forall i f, i < length table ->
       f < length (nth i table []) -> start + 8 * i + f <> action_halt_addr) ->
    table_mem_at start table
      (snd (action_run row_addr tape_addr head m row)).
Proof.
  intros start table m row_addr tape_addr head row
    Htab Htape Hhead Hstate Hhalt i f Hi Hf.
  rewrite (action_run_frame row_addr tape_addr head m row
    (start + 8 * i + f) (Htape i f Hi Hf) (Hhead i f Hi Hf)
    (Hstate i f Hi Hf) (Hhalt i f Hi Hf)).
  apply Htab; assumption.
Qed.

Corollary table_mem_at_action_run_span :
  forall (start : nat) (table : list (list nat)) (m : Mem)
         (row_addr tape_addr head : nat) (row : list nat),
    table_mem_at start table m ->
    (forall i, i < length table -> length (nth i table []) <= 8) ->
    (tape_addr < start \/ start + 8 * length table <= tape_addr) ->
    (action_head_addr < start \/ start + 8 * length table <= action_head_addr) ->
    (action_state_addr < start \/ start + 8 * length table <= action_state_addr) ->
    (action_halt_addr < start \/ start + 8 * length table <= action_halt_addr) ->
    table_mem_at start table
      (snd (action_run row_addr tape_addr head m row)).
Proof.
  intros start table m row_addr tape_addr head row
    Htab Hrows Hout_tape Hout_head Hout_state Hout_halt.
  apply (table_mem_at_action_run start table m row_addr tape_addr head row
    Htab).
  - intros i f Hi Hf.
    exact (table_cell_outside_span start table tape_addr i f
      Hrows Hi Hf Hout_tape).
  - intros i f Hi Hf.
    exact (table_cell_outside_span start table action_head_addr i f
      Hrows Hi Hf Hout_head).
  - intros i f Hi Hf.
    exact (table_cell_outside_span start table action_state_addr i f
      Hrows Hi Hf Hout_state).
  - intros i f Hi Hf.
    exact (table_cell_outside_span start table action_halt_addr i f
      Hrows Hi Hf Hout_halt).
Qed.

(** ** Preservation of the tape-base cell *)

Lemma set_mem_tape_base :
  forall (m : Mem) (a v : nat),
    a <> tape_base_addr ->
    set_mem m a v tape_base_addr = m tape_base_addr.
Proof.
  intros m a v H. apply set_mem_neq. symmetry. exact H.
Qed.

Lemma action_run_tape_base :
  forall (row_addr tape_addr head : nat) (m : Mem) (row : list nat),
    tape_base_addr <> tape_addr ->
    tape_base_addr <> action_head_addr ->
    tape_base_addr <> action_state_addr ->
    tape_base_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) tape_base_addr =
      m tape_base_addr.
Proof.
  intros. apply action_run_frame; assumption.
Qed.
