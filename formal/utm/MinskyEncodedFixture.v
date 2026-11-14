(** * Kernel-checked execution of the native encoded-source fixture

    This is the exact initial tape from tests/test_minsky_encoded.cpp:
       000000M00000000Y000X0000111X0101011Y000
    The final tape, head=35 and halting condition are also those asserted
    in that native test.  The concrete 184-entry table is unchanged.

    The fixed table reaches its halting configuration in 583 transitions
    (including the terminal write-and-halt transition).  This is a fully
    finite trace certificate; it does not imply universal simulation.
*)

From Coq Require Import List Arith ZArith Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable.

Definition encoded_fixture_initial_cells : list nat :=
  [0; 0; 0; 0; 0; 0; 6; 0; 0; 0; 0; 0; 0; 0; 0; 5; 0; 0; 0; 4; 0; 0; 0; 0; 1; 1; 1; 4; 0; 1; 0; 1; 0; 1; 1; 5; 0; 0; 0].

Definition encoded_fixture_final_cells : list nat :=
  [0; 0; 0; 0; 0; 0; 1; 1; 6; 0; 0; 0; 0; 0; 0; 5; 1; 2; 2; 4; 2; 2; 2; 2; 3; 3; 3; 4; 2; 1; 0; 1; 0; 1; 1; 5; 0; 0; 0].

Definition encoded_fixture_start : Config :=
  {| c_state := 5;
     c_tape :=
       {| t_left := rev (firstn 19 encoded_fixture_initial_cells);
          t_right := skipn 19 encoded_fixture_initial_cells |};
     c_halted := false |}.

Definition encoded_fixture_finish : Config :=
  {| c_state := 0;
     c_tape :=
       {| t_left := rev (firstn 35 encoded_fixture_final_cells);
          t_right := skipn 35 encoded_fixture_final_cells |};
     c_halted := true |}.

Theorem encoded_fixture_halts_at_step_583 :
  run 583 encoded_fixture_start = encoded_fixture_finish.
Proof. vm_compute. reflexivity. Qed.

Theorem encoded_fixture_running_at_step_582 :
  c_halted (run 582 encoded_fixture_start) = false.
Proof. vm_compute. reflexivity. Qed.

Theorem encoded_fixture_final_head_and_state :
  c_state encoded_fixture_finish = 0 /\
  length (t_left (c_tape encoded_fixture_finish)) = 35 /\
  c_halted encoded_fixture_finish = true.
Proof. repeat split; reflexivity. Qed.

Theorem encoded_fixture_halt_is_stable :
  forall extra, run extra encoded_fixture_finish = encoded_fixture_finish.
Proof.
  intros extra.
  destruct extra; reflexivity.
Qed.

Print Assumptions encoded_fixture_halts_at_step_583.
Print Assumptions encoded_fixture_running_at_step_582.
