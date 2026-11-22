(** * Arbitrary-width tagged dispatch

    The tagged cycle in [MinskyDirectionRelocationCycle] and
    [MinskyTaggedHalt] was stated for two control bits.  The frozen
    table is width-parametric, and the wide-source semantics allows any
    finite state width.  This module generalizes the q0/q1/q5 dispatch
    gates from a pair of 6/7 tags to an arbitrary finite list of tags.

    Nothing here constructs the upstream canonical q12 frame; these are
    exact native dispatch macros.  The point is that the state width is
    no longer fixed at two.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyWritebackMacro MinskyRelocationMacro
  MinskyDirectionDecision
  MinskyDirectionCycle MinskyDirectionRelocationCycle MinskyTaggedHalt.

(** ** q0 dispatch over an arbitrary tag list *)

Theorem q0_tagged_control_list_dispatches_target :
  forall (prefix left tail : list nat) (bits : list bool)
         (target : bool),
    Forall q0_pass prefix ->
    run (length prefix + length bits + 1)
      (entry_config 0 left
        (prefix ++ map q0_stable_control_tag bits ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (prefix ++ map q0_stable_control_tag bits) ++ left)
      tail
    else cfg_ml 2
      (rev (prefix ++ map q0_stable_control_tag bits) ++ left)
      (2 :: tail).
Proof.
  intros prefix left tail bits target Hprefix.
  assert (Htags : Forall q0_pass (map q0_stable_control_tag bits)).
  { induction bits as [|b rest IH].
    - constructor.
    - cbn [map]. constructor.
      + apply q0_stable_control_tag_pass.
      + exact IH. }
  assert (Hmarked :
    Forall q0_pass (prefix ++ map q0_stable_control_tag bits)).
  { rewrite Forall_app. split; assumption. }
  replace (length prefix + length bits + 1)
    with (S (length (prefix ++ map q0_stable_control_tag bits))).
  2:{ rewrite app_length, map_length. lia. }
  rewrite app_assoc.
  destruct target.
  - apply (q0_scan_one _ _ _ Hmarked).
  - apply (q0_scan_zero _ _ _ Hmarked).
Qed.

Print Assumptions q0_tagged_control_list_dispatches_target.

(** ** The q5 left buffer followed by q1 and q0 *)

Lemma q5_left_buffer_to_q0_any_tags :
  forall (old : bool) (bits : list bool) (target : bool)
         (outer tail : list nat),
    run 4
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: map q0_stable_control_tag bits ++
         source_bit target :: tail)) =
    entry_config 0 (0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
      (map q0_stable_control_tag bits ++ source_bit target :: tail).
Proof.
  intros old bits target outer tail.
  reflexivity.
Qed.

Theorem q5_left_false_gate_tagged_list_dispatch :
  forall (old : bool) (bits : list bool) (target : bool)
         (outer tail : list nat),
    run (4 + (length bits + 1))
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: map q0_stable_control_tag bits ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (map q0_stable_control_tag bits) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail
    else cfg_ml 2
      (rev (map q0_stable_control_tag bits) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: tail).
Proof.
  intros old bits target outer tail.
  rewrite dispatch_run_add.
  rewrite q5_left_buffer_to_q0_any_tags.
  apply (q0_tagged_control_list_dispatches_target
    [] (0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail bits target).
  constructor.
Qed.

Print Assumptions q5_left_false_gate_tagged_list_dispatch.

(** ** Full left q15 relocation with an arbitrary action rail *)

Theorem q15_left_false_guard_native_tagged_list_dispatch :
  forall (first : bool) (rest : list bool) (old target : bool)
         (outer tail : list nat),
    run ((direction_phase_cost
            (map q0_stable_control_tag (first :: rest)) [6; 5] +
          (1 + S (length
            (source_bit old :: rev [6; 5])))) +
         (4 + (length (rev (first :: rest)) + 1)))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (map q0_stable_control_tag
              (rev (first :: rest))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail
    else cfg_ml 2
      (rev (map q0_stable_control_tag
             (rev (first :: rest))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: tail).
Proof.
  intros first rest old target outer tail.
  assert (H21 : Forall q21_pass [6; 5]).
  { repeat (constructor; try (unfold q21_pass; auto 12)). }
  assert (H17 : Forall q17_pass (rev [6; 5])).
  { repeat (constructor; try (unfold q17_pass; auto 12)). }
  rewrite writeback_run_add.
  transitivity
    (run (4 + (length (rev (first :: rest)) + 1))
      (cfg_ml 5
        (rev (source_bit old :: rev [6; 5]) ++ 6 :: outer)
        (2 :: rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: tail))).
  - apply (f_equal
      (run (4 + (length (rev (first :: rest)) + 1)))).
    apply (tagged_rail_left_relocates_to_q5
      first rest 6 [5] old target false outer tail H21 H17).
  - change (run (4 + (length (rev (first :: rest)) + 1))
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: tail)) =
      if target
      then entry_config 3
        (3 :: rev (map q0_stable_control_tag
                (rev (first :: rest))) ++
         0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail
      else cfg_ml 2
        (rev (map q0_stable_control_tag
               (rev (first :: rest))) ++
         0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: tail)).
    rewrite <- map_rev.
    apply q5_left_false_gate_tagged_list_dispatch.
Qed.

Print Assumptions q15_left_false_guard_native_tagged_list_dispatch.

(** ** Full right q15 relocation with an arbitrary action rail *)

Theorem q5_q1_q0_buffered_tagged_list_dispatch :
  forall (bits next_bits : list bool) (sacrificial target : bool)
         (stored tail : list nat),
    run ((S (length (2 :: 6 ::
            map q0_stable_control_tag bits)) +
          (length (map q0_stable_control_tag bits) + 2)) +
         (length next_bits + 2))
      (entry_config 5
        (6 :: map q0_stable_control_tag bits ++ 5 :: stored)
        (2 :: (if sacrificial then 3 else 2) ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag bits ++ 5 :: stored)
      tail
    else cfg_ml 2
      (rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag bits ++ 5 :: stored)
      (2 :: tail).
Proof.
  intros bits next_bits sacrificial target stored tail.
  rewrite writeback_run_add.
  rewrite (q5_q1_buffered_tagged_rail_reenters_q0
    bits stored
    ((if sacrificial then 3 else 2) ::
     map q0_stable_control_tag next_bits ++
     source_bit target :: tail)).
  replace (length next_bits + 2)
    with (length [if sacrificial then 3 else 2] +
          length next_bits + 1).
  2:{ cbn [length]. lia. }
  apply (q0_tagged_control_list_dispatches_target
    [if sacrificial then 3 else 2]
    (0 :: 6 :: map q0_stable_control_tag bits ++ 5 :: stored)
    tail next_bits target).
  constructor.
  - destruct sacrificial; unfold q0_pass; auto 12.
  - constructor.
Qed.

Print Assumptions q5_q1_q0_buffered_tagged_list_dispatch.

Theorem q15_right_buffered_native_tagged_list_dispatch :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial target : bool) (outer tail : list nat),
    run ((direction_phase_cost
            (map q0_stable_control_tag ((first :: rest) ++ [true])) [5] +
          (S (length
            ([5] ++ 7 :: rev
              (map q0_stable_control_tag ((first :: rest) ++ [true])))) +
           S (length [2]))) +
         ((S (length (2 :: 6 ::
             map q0_stable_control_tag ((first :: rest) ++ [true]))) +
           (length (map q0_stable_control_tag
              ((first :: rest) ++ [true])) + 2)) +
          (length next_bits + 2)))
      (entry_config 15
        (source_bit old :: 5 :: 3 :: outer)
        (rev (map q0_stable_control_tag ((first :: rest) ++ [true])) ++
         source_bit sacrificial :: 2 :: 7 ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag ((first :: rest) ++ [true]) ++
       5 :: source_bit old :: outer) tail
    else cfg_ml 2
      (rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag ((first :: rest) ++ [true]) ++
       5 :: source_bit old :: outer) (2 :: tail).
Proof.
  intros first rest next_bits old sacrificial target outer tail.
  assert (H21 : Forall q21_pass [5]).
  { constructor.
    - unfold q21_pass; auto 12.
    - constructor. }
  assert (H15 : Forall q15_pass (rev [5])).
  { constructor.
    - unfold q15_pass; auto 12.
    - constructor. }
  assert (H17 : Forall q17_pass [2]).
  { constructor.
    - unfold q17_pass; auto 12.
    - constructor. }
  rewrite writeback_run_add.
  transitivity
    (run ((S (length (2 :: 6 ::
              map q0_stable_control_tag ((first :: rest) ++ [true]))) +
            (length (map q0_stable_control_tag
               ((first :: rest) ++ [true])) + 2)) +
           (length next_bits + 2))
      (cfg_ml 5
        (rev [2] ++ 6 ::
         rev (rev [5] ++ 7 ::
           rev (map q0_stable_control_tag ((first :: rest) ++ [true]))) ++
         source_bit old :: outer)
        (2 :: (if sacrificial then 3 else 2) ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail))).
  - apply (f_equal
      (run ((S (length (2 :: 6 ::
                map q0_stable_control_tag ((first :: rest) ++ [true]))) +
              (length (map q0_stable_control_tag
                 ((first :: rest) ++ [true])) + 2)) +
             (length next_bits + 2)))).
    apply (tagged_rail_right_relocates_to_q5
      first (rest ++ [true]) 5 [] old sacrificial outer [2]
      (map q0_stable_control_tag next_bits ++
       source_bit target :: tail) H21 H15 H17).
  - cbn [rev].
    change (run ((S (length (2 :: 6 ::
               map q0_stable_control_tag ((first :: rest) ++ [true]))) +
             (length (map q0_stable_control_tag
                ((first :: rest) ++ [true])) + 2)) +
            (length next_bits + 2))
      (entry_config 5
        (6 ::
         (rev (rev [5] ++ 7 ::
           rev (map q0_stable_control_tag ((first :: rest) ++ [true]))) ++
          source_bit old :: outer))
        (2 :: (if sacrificial then 3 else 2) ::
         map q0_stable_control_tag next_bits ++
         source_bit target :: tail)) =
      if target
      then entry_config 3
        (3 :: rev
          ([if sacrificial then 3 else 2] ++
           map q0_stable_control_tag next_bits) ++
         0 :: 6 :: map q0_stable_control_tag ((first :: rest) ++ [true]) ++
         5 :: source_bit old :: outer) tail
      else cfg_ml 2
        (rev
          ([if sacrificial then 3 else 2] ++
           map q0_stable_control_tag next_bits) ++
         0 :: 6 :: map q0_stable_control_tag ((first :: rest) ++ [true]) ++
         5 :: source_bit old :: outer) (2 :: tail)).
    rewrite (q15_right_tagged_return_buffer_layout
      ((first :: rest) ++ [true]) old outer).
    apply q5_q1_q0_buffered_tagged_list_dispatch.
Qed.

Print Assumptions q15_right_buffered_native_tagged_list_dispatch.
