(** * q2 continuations of the tagged dispatch

    When the source read target is false, the arbitrary-width tagged
    right and left dispatches end at q2.  This file composes that q2
    endpoint with a direct rail-to-delimiter scan, producing the q1
    next-match entry.

    The q3/true branches are in [MinskyTaggedContinuation].
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyHeadMoveMacro MinskyWritebackMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle
  MinskyDirectionRelocationCycle MinskyTaggedHalt
  MinskyTaggedWideDispatch MinskyTaggedRightWide.

Lemma Forall_dispatch_left_tag :
  forall bits, Forall dispatch_left_symbol
    (map q0_stable_control_tag bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold dispatch_left_symbol, q0_stable_control_tag; auto 12.
    + exact IH.
Qed.

Lemma Forall_dispatch_left_tag_rev :
  forall bits, Forall dispatch_left_symbol
    (rev (map q0_stable_control_tag bits)).
Proof.
  intros. apply Forall_rev. apply Forall_dispatch_left_tag.
Qed.

Lemma q2_rail_direct_reenter_q1 :
  forall (rail stored right : list nat),
    Forall dispatch_left_symbol rail ->
    run (S (length rail))
      (cfg_ml 2 (rail ++ 5 :: stored) right) =
    entry_config 1 (5 :: stored) (rev rail ++ right).
Proof.
  intros [|r rest] stored right H.
  - cbn. reflexivity.
  - change (run (S (length (r :: rest)))
      (entry_config 2 (rest ++ 5 :: stored) (r :: right)) =
      entry_config 1 (5 :: stored) (rev (r :: rest) ++ right)).
    apply (dispatch_left_to_delimiter rest r stored right H).
Qed.

Lemma q2_rail_direct_reenter_q1_right :
  forall (a b stored right : list nat),
    Forall dispatch_left_symbol (a ++ b) ->
    run (S (length (a ++ b)))
      (cfg_ml 2 (a ++ b ++ 5 :: stored) right) =
    entry_config 1 (5 :: stored) (rev (a ++ b) ++ right).
Proof.
  intros a b stored right H.
  replace (a ++ b ++ 5 :: stored)
    with ((a ++ b) ++ 5 :: stored).
  2:{ repeat rewrite app_assoc. reflexivity. }
  apply (q2_rail_direct_reenter_q1 (a ++ b) stored right H).
Qed.

Theorem tagged_right_dispatch_to_q1 :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial : bool) (outer tail : list nat),
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
       S (length
         (rev
           ([if sacrificial then 3 else 2] ++
            map q0_stable_control_tag next_bits) ++
          0 :: 6 :: map q0_stable_control_tag
            ((first :: rest) ++ [true]))))
      (entry_config 15
        (source_bit old :: 5 :: 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit sacrificial :: 2 :: 7 ::
         map q0_stable_control_tag next_bits ++
         source_bit false :: tail)) =
    entry_config 1 (5 :: source_bit old :: outer)
      (rev
        (rev
          ([if sacrificial then 3 else 2] ++
           map q0_stable_control_tag next_bits) ++
         0 :: 6 :: map q0_stable_control_tag
           ((first :: rest) ++ [true])) ++
       2 :: tail).
Proof.
  intros first rest next_bits old sacrificial outer tail.
  rewrite dispatch_run_add.
  rewrite (q15_right_buffered_native_tagged_list_dispatch
    first rest next_bits old sacrificial false outer tail).
  rewrite map_app.
  assert (Hassoc :
    rev
      ([if sacrificial then 3 else 2] ++
       map q0_stable_control_tag next_bits) ++
    0 :: 6 ::
    (map q0_stable_control_tag (first :: rest) ++ [7]) ++
    5 :: source_bit old :: outer =
    ((rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
      0 :: 6 :: map q0_stable_control_tag (first :: rest)) ++
     [7]) ++ 5 :: source_bit old :: outer).
  { repeat rewrite app_assoc. reflexivity. }
  rewrite Hassoc.
  apply (q2_rail_direct_reenter_q1
    (rev
      ([if sacrificial then 3 else 2] ++
       map q0_stable_control_tag next_bits) ++
     0 :: 6 :: map q0_stable_control_tag (first :: rest))
    7 (source_bit old :: outer) (2 :: tail)).
  apply Forall_app. split.
  - apply Forall_rev. rewrite Forall_app. split.
    + destruct sacrificial; unfold dispatch_left_symbol; auto 12.
    + apply Forall_dispatch_left_tag.
  - constructor.
    + unfold dispatch_left_symbol; auto 12.
    + constructor.
      * unfold dispatch_left_symbol; auto 12.
      * apply Forall_dispatch_left_tag.
Qed.

Print Assumptions tagged_right_dispatch_to_q1.

Theorem tagged_left_dispatch_to_q1 :
  forall (first : bool) (rest : list bool) (old : bool)
         (outer tail : list nat),
    run
      (((direction_phase_cost
           (map q0_stable_control_tag (first :: rest)) [6; 5] +
         (1 + S (length (source_bit old :: rev [6; 5])))) +
        (4 + (length (rev (first :: rest)) + 1))) +
       S (length
         (rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0; 6])))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit false :: tail)) =
    entry_config 1 (5 :: source_bit old :: 6 :: outer)
      (rev
        (rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0; 6]) ++
       2 :: tail).
Proof.
  intros first rest old outer tail.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_list_dispatch
    first rest old false outer tail).
  assert (Hassoc :
    rev (map q0_stable_control_tag (rev (first :: rest))) ++
    0 :: 6 :: 5 :: source_bit old :: 6 :: outer =
    ((rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0]) ++
     [6]) ++ 5 :: source_bit old :: 6 :: outer).
  { repeat rewrite app_assoc. reflexivity. }
  rewrite Hassoc.
  apply (q2_rail_direct_reenter_q1
    (rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0])
    6 (source_bit old :: 6 :: outer) (2 :: tail)).
  apply Forall_app. split.
  - apply Forall_dispatch_left_tag_rev.
  - repeat constructor; unfold dispatch_left_symbol; auto 12.
Qed.

Print Assumptions tagged_left_dispatch_to_q1.
