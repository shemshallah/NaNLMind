(** * Kernel-checked execution of the p=16 native compiler image

    The raw NaN16 fixture [mth_minsky_compiler_p16_test.nas] writes this
    104-cell image and runs the fixed 23x8 table.  The source has 16-bit
    state fields, two transitions, input [1], and initial condition
    q0/read1.  The trace reaches the halted configuration in 11603
    transitions (the last one is the terminal update).

    This is a finite compiler-instance certificate, not a general
    source-machine simulation theorem.
*)

From Coq Require Import List Arith ZArith Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable.

Definition p16_fixture_initial_cells : list nat :=
  [   1; 6; 0; 0; 0; 0; 0; 0; 0; 0; 5; 0; 0; 0; 0; 0; 0; 0; 0; 0;
   0; 0; 0; 0; 0; 0; 0; 1; 4; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
   0; 0; 0; 0; 0; 1; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
   0; 1; 0; 1; 4; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
   1; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 1; 0; 0; 0;
   5; 0; 0; 0].

Definition p16_fixture_final_cells : list nat :=
  [   1; 6; 0; 0; 0; 0; 0; 0; 0; 0; 5; 0; 0; 0; 0; 0; 0; 0; 0; 0;
   0; 0; 0; 0; 0; 1; 2; 2; 4; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2;
   2; 2; 2; 2; 2; 3; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2;
   2; 3; 2; 3; 4; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2;
   1; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 1; 0; 0; 0;
   5; 0; 0; 0].

Definition p16_fixture_start : Config :=
  {| c_state := 5;
     c_tape :=
       {| t_left := rev (firstn 28 p16_fixture_initial_cells);
          t_right := skipn 28 p16_fixture_initial_cells |};
     c_halted := false |}.

Definition p16_fixture_finish : Config :=
  {| c_state := 0;
     c_tape :=
       {| t_left := rev (firstn 100 p16_fixture_final_cells);
          t_right := skipn 100 p16_fixture_final_cells |};
     c_halted := true |}.

Theorem p16_fixture_halts_at_step_11603 :
  run 11603 p16_fixture_start = p16_fixture_finish.
Proof. vm_compute. reflexivity. Qed.

Theorem p16_fixture_running_at_step_11602 :
  c_halted (run 11602 p16_fixture_start) = false.
Proof. vm_compute. reflexivity. Qed.

Theorem p16_fixture_final_head_and_state :
  c_state p16_fixture_finish = 0 /\
  length (t_left (c_tape p16_fixture_finish)) = 100 /\
  c_halted p16_fixture_finish = true.
Proof. repeat split; reflexivity. Qed.

Print Assumptions p16_fixture_halts_at_step_11603.
Print Assumptions p16_fixture_running_at_step_11602.
