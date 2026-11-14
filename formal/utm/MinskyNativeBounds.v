(** * Bounded native-address safety envelope for the Minsky chart

    The symbolic tape uses unbounded [Z] coordinates.  The current native
    implementation instead computes a signed 64-bit working address by
    adding [1048576] to the head, and stores description bytes starting at
    address zero.  This module establishes precise, checkable conditions
    under which a FINITE symbolic execution stays in the representable and
    non-aliasing region of that native layout.

    The conditions are hypotheses, not runtime invariants established for
    every C++ execution.  In particular these results do not prove native
    allocation, integer casts, page indexing, or concrete universality.
*)

From Coq Require Import Arith ZArith Lia.
From NaNLM Require Import MinskyTable MinskyAddressRefinement
  MinskyChartEncoding.
Open Scope Z_scope.

Definition signed64_min : Z := -9223372036854775808.
Definition signed64_max : Z :=  9223372036854775807.

(** Offset 1 is reserved, so count 0 still occupies addresses 0 and 1. *)
Definition description_end (record_count : nat) : Z :=
  2 + 6 * Z.of_nat record_count.

Lemma description_end_bounded :
  forall record_count, (record_count <= 255)%nat ->
    2 <= description_end record_count <= 1532.
Proof.
  intros record_count Hcount.
  unfold description_end.
  assert (Z.of_nat record_count <= 255) by lia.
  lia.
Qed.

(** The exact alias interval for ANY admitted native description length;
    the older fixed interval [-1048576,-1047470) is its 184-row instance. *)
Theorem working_address_alias_iff :
  forall record_count head,
    (0 <= working_chart_address head < description_end record_count) <->
    (-1048576 <= head < description_end record_count - 1048576).
Proof.
  intros record_count head.
  unfold working_chart_address, description_end.
  lia.
Qed.

Corollary minsky_184_alias_interval :
  forall head,
    (0 <= working_chart_address head < description_end 184) <->
    (-1048576 <= head < -1047470).
Proof.
  intro head.
  rewrite working_address_alias_iff.
  unfold description_end.
  simpl.
  lia.
Qed.

(** Every canonical transition moves the head by at most one cell,
    including a halting transition.  Missing entries and already-halted
    configurations leave the head unchanged. *)
Lemma indexed_step_head_delta :
  forall c,
    a_head c - 1 <= a_head (address_step_indexed c) <= a_head c + 1.
Proof.
  intro c.
  unfold address_step_indexed, address_step_with.
  destruct (a_halted c); simpl; [lia |].
  destruct (find_entry (a_state c) (a_tape c (a_head c)))
    as [e|] eqn:Hentry; simpl; [|lia].
  pose proof (find_entry_move_allowed _ _ _ Hentry) as Hmove.
  destruct Hmove as [Hmove | [Hmove | Hmove]];
    rewrite Hmove; lia.
Qed.

(** This inductive envelope covers EVERY symbolic initial configuration,
    not only the known 100-step test trace.  A halt can only reduce drift. *)
Theorem indexed_run_head_envelope :
  forall fuel c,
    a_head c - Z.of_nat fuel <=
      a_head (address_run fuel address_step_indexed c) <=
    a_head c + Z.of_nat fuel.
Proof.
  induction fuel as [|n IH]; intro c.
  - cbn [address_run]. lia.
  - replace (Z.of_nat (S n)) with (Z.of_nat n + 1) by lia.
    cbn [address_run].
    destruct (a_halted c); [lia |].
    pose proof (indexed_step_head_delta c) as Hstep.
    specialize (IH (address_step_indexed c)).
    lia.
Qed.

(** A single native head is safe if both head and working address fit in
    int64 and the work address is above the exclusive description end. *)
Definition native_safe_at (record_count : nat) (head : Z) : Prop :=
  signed64_min <= head <= signed64_max /\
  signed64_min <= working_chart_address head <= signed64_max /\
  description_end record_count <= working_chart_address head.

(** Sufficient conditions for a WHOLE bounded execution.  An initial head
    with [fuel] cells of margin on either side keeps every prefix inside
    int64; the lower guard separates all work accesses from the immutable
    description.  This intentionally does not assume a global run bound. *)
Theorem native_safe_for_every_prefix :
  forall fuel record_count c i,
    (record_count <= 255)%nat ->
    (i <= fuel)%nat ->
    signed64_min + Z.of_nat fuel <= a_head c ->
    a_head c + Z.of_nat fuel <= signed64_max - 1048576 ->
    description_end record_count <=
      1048576 + a_head c - Z.of_nat fuel ->
    native_safe_at record_count
      (a_head (address_run i address_step_indexed c)).
Proof.
  intros fuel record_count c i Hcount Hi Hmin Hmax Hsep.
  pose proof (indexed_run_head_envelope i c) as Hrun.
  assert (HiZ : Z.of_nat i <= Z.of_nat fuel) by lia.
  unfold native_safe_at, working_chart_address,
    signed64_min, signed64_max in *.
  repeat split; lia.
Qed.

(** The published 100-step execution begins at head 38.  Even though the
    theorem above is general, these numerical margins provide a concrete
    Coq-checked non-alias and no-overflow certificate for EVERY prefix. *)
Corollary published_trace_100_native_safe :
  forall i, (i <= 100)%nat ->
    native_safe_at 184
      (a_head (address_run i address_step_indexed initial_address_config)).
Proof.
  intros i Hi.
  eapply (native_safe_for_every_prefix 100 184 initial_address_config i).
  - lia.
  - exact Hi.
  - simpl. unfold signed64_min. lia.
  - simpl. unfold signed64_max. lia.
  - simpl. unfold description_end. lia.
Qed.

Print Assumptions working_address_alias_iff.
Print Assumptions indexed_run_head_envelope.
Print Assumptions native_safe_for_every_prefix.
Print Assumptions published_trace_100_native_safe.
