(** * A concrete inhabitant of the packaged running step

    The repaired [canonical_return_step_ok] record is not merely a
    conditional interface: the explicit witness below satisfies every
    field.  Its two state bits are [false; true], its action is
    [false; false], and its q5 rail is the single mark 2.

    This is a non-vacuity check for the running-step package.  It is not
    yet a source-machine configuration or a universality claim.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyCanonicalMatch MinskyCanonicalInstruction.

Definition canonical_return_witness : canonical_return_step :=
  {| crs_post := [5; 2];
     crs_pre := [];
     crs_bprev := false;
     crs_data := [];
     crs_data' := [0];
     crs_symbol := 2;
     crs_remaining := [];
     crs_prefix := [6; 0];
     crs_hit := true;
     crs_next_bit := false;
     crs_next_tail := [1; 0; 0; 1; 0];
     crs_q16map := [4];
     crs_bits := [false; true];
     crs_action_init := [false];
     crs_tbuffer := [];
     crs_bnext := false;
     crs_rest := [0];
     crs_s21 := 0;
     crs_rest21 := [5];
     crs_hpre := [5];
     crs_hhit := false;
     crs_hpost := [];
     crs_next_bit' := false;
     crs_next_tail' := [];
     crs_tail := [0; 0; 1; 0] |}.

Lemma canonical_return_witness_ok :
  canonical_return_step_ok canonical_return_witness.
Proof.
  unfold canonical_return_witness.
  constructor; vm_compute; auto 12.
Qed.

Theorem canonical_return_witness_run :
  run (canonical_return_step_clock canonical_return_witness)
      (canonical_return_step_start canonical_return_witness) =
  canonical_return_step_end canonical_return_witness.
Proof.
  apply canonical_return_step_run.
  apply canonical_return_witness_ok.
Qed.

Print Assumptions canonical_return_witness_ok.
Print Assumptions canonical_return_witness_run.

(** ** A one-row family with arbitrary source tape data

    The fixed witness above has empty data.  The same record pattern
    works for every left data list and every write bit; only the data
    shift changes.  This is a genuine running step for a fixed two-bit
    instruction with an arbitrary source tape suffix. *)

Definition canonical_witness_family
    (data : list nat) (bprev : bool) : canonical_return_step :=
  {| crs_post := [5; 2];
     crs_pre := [];
     crs_bprev := bprev;
     crs_data := data;
     crs_data' := data ++ [source_bit bprev];
     crs_symbol := 2;
     crs_remaining := [];
     crs_prefix := [6] ++ source_bit bprev :: rev data;
     crs_hit := true;
     crs_next_bit := false;
     crs_next_tail := [1; 0; 0; 1; 0];
     crs_q16map := [4];
     crs_bits := [false; true];
     crs_action_init := [false];
     crs_tbuffer := [];
     crs_bnext := false;
     crs_rest := [0];
     crs_s21 := 0;
     crs_rest21 := [5];
     crs_hpre := [5];
     crs_hhit := false;
     crs_hpost := [];
     crs_next_bit' := false;
     crs_next_tail' := [];
     crs_tail := [0; 0; 1; 0] |}.

Lemma rev_snoc_source_bit :
  forall (data : list nat) (bprev : bool),
    rev (data ++ [source_bit bprev]) = source_bit bprev :: rev data.
Proof.
  intros data bprev.
  rewrite rev_app_distr. cbn [rev]. reflexivity.
Qed.

Lemma canonical_witness_family_ok :
  forall data bprev,
    canonical_return_step_ok (canonical_witness_family data bprev).
Proof.
  intros data bprev.
  unfold canonical_witness_family.
  constructor.
  - cbn. reflexivity.
  - cbn. auto 12.
  - cbn. auto 12.
  - cbn. reflexivity.
  - cbn. rewrite rev_app_distr. cbn. reflexivity.
  - cbn. rewrite rev_app_distr. cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. auto 12.
  - cbn. auto 12.
  - cbn. auto 12.
  - cbn. auto 12.
Qed.

Theorem canonical_witness_family_run :
  forall data bprev,
    run (canonical_return_step_clock
           (canonical_witness_family data bprev))
        (canonical_return_step_start
           (canonical_witness_family data bprev)) =
    canonical_return_step_end
      (canonical_witness_family data bprev).
Proof.
  intros data bprev.
  apply canonical_return_step_run.
  apply canonical_witness_family_ok.
Qed.

Print Assumptions canonical_witness_family_ok.
Print Assumptions canonical_witness_family_run.
