(** * Packaged leftward running step

    The rightward one-row macro is packaged in
    [MinskyCanonicalInstruction] as [canonical_return_step].  The
    leftward macro [canonical_q5_return_to_q5_left] has a different
    q20/q17 return path and a different data shift.  This module gives it
    the same kind of reusable interface.

    The record is a packaging of the exact native hypotheses; it is not
    an additional axiom.  The concrete encoder must still supply a
    witness for each source configuration.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyHeadMoveMacro
  MinskyRelocationMacro MinskyActionMacro MinskyCanonicalCopy
  MinskyCanonicalCopyGeneral MinskyCanonicalDirection
  MinskyCanonicalMatch MinskyCanonicalInstruction.

Record canonical_left_step := {
  cls_post : list nat;
  cls_pre : list nat;
  cls_bprev : bool;
  cls_data : list nat;
  cls_data_q6 : list nat;
  cls_data' : list nat;
  cls_symbol : nat;
  cls_remaining : list nat;
  cls_prefix : list nat;
  cls_hit : bool;
  cls_next_bit : bool;
  cls_next_tail : list nat;
  cls_q16map : list nat;
  cls_bits : list bool;
  cls_action_init : list bool;
  cls_tbuffer : list nat;
  cls_bnext : bool;
  cls_rest : list nat;
  cls_d : bool;
  cls_bit : bool;
  cls_tail : list nat;
  cls_s21 : nat;
  cls_rest21 : list nat;
  cls_tail' : list nat
}.

Definition canonical_left_marked (p : canonical_left_step) : list nat :=
  map match_mark (cls_bits p) ++
  map match_mark (cls_action_init p ++ [cls_bnext p]).

Definition canonical_left_step_start (p : canonical_left_step) : Config :=
  cfg_ml 5
    (rev (cls_post p) ++ 6 :: rev (cls_pre p) ++
     source_bit (cls_bprev p) :: rev (cls_data p))
    ((if cls_hit p then 3 else 2) ::
     map q16_restore (cls_q16map p) ++
     source_bit (cls_next_bit p) :: cls_next_tail p).

Definition canonical_left_step_end (p : canonical_left_step) : Config :=
  cfg_ml 5
    (rev (source_bit (cls_bnext p) ::
          rev (cls_s21 p :: cls_rest21 p)) ++
     6 :: rev (cls_data' p))
    ((if cls_d p then 3 else 2) ::
     map q16_restore
       (rev (2 :: rev (canonical_left_marked p) ++ [4])) ++
     source_bit (cls_bit p) :: cls_tail p).

Definition canonical_left_q5_q6_clock (p : canonical_left_step) : nat :=
  S (length (cls_symbol p :: cls_remaining p)) +
  matched_comparison_steps (cls_bits p) (length ([] : list nat))
    (length [4]) +
  S (length ([] ++ map match_raw (cls_bits p))).

Definition canonical_left_q6_q5_clock (p : canonical_left_step) : nat :=
  (copy_all_clock (cls_bits p) (cls_action_init p ++ [cls_bnext p])
     [] (map match_mark (cls_bits p)) +
   direction_clock
     (map match_mark (cls_bits p) ++
      map match_mark (cls_action_init p ++ [cls_bnext p]))
     (map match_mark (cls_action_init p ++ [cls_bnext p]))) +
  (S (length
       (match_mark (cls_bnext p) ::
        rev (map match_mark (cls_action_init p)) ++
        5 :: rev (cls_tbuffer p))) +
   S (length
       (cls_tbuffer p ++ [5] ++
        rev (rev (map match_mark (cls_action_init p))) ++
        [match_mark (cls_bnext p)])) +
   S (length ((map match_mark (cls_bits p) ++
               map match_mark (cls_action_init p ++ [cls_bnext p]))
              ++ [2])) +
   S (length
       (2 :: rev
         (map match_mark (cls_bits p) ++
          map match_mark (cls_action_init p ++ [cls_bnext p])) ++
        [4])) +
   S (length (cls_s21 p :: cls_rest21 p)) + 1 +
   S (length (source_bit (cls_bnext p) ::
              rev (cls_s21 p :: cls_rest21 p)))).

Definition canonical_left_step_clock (p : canonical_left_step) : nat :=
  canonical_left_q5_q6_clock p + canonical_left_q6_q5_clock p.

Record canonical_left_step_ok (p : canonical_left_step) : Prop := {
  clso_left :
    rev (cls_post p) ++ 6 :: rev (cls_pre p) ++
      source_bit (cls_bprev p) :: rev (cls_data p) =
    (cls_symbol p :: cls_remaining p) ++ 5 :: cls_prefix p;
  clso_scan :
    Forall canonical_q5_return_pass (cls_symbol p :: cls_remaining p);
  clso_rail :
    map entry_rewrite (rev (cls_symbol p :: cls_remaining p)) ++
      (if cls_hit p then 3 else 2) ::
      map q16_restore (cls_q16map p) ++
      source_bit (cls_next_bit p) :: cls_next_tail p =
    ([] : list nat) ++ map match_mark (cls_bits p) ++ [4] ++
    map match_raw (cls_bits p) ++ cls_tail' p;
  clso_tail :
    cls_tail' p =
    map source_bit (cls_action_init p ++ [cls_bnext p]) ++
    source_bit false :: cls_rest p;
  clso_prefix :
    cls_prefix p = rev (cls_tbuffer p) ++ 6 :: rev (cls_data_q6 p);
  clso_shift :
    rev (cls_data_q6 p) =
    rev (cls_pre p) ++ source_bit (cls_bprev p) :: rev (cls_data p);
  clso_len :
    length (cls_action_init p ++ [cls_bnext p]) = length (cls_bits p);
  clso_data :
    rev (cls_data_q6 p) = source_bit (cls_d p) :: rev (cls_data' p);
  clso_rest :
    cls_rest p = source_bit (cls_bit p) :: cls_tail p;
  clso_restored :
    map q14_restore
      (rev (map match_mark (cls_action_init p)) ++
       5 :: rev (cls_tbuffer p)) =
    cls_s21 p :: cls_rest21 p;
  clso_return :
    Forall q17_pass
      (source_bit (cls_bnext p) :: rev (cls_s21 p :: cls_rest21 p));
  clso_line12 :
    Forall q12_pass
      (match_mark (cls_bnext p) ::
       rev (map match_mark (cls_action_init p)) ++
       5 :: rev (cls_tbuffer p));
  clso_line14 :
    Forall q14_pass
      (cls_tbuffer p ++ [5] ++
       rev (rev (map match_mark (cls_action_init p))) ++
       [match_mark (cls_bnext p)])
}.

Theorem canonical_left_step_run :
  forall p,
    canonical_left_step_ok p ->
    run (canonical_left_step_clock p)
        (canonical_left_step_start p) =
    canonical_left_step_end p.
Proof.
  intros p H.
  destruct H as [Hleft Hscan Hrail Htail Hprefix Hshift Hlen Hdata
    Hrest Hrestored Hreturn H12r H14r].
  unfold canonical_left_step_clock, canonical_left_q5_q6_clock,
    canonical_left_q6_q5_clock, canonical_left_step_start,
    canonical_left_step_end, canonical_left_marked.
  apply (canonical_q5_return_to_q5_left
    (cls_post p) (cls_pre p) (cls_bprev p)
    (cls_data p) (cls_data_q6 p) (cls_data' p)
    (cls_symbol p) (cls_remaining p) (cls_prefix p) (cls_hit p)
    (cls_next_bit p) (cls_next_tail p) (cls_q16map p) (cls_bits p)
    (cls_action_init p) (cls_tbuffer p) (cls_bnext p) (cls_rest p)
    (cls_d p) (cls_bit p) (cls_tail p) (cls_s21 p) (cls_rest21 p)
    (cls_tail' p)
    Hleft Hscan Hrail Htail Hprefix Hshift Hlen Hdata Hrest
    Hrestored Hreturn H12r H14r).
Qed.

Print Assumptions canonical_left_step_run.

(** ** A left one-row family with arbitrary source tape data

    The same fixed two-bit instruction as the right witness family, but
    through the q20/q17 left return.  The data shift pops the written
    cell, so the next data list is the old one. *)

Definition canonical_left_witness_family
    (data : list nat) (bprev : bool) : canonical_left_step :=
  {| cls_post := [5; 2];
     cls_pre := [];
     cls_bprev := bprev;
     cls_data := data;
     cls_data_q6 := data ++ [source_bit bprev];
     cls_data' := data;
     cls_symbol := 2;
     cls_remaining := [];
     cls_prefix := [6] ++ source_bit bprev :: rev data;
     cls_hit := true;
     cls_next_bit := false;
     cls_next_tail := [1; 0; 0; 0; 1; 0];
     cls_q16map := [4];
     cls_bits := [false; true];
     cls_action_init := [false];
     cls_tbuffer := [];
     cls_bnext := false;
     cls_rest := [1; 0];
     cls_d := bprev;
     cls_bit := true;
     cls_tail := [0];
     cls_s21 := 0;
     cls_rest21 := [5];
     cls_tail' := [0; 0; 0; 1; 0] |}.

Lemma canonical_left_witness_family_ok :
  forall data bprev,
    canonical_left_step_ok (canonical_left_witness_family data bprev).
Proof.
  intros data bprev.
  unfold canonical_left_witness_family.
  constructor.
  - cbn. reflexivity.
  - cbn. constructor.
    + unfold canonical_q5_return_pass; auto 12.
    + constructor.
  - cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. rewrite rev_app_distr. cbn. reflexivity.
  - cbn. rewrite rev_app_distr. cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. rewrite rev_app_distr. cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. reflexivity.
  - cbn. repeat constructor; try (unfold q17_pass; auto 12); constructor.
  - cbn. repeat constructor; try (unfold q12_pass; auto 12); constructor.
  - cbn. repeat constructor; try (unfold q14_pass; auto 12); constructor.
Qed.

Theorem canonical_left_witness_family_run :
  forall data bprev,
    run (canonical_left_step_clock
           (canonical_left_witness_family data bprev))
        (canonical_left_step_start
           (canonical_left_witness_family data bprev)) =
    canonical_left_step_end
      (canonical_left_witness_family data bprev).
Proof.
  intros data bprev.
  apply canonical_left_step_run.
  apply canonical_left_witness_family_ok.
Qed.

Print Assumptions canonical_left_witness_family_ok.
Print Assumptions canonical_left_witness_family_run.
