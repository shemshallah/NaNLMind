(** * Left buffered tagged native target dispatch

    This is the left counterpart of
    `q15_right_buffered_native_tagged_target_dispatch`, built with a
    controlled sacrificial false delimiter so that the q1 gate is the
    intended q0 path (mark 2), not the q4 mismatch path (mark 3).

    The cycle is
      q15 -> q16 -> q21/q22 -> q20 -> q17/q18 -> q5 -> q1 -> q0 -> q2/q3.
    It starts at its stated q15 configuration; canonical reachability and
    the source encoding remain separate obligations.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyActionMacro
  MinskyWritebackMacro MinskyHeadMoveMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle MinskyWideSource
  MinskyConcreteDispatch MinskyWideConcreteDispatch
  MinskyDirectionRelocationCycle.

Lemma q1_two_to_q0 :
  forall left tail,
    step (entry_config 1 left (2 :: tail)) =
    entry_config 0 (0 :: left) tail.
Proof. intros left tail. reflexivity. Qed.

Lemma q5_left_buffer_pass :
  Forall q5_return_pass (6 :: source_bit false :: 6).
Proof.
  constructor.
  - unfold q5_return_pass; auto 12.
  - constructor.
    + unfold q5_return_pass, source_bit; auto 12.
    + constructor.
      * unfold q5_return_pass; auto 12.
      * constructor.
Qed.

Lemma q1_left_buffer_pass : Forall q1_tagged_pass [6].
Proof.
  constructor.
  - unfold q1_tagged_pass; auto.
  - constructor.
Qed.

Theorem tagged_rail_left_buffered_native_tagged_target_dispatch :
  forall (first : bool) (rest : list bool)
         (target read c1 c2 : bool)
         (stored pre tail : list nat),
    rev (map q0_stable_control_tag (first :: rest)) =
      pre ++ [q0_stable_control_tag c1; q0_stable_control_tag c2] ->
    Forall q0_pass pre ->
    run
      ((direction_phase_cost
          (map q0_stable_control_tag (first :: rest)) [6] +
        (1 + S (length (source_bit false :: rev [6])))) +
       (S (length (6 :: source_bit false :: 6)) +
        (1 + (1 + (length pre + 5)))))
      (entry_config 15
        (source_bit false :: 6 :: 2 :: source_bit target :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit read :: tail)) =
    if read
    then entry_config 3
      (3 :: rev
        ((6 :: (if target then 3 else 2) :: pre) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 6 :: 5 :: stored) tail
    else cfg_ml 2
      (rev
        ((6 :: (if target then 3 else 2) :: pre) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 6 :: 5 :: stored) (2 :: tail).
Proof.
  intros first rest target read c1 c2 stored pre tail Hsplit Hpre.
  assert (H21 : Forall q21_pass [6]).
  { constructor.
    - unfold q21_pass; auto 12.
    - constructor. }
  assert (H17 : Forall q17_pass (rev [6])).
  { cbn [rev]. constructor.
    - unfold q17_pass; auto 12.
    - constructor. }
  assert (Hq0pre : Forall q0_pass
      (6 :: (if target then 3 else 2) :: pre)).
  { constructor.
    - unfold q0_pass; auto 12.
    - constructor.
      + destruct target; unfold q0_pass; auto 12.
      + exact Hpre. }
  rewrite dispatch_run_add.
  rewrite (tagged_rail_left_relocates_to_q5 first rest 6 [] false read
    target (5 :: stored) tail H21 H17).
  cbn [rev source_bit].
  change (run
    (S (length (6 :: 0 :: 6)) + (1 + (1 + (length pre + 5))))
    (entry_config 5 (0 :: 6 :: 5 :: stored)
      (6 :: (if target then 3 else 2) ::
       rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit read :: tail)) =
    if read
    then entry_config 3
      (3 :: rev
        ((6 :: (if target then 3 else 2) :: pre) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 6 :: 5 :: stored) tail
    else cfg_ml 2
      (rev
        ((6 :: (if target then 3 else 2) :: pre) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 6 :: 5 :: stored) (2 :: tail)).
  rewrite dispatch_run_add.
  rewrite (q5_return_scan_to_first_five (0 :: 6) 6 stored
    ((if target then 3 else 2) ::
     rev (map q0_stable_control_tag (first :: rest)) ++
     source_bit read :: tail) q5_left_buffer_pass).
  cbn [rev map entry_rewrite].
  change (run (1 + (1 + (length pre + 5)))
    (entry_config 1 (6 :: 5 :: stored)
      (2 :: 6 :: (if target then 3 else 2) ::
       rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit read :: tail)) = _).
  rewrite dispatch_run_add.
  rewrite (q1_scan_tagged_rail [6] (5 :: stored)
    (2 :: 6 :: (if target then 3 else 2) ::
     rev (map q0_stable_control_tag (first :: rest)) ++
     source_bit read :: tail) q1_left_buffer_pass).
  cbn [rev].
  rewrite dispatch_run_add.
  change (step
    (entry_config 1 (6 :: 5 :: stored)
      (2 :: 6 :: (if target then 3 else 2) ::
       rev (map q0_stable_control_tag (first :: rest)) ++
       source_bit read :: tail)) = _).
  rewrite q1_two_to_q0.
  replace (6 :: (if target then 3 else 2) ::
           rev (map q0_stable_control_tag (first :: rest)) ++
           source_bit read :: tail)
    with ((6 :: (if target then 3 else 2) :: pre) ++
          [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
          source_bit read :: tail).
  2:{ rewrite Hsplit. repeat rewrite <- app_assoc. reflexivity. }
  rewrite (q0_tagged_control_pair_dispatches_target
    (6 :: (if target then 3 else 2) :: pre)
    (0 :: 6 :: 5 :: stored) tail c1 c2 read Hq0pre).
  reflexivity.
Qed.

Print Assumptions tagged_rail_left_buffered_native_tagged_target_dispatch.
