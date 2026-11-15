(** * Kernel-checked execution of the generalized p=9 native compiler image

    The native fixture [mth_minsky_compiler_general_test.nas] emits this
    tape from a p=9, three-transition source machine and then runs the
    literal 23x8 table.  The source input is [1101], and the compiler's
    transition rows are

      q0,1 -> q1,1,R    q1,0 -> q3,0,L    q3,1 -> q2,1,L.

    The initial cells below are exactly the image written by that guest
    program.  The final cells, state and head are the independent Python
    table reference used by the native test.  The proof is a finite trace
    certificate for the generalized compiler path; it is not a theorem
    about every source machine and not a universality claim.
*)

From Coq Require Import List Arith ZArith Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable.

Definition wide_fixture_initial_cells : list nat :=
  [   1; 1; 0; 1; 6; 0; 0; 0; 0; 0; 0; 0; 0; 5; 0; 0; 0; 0; 0; 0;
   0; 0; 0; 0; 4; 0; 0; 0; 0; 0; 0; 0; 0; 0; 1; 0; 0; 0; 0; 0;
   0; 0; 0; 1; 1; 1; 4; 0; 0; 0; 0; 0; 0; 0; 0; 1; 0; 0; 0; 0;
   0; 0; 0; 0; 1; 1; 0; 0; 4; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1; 0;
   0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 5; 0; 0; 0;].

Definition wide_fixture_final_cells : list nat :=
  [   1; 1; 0; 1; 6; 0; 0; 0; 0; 0; 0; 0; 0; 5; 0; 0; 0; 0; 0; 0;
   0; 0; 2; 2; 4; 2; 2; 2; 2; 2; 2; 2; 2; 2; 3; 2; 2; 2; 2; 2;
   2; 2; 2; 3; 3; 3; 4; 2; 2; 2; 2; 2; 2; 2; 2; 3; 2; 2; 2; 2;
   2; 2; 2; 2; 3; 3; 2; 2; 4; 2; 2; 2; 2; 2; 2; 2; 3; 1; 1; 0;
   0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 5; 0; 0; 0;].

Definition wide_fixture_start : Config :=
  {| c_state := 5;
     c_tape :=
       {| t_left := rev (firstn 24 wide_fixture_initial_cells);
          t_right := skipn 24 wide_fixture_initial_cells |};
     c_halted := false |}.

Definition wide_fixture_finish : Config :=
  {| c_state := 0;
     c_tape :=
       {| t_left := rev (firstn 90 wide_fixture_final_cells);
          t_right := skipn 90 wide_fixture_final_cells |};
     c_halted := true |}.

Theorem wide_fixture_halts_at_step_1978 :
  run 1978 wide_fixture_start = wide_fixture_finish.
Proof. vm_compute. reflexivity. Qed.

Theorem wide_fixture_running_at_step_1977 :
  c_halted (run 1977 wide_fixture_start) = false.
Proof. vm_compute. reflexivity. Qed.

Theorem wide_fixture_final_head_and_state :
  c_state wide_fixture_finish = 0 /\
  length (t_left (c_tape wide_fixture_finish)) = 90 /\
  c_halted wide_fixture_finish = true.
Proof. repeat split; reflexivity. Qed.

Print Assumptions wide_fixture_halts_at_step_1978.
Print Assumptions wide_fixture_running_at_step_1977.
