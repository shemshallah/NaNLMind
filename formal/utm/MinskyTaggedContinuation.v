(** * Continuations of the tagged dispatch

    The arbitrary-width tagged right and left dispatches end at q3 when
    the source read target is true.  This file composes that q3 endpoint
    with the two native continuations:

    - q3 scans to the end marker 5 and halts (the lookup-failure/halt
      branch);
    - q3 scans to the next X=4 and re-enters q5 (the running branch).

    Both are exact native runs.  The source-program layout that supplies
    the q3 tail is still an encoder obligation.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyWritebackMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle
  MinskyDirectionRelocationCycle MinskyTaggedHalt
  MinskyTaggedWideDispatch MinskyTaggedRightWide.

Theorem tagged_right_dispatch_halts :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial : bool) (outer scanned done : list nat),
    Forall q3_halt_pass scanned ->
    c_halted
      (run
        (((direction_phase_cost
             (map q0_stable_control_tag (first :: rest)) [5] +
           (S (length
             ([5] ++ 7 :: rev
               (map q0_stable_control_tag (first :: rest)))) +
            S (length [2]))) +
          ((S (length (2 :: 6 ::
              map q0_stable_control_tag
                ((first :: rest) ++ [true]))) +
            (length (map q0_stable_control_tag
              ((first :: rest) ++ [true])) + 2)) +
           (length next_bits + 2))) +
         S (length scanned))
        (entry_config 15
          (source_bit old :: 5 :: 3 :: outer)
          (rev (map q0_stable_control_tag (first :: rest)) ++
           source_bit sacrificial :: 2 :: 7 ::
           map q0_stable_control_tag next_bits ++
           source_bit true :: scanned ++ 5 :: done))) = true.
Proof.
  intros first rest next_bits old sacrificial outer scanned done Hscan.
  rewrite dispatch_run_add.
  rewrite (q15_right_buffered_native_tagged_list_dispatch
    first rest next_bits old sacrificial true outer
    (scanned ++ 5 :: done)).
  apply q3_scan_to_five_halts. exact Hscan.
Qed.

Print Assumptions tagged_right_dispatch_halts.

Theorem tagged_left_dispatch_halts :
  forall (first : bool) (rest : list bool) (old : bool)
         (outer scanned done : list nat),
    Forall q3_halt_pass scanned ->
    c_halted
      (run
        (((direction_phase_cost
             (map q0_stable_control_tag (first :: rest)) [6; 5] +
           (1 + S (length (source_bit old :: rev [6; 5])))) +
          (4 + (length (rev (first :: rest)) + 1))) +
         S (length scanned))
        (entry_config 15
          (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
          (rev (map q0_stable_control_tag (first :: rest)) ++
           source_bit true :: scanned ++ 5 :: done))) = true.
Proof.
  intros first rest old outer scanned done Hscan.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_list_dispatch
    first rest old true outer (scanned ++ 5 :: done)).
  apply q3_scan_to_five_halts. exact Hscan.
Qed.

Print Assumptions tagged_left_dispatch_halts.

Theorem tagged_right_dispatch_to_q5 :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial : bool) (outer symbols suffix : list nat),
    Forall dispatch_right_symbol symbols ->
    run
      (((direction_phase_cost
           (map q0_stable_control_tag (first :: rest)) [5] +
         (S (length
           ([5] ++ 7 :: rev
             (map q0_stable_control_tag (first :: rest)))) +
          S (length [2]))) +
        ((S (length (2 :: 6 ::
            map q0_stable_control_tag
              ((first :: rest) ++ [true]))) +
          (length (map q0_stable_control_tag
            ((first :: rest) ++ [true])) + 2)) +
         (length next_bits + 2))) +
       (length symbols + 1))
      (entry_config 15
        (source_bit old :: 5 :: 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit sacrificial :: 2 :: 7 ::
         map q0_stable_control_tag next_bits ++
         source_bit true :: symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++
       3 :: rev
         ([if sacrificial then 3 else 2] ++
          map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag
         ((first :: rest) ++ [true]) ++
       5 :: source_bit old :: outer)
      (4 :: suffix).
Proof.
  intros first rest next_bits old sacrificial outer symbols suffix Hsym.
  rewrite dispatch_run_add.
  rewrite (q15_right_buffered_native_tagged_list_dispatch
    first rest next_bits old sacrificial true outer
    (symbols ++ 4 :: suffix)).
  apply q3_scan_to_q5. exact Hsym.
Qed.

Print Assumptions tagged_right_dispatch_to_q5.

Theorem tagged_left_dispatch_to_q5 :
  forall (first : bool) (rest : list bool) (old : bool)
         (outer symbols suffix : list nat),
    Forall dispatch_right_symbol symbols ->
    run
      (((direction_phase_cost
           (map q0_stable_control_tag (first :: rest)) [6; 5] +
         (1 + S (length (source_bit old :: rev [6; 5])))) +
        (4 + (length (rev (first :: rest)) + 1))) +
       (length symbols + 1))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit true :: symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++
       3 :: rev (map q0_stable_control_tag (rev (first :: rest))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
      (4 :: suffix).
Proof.
  intros first rest old outer symbols suffix Hsym.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_list_dispatch
    first rest old true outer (symbols ++ 4 :: suffix)).
  apply q3_scan_to_q5. exact Hsym.
Qed.

Print Assumptions tagged_left_dispatch_to_q5.
