(** * Concrete fixture closure for the NaN16 Minsky run refinement

    [MinskyNaN16RunClosed.v] reduces the whole run to two global layout
    facts about the current tape window:

      [table_control_ok table table_base]
      [tape_window_ok table table_base tbase window]

    This file discharges both facts for the concrete fixture of
    [mth/tests/mth_minsky_test.nas]:

      * the table is the literal 184x8 word block of that file, and
      * the tape base is the literal [4096] of [tbase: .word 4096]
        (the tape image itself is emitted at [.org 4096]).

    Then [vm_run_refines_window] is instantiated, so the only remaining
    hypothesis of the run-level theorem is [entry_ok] on the initial VM.

    ** Addresses

    The .nas label layout is

      tbase 99, state 100, head 101, halt 102, rlink 103, table 104,
      tape 4096,

    i.e. the five data cells are followed immediately by the table and
    the whole 1472-word table (104 + 8*184 = 1576) stays below the tape.

    The Coq VM abstracts the four data cells by the constants
    [action_head_addr = 300], [action_state_addr = 301],
    [action_halt_addr = 302], [tape_base_addr = 303] (see
    [MinskyNaN16Action.v]; the constants are parameters linked to the
    source layout by the transcription gate).  The model table must
    therefore avoid 300..302 and start above the control block.  Taking
    the first free address, [304], preserves the .nas ordering

      300..303   control cells
      304..1775  table        (304 + 8*184 = 1776)
      4096..     tape

    and the separation below is pure arithmetic on these numerals.  The
    choices are explicit constants, not assumptions. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyNaN16RunClosed MinskyNaN16Run
  MinskyNaN16StepOk MinskyNaN16VM MinskyNaN16Action MinskyNaN16Prelude
  MinskyNaN16StepSpec MinskyNaN16StepEntrySpec MinskyNaN16Words
  MinskyTableData MinskyChartEncoding.

(** ** Fixture addresses *)

Definition fixture_table_base : nat := 304.
Definition fixture_tape_base : nat := 4096.

(** ** The literal 184x8 table of [mth_minsky_test.nas] *)

Definition fixture_table : list (list nat) := [
  [0; 0; 2; 0; 2; 0; 0; 0];
  [0; 1; 3; 2; 3; 0; 0; 0];
  [0; 2; 2; 2; 0; 0; 0; 0];
  [0; 3; 3; 2; 0; 0; 0; 0];
  [0; 4; 4; 2; 0; 0; 0; 0];
  [0; 5; 5; 2; 0; 0; 0; 0];
  [0; 6; 6; 2; 0; 0; 0; 0];
  [0; 7; 7; 2; 0; 0; 0; 0];
  [1; 0; 0; 2; 1; 0; 0; 0];
  [1; 1; 1; 2; 1; 0; 0; 0];
  [1; 2; 0; 2; 0; 0; 0; 0];
  [1; 3; 1; 2; 4; 0; 0; 0];
  [1; 4; 4; 2; 6; 0; 0; 0];
  [1; 5; 5; 2; 1; 0; 0; 0];
  [1; 6; 6; 2; 1; 0; 0; 0];
  [1; 7; 7; 2; 1; 0; 0; 0];
  [2; 0; 0; 0; 2; 0; 0; 0];
  [2; 1; 1; 0; 2; 0; 0; 0];
  [2; 2; 2; 0; 2; 0; 0; 0];
  [2; 3; 3; 0; 2; 0; 0; 0];
  [2; 4; 4; 0; 2; 0; 0; 0];
  [2; 5; 5; 2; 1; 0; 0; 0];
  [2; 6; 6; 0; 2; 0; 0; 0];
  [2; 7; 7; 0; 2; 0; 0; 0];
  [3; 0; 0; 2; 3; 0; 0; 0];
  [3; 1; 1; 2; 3; 0; 0; 0];
  [3; 2; 2; 2; 3; 0; 0; 0];
  [3; 3; 3; 2; 3; 0; 0; 0];
  [3; 4; 4; 0; 5; 0; 0; 0];
  [3; 5; 5; 1; 0; 1; 0; 0];
  [3; 6; 6; 2; 3; 0; 0; 0];
  [3; 7; 7; 2; 3; 0; 0; 0];
  [4; 0; 2; 2; 3; 0; 0; 0];
  [4; 1; 3; 0; 2; 0; 0; 0];
  [4; 2; 2; 2; 4; 0; 0; 0];
  [4; 3; 3; 2; 4; 0; 0; 0];
  [4; 4; 4; 2; 4; 0; 0; 0];
  [4; 5; 5; 2; 4; 0; 0; 0];
  [4; 6; 6; 2; 4; 0; 0; 0];
  [4; 7; 7; 2; 4; 0; 0; 0];
  [5; 0; 2; 0; 5; 0; 0; 0];
  [5; 1; 3; 0; 5; 0; 0; 0];
  [5; 2; 2; 0; 5; 0; 0; 0];
  [5; 3; 3; 0; 5; 0; 0; 0];
  [5; 4; 4; 0; 5; 0; 0; 0];
  [5; 5; 5; 2; 1; 0; 0; 0];
  [5; 6; 6; 0; 5; 0; 0; 0];
  [5; 7; 7; 0; 5; 0; 0; 0];
  [6; 0; 2; 0; 8; 0; 0; 0];
  [6; 1; 3; 0; 7; 0; 0; 0];
  [6; 2; 2; 2; 6; 0; 0; 0];
  [6; 3; 3; 2; 6; 0; 0; 0];
  [6; 4; 4; 2; 6; 0; 0; 0];
  [6; 5; 5; 2; 6; 0; 0; 0];
  [6; 6; 6; 2; 6; 0; 0; 0];
  [6; 7; 7; 2; 6; 0; 0; 0];
  [7; 0; 0; 0; 7; 0; 0; 0];
  [7; 1; 1; 0; 7; 0; 0; 0];
  [7; 2; 2; 0; 7; 0; 0; 0];
  [7; 3; 3; 0; 7; 0; 0; 0];
  [7; 4; 4; 0; 7; 0; 0; 0];
  [7; 5; 5; 2; 9; 0; 0; 0];
  [7; 6; 6; 0; 7; 0; 0; 0];
  [7; 7; 7; 0; 7; 0; 0; 0];
  [8; 0; 0; 0; 8; 0; 0; 0];
  [8; 1; 1; 0; 8; 0; 0; 0];
  [8; 2; 2; 0; 8; 0; 0; 0];
  [8; 3; 3; 0; 8; 0; 0; 0];
  [8; 4; 4; 0; 8; 0; 0; 0];
  [8; 5; 5; 2; 10; 0; 0; 0];
  [8; 6; 6; 0; 8; 0; 0; 0];
  [8; 7; 7; 0; 8; 0; 0; 0];
  [9; 0; 3; 2; 11; 0; 0; 0];
  [9; 1; 3; 2; 11; 0; 0; 0];
  [9; 2; 2; 2; 9; 0; 0; 0];
  [9; 3; 3; 2; 9; 0; 0; 0];
  [9; 4; 4; 0; 12; 0; 0; 0];
  [9; 5; 5; 2; 9; 0; 0; 0];
  [9; 6; 6; 2; 9; 0; 0; 0];
  [9; 7; 7; 2; 9; 0; 0; 0];
  [10; 0; 2; 2; 11; 0; 0; 0];
  [10; 1; 2; 2; 11; 0; 0; 0];
  [10; 2; 2; 2; 10; 0; 0; 0];
  [10; 3; 3; 2; 10; 0; 0; 0];
  [10; 4; 4; 0; 13; 0; 0; 0];
  [10; 5; 5; 2; 10; 0; 0; 0];
  [10; 6; 6; 2; 10; 0; 0; 0];
  [10; 7; 7; 2; 10; 0; 0; 0];
  [11; 0; 0; 2; 11; 0; 0; 0];
  [11; 1; 1; 2; 11; 0; 0; 0];
  [11; 2; 2; 2; 11; 0; 0; 0];
  [11; 3; 3; 2; 11; 0; 0; 0];
  [11; 4; 4; 2; 6; 0; 0; 0];
  [11; 5; 5; 2; 11; 0; 0; 0];
  [11; 6; 6; 2; 11; 0; 0; 0];
  [11; 7; 7; 2; 11; 0; 0; 0];
  [12; 0; 0; 0; 12; 0; 0; 0];
  [12; 1; 1; 0; 12; 0; 0; 0];
  [12; 2; 2; 0; 12; 0; 0; 0];
  [12; 3; 3; 0; 12; 0; 0; 0];
  [12; 4; 4; 0; 12; 0; 0; 0];
  [12; 5; 5; 0; 12; 0; 0; 0];
  [12; 6; 3; 2; 14; 0; 0; 0];
  [12; 7; 7; 0; 12; 0; 0; 0];
  [13; 0; 0; 0; 13; 0; 0; 0];
  [13; 1; 1; 0; 13; 0; 0; 0];
  [13; 2; 2; 0; 13; 0; 0; 0];
  [13; 3; 3; 0; 13; 0; 0; 0];
  [13; 4; 4; 0; 13; 0; 0; 0];
  [13; 5; 5; 0; 13; 0; 0; 0];
  [13; 6; 2; 2; 14; 0; 0; 0];
  [13; 7; 7; 0; 13; 0; 0; 0];
  [14; 0; 0; 2; 14; 0; 0; 0];
  [14; 1; 1; 2; 14; 0; 0; 0];
  [14; 2; 0; 2; 14; 0; 0; 0];
  [14; 3; 1; 2; 14; 0; 0; 0];
  [14; 4; 4; 2; 15; 0; 0; 0];
  [14; 5; 5; 2; 14; 0; 0; 0];
  [14; 6; 6; 2; 14; 0; 0; 0];
  [14; 7; 7; 2; 14; 0; 0; 0];
  [15; 0; 0; 0; 16; 0; 0; 0];
  [15; 1; 1; 0; 16; 0; 0; 0];
  [15; 2; 2; 2; 15; 0; 0; 0];
  [15; 3; 3; 2; 15; 0; 0; 0];
  [15; 4; 4; 2; 15; 0; 0; 0];
  [15; 5; 5; 2; 15; 0; 0; 0];
  [15; 6; 6; 2; 15; 0; 0; 0];
  [15; 7; 7; 2; 15; 0; 0; 0];
  [16; 0; 7; 0; 21; 0; 0; 0];
  [16; 1; 7; 0; 22; 0; 0; 0];
  [16; 2; 0; 0; 16; 0; 0; 0];
  [16; 3; 1; 0; 16; 0; 0; 0];
  [16; 4; 4; 0; 16; 0; 0; 0];
  [16; 5; 5; 0; 16; 0; 0; 0];
  [16; 6; 6; 0; 16; 0; 0; 0];
  [16; 7; 7; 0; 16; 0; 0; 0];
  [17; 0; 0; 2; 17; 0; 0; 0];
  [17; 1; 1; 2; 17; 0; 0; 0];
  [17; 2; 2; 2; 17; 0; 0; 0];
  [17; 3; 3; 2; 17; 0; 0; 0];
  [17; 4; 4; 2; 17; 0; 0; 0];
  [17; 5; 5; 2; 17; 0; 0; 0];
  [17; 6; 6; 2; 17; 0; 0; 0];
  [17; 7; 2; 0; 5; 0; 0; 0];
  [18; 0; 0; 2; 18; 0; 0; 0];
  [18; 1; 1; 2; 18; 0; 0; 0];
  [18; 2; 2; 2; 18; 0; 0; 0];
  [18; 3; 3; 2; 18; 0; 0; 0];
  [18; 4; 4; 2; 18; 0; 0; 0];
  [18; 5; 5; 2; 18; 0; 0; 0];
  [18; 6; 6; 2; 18; 0; 0; 0];
  [18; 7; 3; 0; 5; 0; 0; 0];
  [19; 0; 6; 2; 17; 0; 0; 0];
  [19; 1; 6; 2; 18; 0; 0; 0];
  [19; 2; 2; 2; 19; 0; 0; 0];
  [19; 3; 3; 2; 19; 0; 0; 0];
  [19; 4; 4; 2; 19; 0; 0; 0];
  [19; 5; 5; 2; 19; 0; 0; 0];
  [19; 6; 6; 2; 19; 0; 0; 0];
  [19; 7; 7; 2; 19; 0; 0; 0];
  [20; 0; 6; 2; 17; 0; 0; 0];
  [20; 1; 6; 2; 18; 0; 0; 0];
  [20; 2; 2; 0; 20; 0; 0; 0];
  [20; 3; 3; 0; 20; 0; 0; 0];
  [20; 4; 4; 0; 20; 0; 0; 0];
  [20; 5; 5; 0; 20; 0; 0; 0];
  [20; 6; 6; 0; 20; 0; 0; 0];
  [20; 7; 7; 0; 20; 0; 0; 0];
  [21; 0; 0; 0; 21; 0; 0; 0];
  [21; 1; 1; 0; 21; 0; 0; 0];
  [21; 2; 0; 0; 20; 0; 0; 0];
  [21; 3; 0; 2; 19; 0; 0; 0];
  [21; 4; 4; 0; 21; 0; 0; 0];
  [21; 5; 5; 0; 21; 0; 0; 0];
  [21; 6; 6; 0; 21; 0; 0; 0];
  [21; 7; 7; 0; 21; 0; 0; 0];
  [22; 0; 0; 0; 22; 0; 0; 0];
  [22; 1; 1; 0; 22; 0; 0; 0];
  [22; 2; 1; 0; 20; 0; 0; 0];
  [22; 3; 1; 2; 19; 0; 0; 0];
  [22; 4; 4; 0; 22; 0; 0; 0];
  [22; 5; 5; 0; 22; 0; 0; 0];
  [22; 6; 6; 0; 22; 0; 0; 0];
  [22; 7; 7; 0; 22; 0; 0; 0]
].

(** The literal transcription is exactly the NaN16 eight-word image of
    the already gated 23x8 table data ([nan16_word_image]). *)
Lemma fixture_table_is_word_image :
  fixture_table = map encode_nan16_words minsky_entries.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_table_length : length fixture_table = 184.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_table_rows8 :
  Forall (fun r => length r = 8) fixture_table.
Proof. vm_compute. repeat constructor; reflexivity. Qed.

(** Every row has at least two fields, hence the two conditionals of the
    scan can read [nth 0] and [nth 1]. *)
Lemma rows_short_of_rows8 :
  forall rows : list (list nat),
    Forall (fun r => length r = 8) rows ->
    Forall (fun r => 0 < length r /\ 1 < length r) rows.
Proof.
  intros rows H. induction H as [|r rs Hr Hrs IH].
  - constructor.
  - constructor; [rewrite Hr; lia|exact IH].
Qed.

Lemma fixture_table_short :
  Forall (fun r => 0 < length r /\ 1 < length r) fixture_table.
Proof. apply rows_short_of_rows8. exact fixture_table_rows8. Qed.

(** The table occupies [304, 1776), strictly below the tape base. *)
Lemma fixture_table_end :
  fixture_table_base + 8 * length fixture_table = 1776.
Proof. vm_compute. reflexivity. Qed.

Lemma fixture_table_below_tape :
  forall i f, i < length fixture_table -> f < 8 ->
    fixture_table_base + 8 * i + f < fixture_tape_base.
Proof.
  intros i f Hi Hf.
  rewrite fixture_table_length in Hi.
  unfold fixture_table_base, fixture_tape_base in *.
  lia.
Qed.

(** A tape window starting at the tape base is outside the table and the
    four control cells, for *every* window length. *)
Lemma tape_window_ok_of_table_below :
  forall (table : list (list nat)) (table_base tbase window : nat),
    (forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f < tbase) ->
    action_head_addr < tbase ->
    action_state_addr < tbase ->
    action_halt_addr < tbase ->
    tape_base_addr < tbase ->
    tape_window_ok table table_base tbase window.
Proof.
  intros table table_base tbase window Hcells Hhead Hstate Hhalt Htb.
  unfold tape_window_ok. split.
  - intros z Hz1 Hz2 i f Hi Hf.
    specialize (Hcells i f Hi Hf). lia.
  - intros z Hz1 Hz2. repeat split; lia.
Qed.

(** ** The two global layout facts, proved for the fixture *)

Theorem fixture_table_control_ok :
  table_control_ok fixture_table fixture_table_base.
Proof.
  apply table_control_ok_of_base_above.
  unfold action_halt_addr, fixture_table_base. lia.
Qed.

Theorem fixture_tape_window_ok :
  forall window,
    tape_window_ok fixture_table fixture_table_base fixture_tape_base window.
Proof.
  intros window.
  apply (tape_window_ok_of_table_below fixture_table fixture_table_base
    fixture_tape_base window).
  - exact fixture_table_below_tape.
  - unfold action_head_addr, fixture_tape_base. lia.
  - unfold action_state_addr, fixture_tape_base. lia.
  - unfold action_halt_addr, fixture_tape_base. lia.
  - unfold tape_base_addr, fixture_tape_base. lia.
Qed.

(** ** The per-step obligation holds with no layout hypotheses *)

Corollary fixture_step_ok :
  forall vm,
    entry_ok vm fixture_table fixture_table_base fixture_tape_base ->
    step_ok vm fixture_table fixture_table_base fixture_tape_base.
Proof.
  intros vm Hentry.
  apply (step_ok_of_window vm fixture_table fixture_table_base
    fixture_tape_base (vm_reg vm 2 + 1)
    Hentry fixture_table_length fixture_table_short fixture_table_rows8
    fixture_table_control_ok (fixture_tape_window_ok (vm_reg vm 2 + 1))).
  lia.
Qed.

(** ** Closed run refinement for the concrete fixture

    No layout hypothesis remains: only [entry_ok] on the initial VM is
    required, and all table/shape facts are closed computations. *)

Theorem vm_run_refines_fixture :
  forall (n : nat) (vm : VM),
    entry_ok vm fixture_table fixture_table_base fixture_tape_base ->
    entry_ok (vm_run n vm fixture_table fixture_table_base)
      fixture_table fixture_table_base fixture_tape_base /\
    nstate_rel
      (vm_to_nstate (vm_run n vm fixture_table fixture_table_base))
      (nrun n fixture_table fixture_table_base fixture_tape_base
        (vm_to_nstate vm)).
Proof.
  intros n vm Hentry.
  exact (vm_run_refines_window n vm fixture_table fixture_table_base
    fixture_tape_base Hentry fixture_table_length fixture_table_short
    fixture_table_rows8 fixture_table_control_ok
    (fixture_tape_window_ok (vm_reg vm 2 + n + 1))).
Qed.

(** ** Axiom check *)

Print Assumptions fixture_table_control_ok.
Print Assumptions fixture_tape_window_ok.
Print Assumptions fixture_step_ok.
Print Assumptions vm_run_refines_fixture.
