(** * Arbitrary-width right tagged dispatch

    The left q15->q5->q1->q0 dispatch was generalized to arbitrary
    action rails in [MinskyTaggedWideDispatch].  This file completes the
    right direction: the q15 right relocation, the buffered q5/q1 gate,
    and the q0 target dispatch for any finite next-state tag list.

    The proof is an exact native composition; the only list-shape input
    is the two-cell return buffer [2] and the [5] direction marker.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyWritebackMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle
  MinskyDirectionRelocationCycle MinskyTaggedHalt
  MinskyTaggedWideDispatch.

Theorem q15_right_buffered_native_tagged_list_dispatch :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial target : bool) (outer tail : list nat),
    run
      ((direction_phase_cost
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
        (length next_bits + 2)))
      (entry_config 15
        (source_bit old :: 5 :: 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit sacrificial :: 2 :: 7 ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag
         ((first :: rest) ++ [true]) ++
       5 :: source_bit old :: outer) tail
    else cfg_ml 2
      (rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag
         ((first :: rest) ++ [true]) ++
       5 :: source_bit old :: outer) (2 :: tail).
Proof.
  intros first rest next_bits old sacrificial target outer tail.
  assert (H21 : Forall q21_pass [5]).
  { constructor.
    - unfold q21_pass; auto 12.
    - constructor.
  }
  assert (H15 : Forall q15_pass (rev [5])).
  { constructor.
    - unfold q15_pass; auto 12.
    - constructor.
  }
  assert (H17 : Forall q17_pass [2]).
  { constructor.
    - unfold q17_pass; auto 12.
    - constructor.
  }
  rewrite writeback_run_add.
  match goal with
  | |- _ = ?expected =>
    change (run
      ((S (length (2 :: 6 ::
           map q0_stable_control_tag
             ((first :: rest) ++ [true]))) +
        (length (map q0_stable_control_tag
           ((first :: rest) ++ [true])) + 2)) +
       (length next_bits + 2))
      (run
        (direction_phase_cost
           (map q0_stable_control_tag (first :: rest)) [5] +
         (S (length
           (rev [5] ++ 7 ::
            rev (map q0_stable_control_tag (first :: rest)))) +
          S (length [2])))
        (entry_config 15
          (source_bit old :: 5 :: [] ++ 3 :: outer)
          (rev (map q0_stable_control_tag (first :: rest)) ++
           source_bit sacrificial :: [2] ++
           7 :: map q0_stable_control_tag next_bits ++
           source_bit target :: tail))) = expected)
  end.
  rewrite (tagged_rail_right_relocates_to_q5
    first rest 5 [] old sacrificial outer [2]
    (map q0_stable_control_tag next_bits ++
     source_bit target :: tail) H21 H15 H17).
  match goal with
  | |- _ = ?expected =>
    change (run
      ((S (length (2 :: 6 ::
           map q0_stable_control_tag
             ((first :: rest) ++ [true]))) +
        (length (map q0_stable_control_tag
           ((first :: rest) ++ [true])) + 2)) +
       (length next_bits + 2))
      (entry_config 5
        (6 ::
         (rev (rev [5] ++ 7 ::
            rev (map q0_stable_control_tag (first :: rest))) ++
          source_bit old :: outer))
        (2 :: (if sacrificial then 3 else 2) ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail)) = expected)
  end.
  rewrite (q15_right_tagged_return_buffer_layout
    (first :: rest) old outer).
  apply q5_q1_q0_buffered_tagged_list_dispatch.
Qed.

Print Assumptions q15_right_buffered_native_tagged_list_dispatch.
