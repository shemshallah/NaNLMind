(** * Prefetched q1 fetch after a tagged dispatch

    The tagged dispatch ends at q1 with a rail of 6/7 tags and the
    current write mark.  This module composes that endpoint with a
    q1 match and the q1 -> q6 crossing for a *supplied* next condition
    and action.  The source encoder can therefore precompute the next
    row instead of making the native table search the description.

    The composition is conditional on the exact rail identity: the
    caller must place the next condition/action in the q1 rail.  It is a
    native macro, not yet a total source encoder.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyDirectionRelocationCycle MinskyTaggedHalt
  MinskyTaggedWideDispatch MinskyTaggedRightWide MinskyTaggedReentry.

(** ** Right dispatch followed by a prefetched q1 match *)

Theorem tagged_right_prefetch_to_q6 :
  forall (first : bool) (rest next_bits : list bool)
         (old sacrificial : bool) (outer tail : list nat)
         (pass : list nat) (bits action : list bool) (dir : bool)
         (rest6 : list nat),
    Forall q1_pass pass ->
    length action = length bits ->
    rev
      (rev
        ([if sacrificial then 3 else 2] ++
         map q0_stable_control_tag next_bits) ++
       0 :: 6 :: map q0_stable_control_tag
         ((first :: rest) ++ [true])) ++
    2 :: tail =
    pass ++ map match_mark bits ++ [4] ++ map match_raw bits ++
    map source_bit action ++ source_bit dir :: rest6 ->
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
            ((first :: rest) ++ [true]))) +
      (matched_comparison_steps bits (length pass) 1 +
       S (length (pass ++ map match_raw bits))))
      (entry_config 15
        (source_bit old :: 5 :: 3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit sacrificial :: 2 :: 7 ::
         map q0_stable_control_tag next_bits ++
         source_bit false :: tail)) =
    entry_config 6
      (4 :: rev (pass ++ map match_raw bits) ++
       5 :: source_bit old :: outer)
      (map match_mark bits ++ map source_bit action ++
       source_bit dir :: rest6).
Proof.
  intros first rest next_bits old sacrificial outer tail pass bits action
    dir rest6 Hpass Hlen Hrail.
  rewrite dispatch_run_add.
  rewrite (tagged_right_dispatch_to_q1
    first rest next_bits old sacrificial outer tail).
  rewrite Hrail.
  rewrite dispatch_run_add.
  change (matched_comparison_steps bits (length pass) 1)
    with (matched_comparison_steps bits (length pass) (length [4])).
  rewrite (q1_all_matching_bits_wide bits pass [4]
    (source_bit old :: outer)
    (map source_bit action ++ source_bit dir :: rest6) Hpass).
  2:{ constructor; [unfold wide_mark; auto 10 | constructor]. }
  replace (pass ++ map match_raw bits ++ [4] ++
           map match_mark bits ++ map source_bit action ++
           source_bit dir :: rest6)
    with ((pass ++ map match_raw bits) ++ [4] ++
          map match_mark bits ++ map source_bit action ++
          source_bit dir :: rest6)
    by (repeat rewrite <- app_assoc; reflexivity).
  apply (q1_scan_four_list_to_q6
    (pass ++ map match_raw bits)
    (map match_mark bits ++
     map source_bit action ++ source_bit dir :: rest6)
    (5 :: source_bit old :: outer)).
  apply Forall_app. split.
  - exact Hpass.
  - apply match_raw_valid.
Qed.

Print Assumptions tagged_right_prefetch_to_q6.

(** ** Left dispatch followed by a prefetched q1 match *)

Theorem tagged_left_prefetch_to_q6 :
  forall (first : bool) (rest : list bool) (old : bool)
         (outer tail : list nat)
         (pass : list nat) (bits action : list bool) (dir : bool)
         (rest6 : list nat),
    Forall q1_pass pass ->
    length action = length bits ->
    rev
      (rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0; 6]) ++
    2 :: tail =
    pass ++ map match_mark bits ++ [4] ++ map match_raw bits ++
    map source_bit action ++ source_bit dir :: rest6 ->
    run
      (((direction_phase_cost
           (map q0_stable_control_tag (first :: rest)) [6; 5] +
         (1 + S (length (source_bit old :: rev [6; 5])))) +
        (4 + (length (rev (first :: rest)) + 1))) +
       S (length
         (rev (map q0_stable_control_tag (rev (first :: rest))) ++ [0; 6])) +
      (matched_comparison_steps bits (length pass) 1 +
       S (length (pass ++ map match_raw bits))))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit false :: tail)) =
    entry_config 6
      (4 :: rev (pass ++ map match_raw bits) ++
       5 :: source_bit old :: 6 :: outer)
      (map match_mark bits ++ map source_bit action ++
       source_bit dir :: rest6).
Proof.
  intros first rest old outer tail pass bits action dir rest6 Hpass Hlen Hrail.
  rewrite dispatch_run_add.
  rewrite (tagged_left_dispatch_to_q1 first rest old outer tail).
  rewrite Hrail.
  rewrite dispatch_run_add.
  change (matched_comparison_steps bits (length pass) 1)
    with (matched_comparison_steps bits (length pass) (length [4])).
  rewrite (q1_all_matching_bits_wide bits pass [4]
    (source_bit old :: 6 :: outer)
    (map source_bit action ++ source_bit dir :: rest6) Hpass).
  2:{ constructor; [unfold wide_mark; auto 10 | constructor]. }
  replace (pass ++ map match_raw bits ++ [4] ++
           map match_mark bits ++ map source_bit action ++
           source_bit dir :: rest6)
    with ((pass ++ map match_raw bits) ++ [4] ++
          map match_mark bits ++ map source_bit action ++
          source_bit dir :: rest6)
    by (repeat rewrite <- app_assoc; reflexivity).
  apply (q1_scan_four_list_to_q6
    (pass ++ map match_raw bits)
    (map match_mark bits ++
     map source_bit action ++ source_bit dir :: rest6)
    (5 :: source_bit old :: 6 :: outer)).
  apply Forall_app. split.
  - exact Hpass.
  - apply match_raw_valid.
Qed.

Print Assumptions tagged_left_prefetch_to_q6.
