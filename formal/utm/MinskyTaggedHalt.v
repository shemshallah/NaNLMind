(** * Tagged halt hook

    The frozen table has exactly one halting transition: q3 on Y=5.
    The verified tagged left cycle sends a target=true dispatch to q3;
    if the right tail is a q3-passable list followed by 5, the machine
    halts.  This is a native halt macro from the tagged q15 entry.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyActionMacro
  MinskyWritebackMacro MinskyHeadMoveMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyDirectionCycle MinskyWideSource
  MinskyConcreteDispatch MinskyWideConcreteDispatch
  MinskyDirectionRelocationCycle.

Definition q3_halt_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 6 \/ s = 7.

Lemma q3_halt_pass_step :
  forall s left right,
    q3_halt_pass s ->
    step (entry_config 3 left (s :: right)) =
    entry_config 3 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q3_five_halts :
  forall left tail,
    c_halted (step (entry_config 3 left (5 :: tail))) = true.
Proof. intros left tail. reflexivity. Qed.

Theorem q3_scan_to_five_halts :
  forall scanned left tail,
    Forall q3_halt_pass scanned ->
    c_halted
      (run (S (length scanned))
        (entry_config 3 left (scanned ++ 5 :: tail))) = true.
Proof.
  induction scanned as [|s rest IH];
    intros left tail Hscan.
  - cbn [length app run].
    apply q3_five_halts.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    cbn [length app].
    change (c_halted
      (run (S (length rest))
        (step (entry_config 3 left
          (s :: rest ++ 5 :: tail)))) = true).
    rewrite (q3_halt_pass_step s left (rest ++ 5 :: tail) Hs).
    apply IH. exact Hrest.
Qed.

(** Target=true tagged left dispatch reaches q3; a passable tail then
    Y=5 halts the machine in 21 + S |tail| native steps. *)
Theorem q15_left_false_guard_halt :
  forall (old next extra : bool) (outer scanned tail : list nat),
    Forall q3_halt_pass scanned ->
    c_halted
      (run (21 + S (length scanned))
        (entry_config 15
          (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
          (q0_stable_control_tag next ::
           q0_stable_control_tag extra :: source_bit true ::
           scanned ++ 5 :: tail))) = true.
Proof.
  intros old next extra outer scanned tail Hscan.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_target_dispatch
    old next extra true outer (scanned ++ 5 :: tail)).
  apply q3_scan_to_five_halts. exact Hscan.
Qed.

Print Assumptions q3_scan_to_five_halts.
Print Assumptions q15_left_false_guard_halt.


(** Local copy of the 4-prefix bridge, kept here so this module only
    depends on the tagged cycle file. *)
Theorem q15_q16_four_prefix_roundtrip_local :
  forall (old target : bool) (tags left suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run (S (length (rev tags)) + S (length (tags ++ [4])))
      (entry_config 15 (4 :: source_bit old :: left)
        (rev tags ++ source_bit target :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit target :: suffix).
Proof.
  intros old target tags left suffix H15 H16.
  rewrite dispatch_run_add.
  rewrite (q15_scan_to_raw (rev tags) target
    (4 :: source_bit old :: left) suffix H15).
  rewrite rev_involutive.
  replace (tags ++ 4 :: source_bit old :: left)
    with ((tags ++ [4]) ++ source_bit old :: left)
    by (rewrite <- app_assoc; reflexivity).
  destruct (tags ++ [4]) as [|s remaining] eqn:H.
  - assert (Hlen : length (tags ++ [4]) = 0)
      by (rewrite H; reflexivity).
    rewrite length_app in Hlen. cbn [length] in Hlen. lia.
  - assert (H16' : Forall q16_pass (s :: remaining)) by exact H16.
    cbn [app cfg_ml].
    rewrite (q16_restore_to_raw remaining s old left
      (source_bit target :: suffix) H16').
    reflexivity.
Qed.

Lemma map_q16_restore_four_prefix :
  forall tags,
    map q16_restore (rev (tags ++ [4])) =
    4 :: map q16_restore (rev tags).
Proof.
  intros tags.
  rewrite rev_app_distr. cbn [rev].
  reflexivity.
Qed.

Theorem q15_q22_right_four_prefix_to_q19 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (rev (map q0_stable_control_tag (first :: rest)))) +
         S (length
           (map q0_stable_control_tag (first :: rest) ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix).
Proof.
  intros first rest dir_head dir_remaining old target outer suffix H21.
  assert (H15 : Forall q15_pass
      (rev (map q0_stable_control_tag (first :: rest)))).
  { apply q15_stable_control_rail_reverse_safe. }
  assert (H16 : Forall q16_pass
      (map q0_stable_control_tag (first :: rest) ++ [4])).
  {
    rewrite Forall_app. split.
    - apply q16_stable_control_rail_safe.
    - constructor.
      + unfold q16_pass; auto 12.
      + constructor.
  }
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22)
    by (destruct old; simpl; auto).
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip_local old target
    (map q0_stable_control_tag (first :: rest))
    (dir_head :: dir_remaining ++ 3 :: outer) suffix H15 H16).
  rewrite map_q16_restore_four_prefix.
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head ::
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))) ++
       source_bit target :: suffix)).
  rewrite (q21_scan_to_right_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: 4 ::
     map q16_restore
       (rev (map q0_stable_control_tag (first :: rest))) ++
     source_bit target :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Print Assumptions q15_q22_right_four_prefix_to_q19.

(** Full right return with the canonical 4-prefix: q15 -> q16 ->
    q21/q22 -> q19 -> q17/q18 -> q5.  The 4-prefix travels in the
    restored rail and does not stop q19. *)
Theorem q15_q22_right_four_prefix_relocates_to_q5 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target outer between tail,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    run ((S (length (rev (map q0_stable_control_tag (first :: rest)))) +
          S (length
            (map q0_stable_control_tag (first :: rest) ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (S (length
           (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest))))) +
          S (length between)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 :: tail)) =
    cfg_ml 5
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       source_bit old :: outer)
      ((if target then 3 else 2) :: tail).
Proof.
  intros first rest dir_head dir_remaining old target outer between tail
    H21 Hdir15 Hbetween.
  assert (Hscan : Forall q15_pass
      (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest))))).
  {
    rewrite Forall_app. split.
    - exact Hdir15.
    - constructor.
      + unfold q15_pass; auto 12.
      + constructor.
        * unfold q15_pass; auto 12.
        * rewrite map_rev.
          rewrite q16_stable_control_rail_restore_identity.
          apply q15_stable_control_rail_reverse_safe.
  }
  rewrite dispatch_run_add.
  rewrite (q15_q22_right_four_prefix_to_q19 first rest
    dir_head dir_remaining old target outer (between ++ 7 :: tail) H21).
  replace (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
           map q16_restore
             (rev (map q0_stable_control_tag (first :: rest))) ++
           source_bit target :: between ++ 7 :: tail)
    with ((rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
           map q16_restore
             (rev (map q0_stable_control_tag (first :: rest)))) ++
          source_bit target :: between ++ 7 :: tail)
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite (q19_to_q5_relocation
    (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
     map q16_restore
       (rev (map q0_stable_control_tag (first :: rest))))
    between target (source_bit old :: outer) tail Hscan Hbetween).
  reflexivity.
Qed.

Print Assumptions q15_q22_right_four_prefix_relocates_to_q5.

(** q5 rail scan after the 4-prefix right return.  A 5 delimiter is
    supplied in the outer tape; q5 scans the rail to it and returns q1. *)
Theorem q15_q22_right_four_prefix_q5_q1 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target between tail stored,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit old]) ->
    run (((S (length
              (rev (map q0_stable_control_tag (first :: rest)))) +
           S (length
             (map q0_stable_control_tag (first :: rest) ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (S (length
            (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
             map q16_restore
               (rev (map q0_stable_control_tag (first :: rest))))) +
           S (length between))) +
         S (length
           (rev between ++ 6 ::
            rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                 map q16_restore
                   (rev (map q0_stable_control_tag (first :: rest)))) ++
            [source_bit old])))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 :: tail)) =
    entry_config 1 (5 :: stored)
      (map entry_rewrite
        (rev
          (rev between ++ 6 ::
           rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                map q16_restore
                  (rev (map q0_stable_control_tag (first :: rest)))) ++
           [source_bit old])) ++
       (if target then 3 else 2) :: tail).
Proof.
  intros first rest dir_head dir_remaining old target between tail stored
    H21 Hdir15 Hbetween Hpass.
  set (scanned :=
    rev between ++ 6 ::
    rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
         map q16_restore
           (rev (map q0_stable_control_tag (first :: rest)))) ++
    [source_bit old]).
  assert (Hnonempty : scanned <> []).
  {
    intro H.
    assert (Hl : length scanned = 0) by (rewrite H; reflexivity).
    unfold scanned in Hl. rewrite length_app in Hl.
    cbn [length] in Hl. lia.
  }
  rewrite dispatch_run_add.
  rewrite (q15_q22_right_four_prefix_relocates_to_q5 first rest
    dir_head dir_remaining old target (5 :: stored) between tail
    H21 Hdir15 Hbetween).
  assert (Hsplit :
    rev between ++ 6 ::
    rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
         map q16_restore
           (rev (map q0_stable_control_tag (first :: rest)))) ++
    source_bit old :: 5 :: stored =
    scanned ++ 5 :: stored).
  {
    unfold scanned.
    repeat rewrite <- app_assoc.
    cbn [app].
    repeat rewrite <- app_assoc.
    reflexivity.
  }
  rewrite Hsplit.
  destruct scanned as [|s rest'] eqn:HS.
  - contradiction.
  - assert (Hpass' : Forall q5_return_pass (s :: rest')).
    { rewrite <- HS. exact Hpass. }
    change (run (S (length (s :: rest')))
      (entry_config 5 (rest' ++ 5 :: stored)
        (s :: (if target then 3 else 2) :: tail)) =
      entry_config 1 (5 :: stored)
        (map entry_rewrite (rev (s :: rest')) ++
         (if target then 3 else 2) :: tail)).
    apply (q5_return_scan_to_first_five rest' s stored
      ((if target then 3 else 2) :: tail) Hpass').
Qed.

Print Assumptions q15_q22_right_four_prefix_q5_q1.

Lemma map_entry_rewrite_snoc :
  forall (A : list nat) (x : nat),
    map entry_rewrite (rev (A ++ [x])) =
    entry_rewrite x :: map entry_rewrite (rev A).
Proof.
  intros A x.
  rewrite rev_app_distr. cbn [rev].
  rewrite map_app. cbn [map]. reflexivity.
Qed.

Lemma q1_old_mark_step :
  forall (old : bool) (left rest : list nat),
    step (entry_config 1 left (entry_rewrite (source_bit old) :: rest)) =
    if old
    then entry_config 4 (1 :: left) rest
    else entry_config 0 (0 :: left) rest.
Proof. intros old left rest. destruct old; reflexivity. Qed.



Theorem q15_q22_right_four_prefix_q1_step :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old target between tail stored,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit old]) ->
    run ((((S (length
               (rev (map q0_stable_control_tag (first :: rest)))) +
            S (length
              (map q0_stable_control_tag (first :: rest) ++ [4])) +
            S (length (dir_head :: dir_remaining))) +
           (S (length
             (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
              map q16_restore
                (rev (map q0_stable_control_tag (first :: rest))))) +
            S (length between))) +
          S (length
            (rev between ++ 6 ::
             rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                  map q16_restore
                    (rev (map q0_stable_control_tag (first :: rest)))) ++
             [source_bit old]))) + 1)
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 :: tail)) =
    if old
    then entry_config 4 (1 :: 5 :: stored)
      (map entry_rewrite
        (rev
          (rev between ++ 6 ::
           rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                map q16_restore
                  (rev (map q0_stable_control_tag (first :: rest)))))) ++
       (if target then 3 else 2) :: tail)
    else entry_config 0 (0 :: 5 :: stored)
      (map entry_rewrite
        (rev
          (rev between ++ 6 ::
           rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                map q16_restore
                  (rev (map q0_stable_control_tag (first :: rest)))))) ++
       (if target then 3 else 2) :: tail).
Proof.
  intros first rest dir_head dir_remaining old target between tail stored
    H21 Hdir15 Hbetween Hpass.
  rewrite dispatch_run_add.
  rewrite (q15_q22_right_four_prefix_q5_q1 first rest
    dir_head dir_remaining old target between tail stored
    H21 Hdir15 Hbetween Hpass).
  replace (rev between ++ 6 ::
           rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                map q16_restore
                  (rev (map q0_stable_control_tag (first :: rest)))) ++
           [source_bit old])
    with ((rev between ++ 6 ::
           rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                map q16_restore
                  (rev (map q0_stable_control_tag (first :: rest))))) ++
          [source_bit old])
    by (rewrite <- app_assoc; cbn [app]; reflexivity).
  rewrite map_entry_rewrite_snoc.
  match goal with
  | |- _ = ?expected =>
    change (step
      (entry_config 1 (5 :: stored)
        (entry_rewrite (source_bit old) ::
         map entry_rewrite
           (rev
             (rev between ++ 6 ::
              rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
                   map q16_restore
                     (rev (map q0_stable_control_tag (first :: rest)))))) ++
         (if target then 3 else 2) :: tail)) = expected)
  end.
  apply q1_old_mark_step.
Qed.

Print Assumptions q15_q22_right_four_prefix_q1_step.

(** q0 target dispatch over a returned rail: the pass prefix is the
    rewritten rail plus the relocated old mark, followed by two stable
    control tags and the raw target. *)
Theorem q0_right_rail_target_dispatch :
  forall (prefix : list nat) (mark : nat)
         (c1 c2 read : bool) (stored tail : list nat),
    Forall q0_pass (prefix ++ [mark]) ->
    run (length (prefix ++ [mark]) + 3)
      (entry_config 0 (0 :: 5 :: stored)
        ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit read :: tail)) =
    if read
    then entry_config 3
      (3 :: rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 5 :: stored) tail
    else cfg_ml 2
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 5 :: stored) (2 :: tail).
Proof.
  intros prefix mark c1 c2 read stored tail Hprefix.
  apply (q0_tagged_control_pair_dispatches_target
    (prefix ++ [mark]) (0 :: 5 :: stored) tail c1 c2 read Hprefix).
Qed.

Print Assumptions q0_right_rail_target_dispatch.

(** q4 mirrored target dispatch over the returned rail.  q4 on the raw
    target writes the opposite mark and moves right (0 -> q3) or left
    (1 -> q2).  Split into the two direct scan cases. *)
Theorem q4_right_rail_target_zero :
  forall (prefix : list nat) (mark : nat)
         (c1 c2 : bool) (stored tail : list nat),
    Forall q4_pass ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2]) ->
    run (S (length ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2])))
      (entry_config 4 (1 :: 5 :: stored)
        (((prefix ++ [mark]) ++
          [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
         0 :: tail)) =
    entry_config 3
      (2 :: rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       1 :: 5 :: stored) tail.
Proof.
  intros prefix mark c1 c2 stored tail Hpass.
  apply (q4_scan_zero ((prefix ++ [mark]) ++
    [q0_stable_control_tag c1; q0_stable_control_tag c2])
    (1 :: 5 :: stored) tail Hpass).
Qed.

Theorem q4_right_rail_target_one :
  forall (prefix : list nat) (mark : nat)
         (c1 c2 : bool) (stored tail : list nat),
    Forall q4_pass ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2]) ->
    run (S (length ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2])))
      (entry_config 4 (1 :: 5 :: stored)
        (((prefix ++ [mark]) ++
          [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
         1 :: tail)) =
    cfg_ml 2
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       1 :: 5 :: stored) (3 :: tail).
Proof.
  intros prefix mark c1 c2 stored tail Hpass.
  apply (q4_scan_one ((prefix ++ [mark]) ++
    [q0_stable_control_tag c1; q0_stable_control_tag c2])
    (1 :: 5 :: stored) tail Hpass).
Qed.

Print Assumptions q4_right_rail_target_zero.
Print Assumptions q4_right_rail_target_one.

(** q3 reentry: scan right over dispatch_right_symbols to X=4 and enter
    q5 for the next row. *)
Theorem q3_scan_to_q5 :
  forall (left symbols suffix : list nat),
    Forall dispatch_right_symbol symbols ->
    run (length symbols + 1)
      (entry_config 3 left (symbols ++ 4 :: suffix)) =
    cfg_ml 5 (rev symbols ++ left) (4 :: suffix).
Proof.
  intros left symbols suffix Hsymbols.
  rewrite (q3_reaches_marker symbols left suffix Hsymbols).
  apply q3_at_marker_step.
Qed.

(** q2 reentry: from a cfg_ml with a 5 delimiter in the left tape, scan
    left to the delimiter and enter q1. *)
Theorem q2_rail_reenter_q1 :
  forall (rail : list nat) (mark : nat) (stored : list nat)
         (right : list nat),
    Forall dispatch_left_symbol (rail ++ [mark]) ->
    run (S (length (rail ++ [mark])))
      (cfg_ml 2 (rail ++ mark :: 5 :: stored) right) =
    entry_config 1 (5 :: stored) (rev (rail ++ [mark]) ++ right).
Proof.
  intros rail mark stored right Hscan.
  destruct rail as [|r rest].
  - change (run (S (length (mark :: [])))
      (entry_config 2 ([] ++ 5 :: stored) (mark :: right)) =
      entry_config 1 (5 :: stored)
        (rev (mark :: []) ++ right)).
    apply (dispatch_left_to_delimiter [] mark stored right Hscan).
  - change (run (S (length (r :: rest ++ [mark])))
      (entry_config 2 (rest ++ mark :: 5 :: stored) (r :: right)) =
      entry_config 1 (5 :: stored)
        (rev (r :: rest ++ [mark]) ++ right)).
    replace (rest ++ mark :: 5 :: stored)
      with ((rest ++ [mark]) ++ 5 :: stored)
      by (rewrite <- app_assoc; reflexivity).
    apply (dispatch_left_to_delimiter (rest ++ [mark]) r stored right Hscan).
Qed.

Print Assumptions q3_scan_to_q5.
Print Assumptions q2_rail_reenter_q1.

Lemma rev_snoc_singleton :
  forall (l : list nat) (x : nat),
    rev (l ++ [x]) = x :: rev l.
Proof.
  intros l x.
  rewrite rev_app_distr. cbn [rev].
  reflexivity.
Qed.

(** q0 read-zero: target dispatch to q3, then q3 scans to X=4 and
    reenters q5. *)
Theorem q0_rail_read_one_to_q5 :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q0_pass (prefix ++ [mark]) ->
    Forall dispatch_right_symbol symbols ->
    run ((length (prefix ++ [mark]) + 3) +
         (length symbols + 1))
      (entry_config 0 (0 :: 5 :: stored)
        ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit true :: symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++ 3 ::
       rev ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 5 :: stored) (4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix H0 Hsym.
  rewrite dispatch_run_add.
  rewrite (q0_right_rail_target_dispatch prefix mark c1 c2 true
    stored (symbols ++ 4 :: suffix) H0).
  eapply q3_scan_to_q5. exact Hsym.
Qed.

(** q0 read-one: target dispatch to q2, then q2 scans left to the 5
    delimiter and reenters q1. *)
Theorem q0_rail_read_zero_to_q1 :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q0_pass (prefix ++ [mark]) ->
    Forall dispatch_left_symbol
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0]) ->
    run ((length (prefix ++ [mark]) + 3) +
         S (length (rev ((prefix ++ [mark]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0])))
      (entry_config 0 (0 :: 5 :: stored)
        ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit false :: symbols ++ 4 :: suffix)) =
    entry_config 1 (5 :: stored)
      (0 :: ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       2 :: symbols ++ 4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix H0 Hleft.
  rewrite dispatch_run_add.
  rewrite (q0_right_rail_target_dispatch prefix mark c1 c2 false
    stored (symbols ++ 4 :: suffix) H0).
  rewrite (q2_rail_reenter_q1
    (rev ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2]))
    0 stored (2 :: symbols ++ 4 :: suffix) Hleft).
  rewrite rev_snoc_singleton.
  rewrite rev_involutive. reflexivity.
Qed.

(** q4 target-zero: mirrored target dispatch to q3, then q3 -> q5. *)
Theorem q4_rail_read_zero_to_q5 :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q4_pass (prefix ++ [mark]) ->
    Forall dispatch_right_symbol symbols ->
    run (S (length ((prefix ++ [mark]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
         (length symbols + 1))
      (entry_config 4 (1 :: 5 :: stored)
        (((prefix ++ [mark]) ++
          [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
         0 :: symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++ 2 ::
       rev ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       1 :: 5 :: stored) (4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix H4 Hsym.
  assert (H4full : Forall q4_pass
      ((prefix ++ [mark]) ++
       [q0_stable_control_tag c1; q0_stable_control_tag c2])).
  { rewrite Forall_app. split.
    - exact H4.
    - constructor.
      + destruct c1; unfold q4_pass, q0_stable_control_tag; auto 12.
      + constructor.
        * destruct c2; unfold q4_pass, q0_stable_control_tag; auto 12.
        * constructor. }
  rewrite dispatch_run_add.
  rewrite (q4_right_rail_target_zero prefix mark c1 c2
    stored (symbols ++ 4 :: suffix) H4full).
  eapply q3_scan_to_q5. exact Hsym.
Qed.

(** q4 target-one: mirrored target dispatch to q2, then q2 -> q1. *)
Theorem q4_rail_read_one_to_q1 :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q4_pass (prefix ++ [mark]) ->
    Forall dispatch_left_symbol
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1]) ->
    run (S (length ((prefix ++ [mark]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
         S (length (rev ((prefix ++ [mark]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1])))
      (entry_config 4 (1 :: 5 :: stored)
        (((prefix ++ [mark]) ++
          [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
         1 :: symbols ++ 4 :: suffix)) =
    entry_config 1 (5 :: stored)
      (1 :: ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       3 :: symbols ++ 4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix H4 Hleft.
  assert (H4full : Forall q4_pass
      ((prefix ++ [mark]) ++
       [q0_stable_control_tag c1; q0_stable_control_tag c2])).
  { rewrite Forall_app. split.
    - exact H4.
    - constructor.
      + destruct c1; unfold q4_pass, q0_stable_control_tag; auto 12.
      + constructor.
        * destruct c2; unfold q4_pass, q0_stable_control_tag; auto 12.
        * constructor. }
  rewrite dispatch_run_add.
  rewrite (q4_right_rail_target_one prefix mark c1 c2
    stored (symbols ++ 4 :: suffix) H4full).
  rewrite (q2_rail_reenter_q1
    (rev ((prefix ++ [mark]) ++
      [q0_stable_control_tag c1; q0_stable_control_tag c2]))
    1 stored (3 :: symbols ++ 4 :: suffix) Hleft).
  rewrite rev_snoc_singleton.
  rewrite rev_involutive. reflexivity.
Qed.

Print Assumptions q0_rail_read_one_to_q5.
Print Assumptions q0_rail_read_zero_to_q1.
Print Assumptions q4_rail_read_zero_to_q5.
Print Assumptions q4_rail_read_one_to_q1.



Definition right_rail_map
    (first : bool) (rest : list bool)
    (dir_head : nat) (dir_remaining between : list nat) : list nat :=
  map entry_rewrite
    (rev
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))))).

Definition right_q1_step_clock
    (first : bool) (rest : list bool)
    (dir_head : nat) (dir_remaining between : list nat)
    (old : bool) : nat :=
  ((((S (length
          (rev (map q0_stable_control_tag (first :: rest)))) +
       S (length
         (map q0_stable_control_tag (first :: rest) ++ [4])) +
       S (length (dir_head :: dir_remaining))) +
      (S (length
        (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
         map q16_restore
           (rev (map q0_stable_control_tag (first :: rest))))) +
       S (length between))) +
     S (length
       (rev between ++ 6 ::
        rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
             map q16_restore
               (rev (map q0_stable_control_tag (first :: rest)))) ++
        [source_bit old]))) + 1).

Lemma cons_append_split :
  forall (a : list nat) (x : nat) (b c : list nat),
    a ++ x :: (b ++ c) = ((a ++ [x]) ++ b) ++ c.
Proof.
  intros a x b c.
  cbn [app]. repeat rewrite <- app_assoc. reflexivity.
Qed.

Definition right_mark (target : bool) : nat :=
  if target then 3 else 2.



Lemma q1_out_to_q0_frame :
  forall (a : list nat) (x : nat) (b c : list nat),
    a ++ x :: (b ++ c) = (a ++ [x]) ++ (b ++ c).
Proof.
  intros a x b c. rewrite <- app_assoc. reflexivity.
Qed.

(** q0/read-zero when the input is already in the q1-step output form. *)
Lemma q0_read_zero_from_q1_output :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q0_pass (prefix ++ [mark]) ->
    Forall dispatch_left_symbol
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0]) ->
    run ((length (prefix ++ [mark]) + 3) +
         S (length (rev ((prefix ++ [mark]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0])))
      (entry_config 0 (0 :: 5 :: stored)
        (prefix ++ mark ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit false :: (symbols ++ 4 :: suffix))) =
    entry_config 1 (5 :: stored)
      (0 :: ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       2 :: symbols ++ 4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix Hp Hl.
  rewrite (q1_out_to_q0_frame prefix mark
    [q0_stable_control_tag c1; q0_stable_control_tag c2]
    (source_bit false :: (symbols ++ 4 :: suffix))).
  apply (q0_rail_read_zero_to_q1 prefix mark c1 c2 stored symbols
    suffix Hp Hl).
Qed.

Print Assumptions q0_read_zero_from_q1_output.

(** Full right loop for q0/read-zero: q15 -> q22 -> q19 -> q17/q18
    -> q5 -> q1 -> q0 -> q2 -> q1. *)
Theorem q15_right_loop_q0_read0 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining target between stored
         (c1 c2 : bool) symbols suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit false]) ->
    Forall q0_pass
      (right_rail_map first rest dir_head dir_remaining between ++
       [right_mark target]) ->
    Forall dispatch_left_symbol
      (rev
        ((right_rail_map first rest dir_head dir_remaining between ++
          [right_mark target]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0]) ->
    run
      (right_q1_step_clock first rest dir_head dir_remaining between false +
       ((length
          (right_rail_map first rest dir_head dir_remaining between ++
           [right_mark target]) + 3) +
        S (length
          (rev
            ((right_rail_map first rest dir_head dir_remaining between ++
              [right_mark target]) ++
             [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [0]))))
      (entry_config 15
        (4 :: source_bit false :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit false :: (symbols ++ 4 :: suffix))) =
    entry_config 1 (5 :: stored)
      (0 ::
       ((right_rail_map first rest dir_head dir_remaining between ++
         [right_mark target]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       2 :: symbols ++ 4 :: suffix).
Proof.
  intros first rest dir_head dir_remaining target between stored
    c1 c2 symbols suffix H21 Hdir15 Hbetween Hpass Hprefix Hleft.
  rewrite dispatch_run_add.
  unfold right_q1_step_clock.
  rewrite (q15_q22_right_four_prefix_q1_step first rest
    dir_head dir_remaining false target between
    ([q0_stable_control_tag c1; q0_stable_control_tag c2] ++
     (source_bit false :: (symbols ++ 4 :: suffix))) stored
    H21 Hdir15 Hbetween Hpass).
  apply (q0_read_zero_from_q1_output
    (right_rail_map first rest dir_head dir_remaining between)
    (if target then 3 else 2) c1 c2 stored symbols suffix
    Hprefix Hleft).
Qed.

Print Assumptions q15_right_loop_q0_read0.



Lemma q0_read_one_from_q1_output :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q0_pass (prefix ++ [mark]) ->
    Forall dispatch_right_symbol symbols ->
    run ((length (prefix ++ [mark]) + 3) + (length symbols + 1))
      (entry_config 0 (0 :: 5 :: stored)
        (prefix ++ mark ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit true :: (symbols ++ 4 :: suffix))) =
    cfg_ml 5
      (rev symbols ++ 3 ::
       rev ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 5 :: stored) (4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix Hp Hsym.
  rewrite (q1_out_to_q0_frame prefix mark
    [q0_stable_control_tag c1; q0_stable_control_tag c2]
    (source_bit true :: (symbols ++ 4 :: suffix))).
  apply (q0_rail_read_one_to_q5 prefix mark c1 c2 stored symbols
    suffix Hp Hsym).
Qed.

Lemma q4_read_zero_from_q1_output :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q4_pass (prefix ++ [mark]) ->
    Forall dispatch_right_symbol symbols ->
    run (S (length ((prefix ++ [mark]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
         (length symbols + 1))
      (entry_config 4 (1 :: 5 :: stored)
        (prefix ++ mark ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit false :: (symbols ++ 4 :: suffix))) =
    cfg_ml 5
      (rev symbols ++ 2 ::
       rev ((prefix ++ [mark]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       1 :: 5 :: stored) (4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix Hp Hsym.
  rewrite (cons_append_split prefix mark
    [q0_stable_control_tag c1; q0_stable_control_tag c2]
    (source_bit false :: (symbols ++ 4 :: suffix))).
  apply (q4_rail_read_zero_to_q5 prefix mark c1 c2 stored symbols
    suffix Hp Hsym).
Qed.

Lemma q4_read_one_from_q1_output :
  forall (prefix : list nat) (mark : nat) (c1 c2 : bool)
         (stored symbols suffix : list nat),
    Forall q4_pass (prefix ++ [mark]) ->
    Forall dispatch_left_symbol
      (rev ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1]) ->
    run (S (length ((prefix ++ [mark]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
         S (length (rev ((prefix ++ [mark]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1])))
      (entry_config 4 (1 :: 5 :: stored)
        (prefix ++ mark ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit true :: (symbols ++ 4 :: suffix))) =
    entry_config 1 (5 :: stored)
      (1 :: ((prefix ++ [mark]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       3 :: symbols ++ 4 :: suffix).
Proof.
  intros prefix mark c1 c2 stored symbols suffix Hp Hleft.
  rewrite (cons_append_split prefix mark
    [q0_stable_control_tag c1; q0_stable_control_tag c2]
    (source_bit true :: (symbols ++ 4 :: suffix))).
  apply (q4_rail_read_one_to_q1 prefix mark c1 c2 stored symbols
    suffix Hp Hleft).
Qed.

Print Assumptions q0_read_one_from_q1_output.
Print Assumptions q4_read_zero_from_q1_output.
Print Assumptions q4_read_one_from_q1_output.

(** Full right loop, q0/read-one: q15 -> ... -> q1 -> q0 -> q3 -> q5. *)
Theorem q15_right_loop_q0_read1 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining target between stored
         (c1 c2 : bool) symbols suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit false]) ->
    Forall q0_pass
      (right_rail_map first rest dir_head dir_remaining between ++
       [right_mark target]) ->
    Forall dispatch_right_symbol symbols ->
    run
      (right_q1_step_clock first rest dir_head dir_remaining between false +
       ((length
          (right_rail_map first rest dir_head dir_remaining between ++
           [right_mark target]) + 3) +
        (length symbols + 1)))
      (entry_config 15
        (4 :: source_bit false :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit true :: (symbols ++ 4 :: suffix))) =
    cfg_ml 5
      (rev symbols ++ 3 ::
       rev ((right_rail_map first rest dir_head dir_remaining between ++
             [right_mark target]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       0 :: 5 :: stored) (4 :: suffix).
Proof.
  intros first rest dir_head dir_remaining target between stored
    c1 c2 symbols suffix H21 Hdir15 Hbetween Hpass Hprefix Hsym.
  rewrite dispatch_run_add.
  unfold right_q1_step_clock.
  rewrite (q15_q22_right_four_prefix_q1_step first rest
    dir_head dir_remaining false target between
    ([q0_stable_control_tag c1; q0_stable_control_tag c2] ++
     source_bit true :: (symbols ++ 4 :: suffix)) stored
    H21 Hdir15 Hbetween Hpass).
  fold (right_rail_map first rest dir_head dir_remaining between).
  replace (if target then 3 else 2) with (right_mark target) by reflexivity.
  apply (q0_read_one_from_q1_output
    (right_rail_map first rest dir_head dir_remaining between)
    (right_mark target) c1 c2 stored symbols suffix Hprefix Hsym).
Qed.

(** Full right loop, q4/read-zero: q15 -> ... -> q1 -> q4 -> q3 -> q5. *)
Theorem q15_right_loop_q4_read0 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining target between stored
         (c1 c2 : bool) symbols suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit true]) ->
    Forall q4_pass
      (right_rail_map first rest dir_head dir_remaining between ++
       [right_mark target]) ->
    Forall dispatch_right_symbol symbols ->
    run
      (right_q1_step_clock first rest dir_head dir_remaining between true +
       (S (length
          ((right_rail_map first rest dir_head dir_remaining between ++
            [right_mark target]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
        (length symbols + 1)))
      (entry_config 15
        (4 :: source_bit true :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit false :: (symbols ++ 4 :: suffix))) =
    cfg_ml 5
      (rev symbols ++ 2 ::
       rev ((right_rail_map first rest dir_head dir_remaining between ++
             [right_mark target]) ++
            [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       1 :: 5 :: stored) (4 :: suffix).
Proof.
  intros first rest dir_head dir_remaining target between stored
    c1 c2 symbols suffix H21 Hdir15 Hbetween Hpass Hprefix Hsym.
  rewrite dispatch_run_add.
  unfold right_q1_step_clock.
  rewrite (q15_q22_right_four_prefix_q1_step first rest
    dir_head dir_remaining true target between
    ([q0_stable_control_tag c1; q0_stable_control_tag c2] ++
     source_bit false :: (symbols ++ 4 :: suffix)) stored
    H21 Hdir15 Hbetween Hpass).
  fold (right_rail_map first rest dir_head dir_remaining between).
  replace (if target then 3 else 2) with (right_mark target) by reflexivity.
  apply (q4_read_zero_from_q1_output
    (right_rail_map first rest dir_head dir_remaining between)
    (right_mark target) c1 c2 stored symbols suffix Hprefix Hsym).
Qed.

(** Full right loop, q4/read-one: q15 -> ... -> q1 -> q4 -> q2 -> q1. *)
Theorem q15_right_loop_q4_read1 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining target between stored
         (c1 c2 : bool) symbols suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q15_pass (rev (dir_head :: dir_remaining)) ->
    Forall q17_pass between ->
    Forall q5_return_pass
      (rev between ++ 6 ::
       rev (rev (dir_head :: dir_remaining) ++ 7 :: 4 ::
            map q16_restore
              (rev (map q0_stable_control_tag (first :: rest)))) ++
       [source_bit true]) ->
    Forall q4_pass
      (right_rail_map first rest dir_head dir_remaining between ++
       [right_mark target]) ->
    Forall dispatch_left_symbol
      (rev
        ((right_rail_map first rest dir_head dir_remaining between ++
          [right_mark target]) ++
         [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1]) ->
    run
      (right_q1_step_clock first rest dir_head dir_remaining between true +
       (S (length
          ((right_rail_map first rest dir_head dir_remaining between ++
            [right_mark target]) ++
           [q0_stable_control_tag c1; q0_stable_control_tag c2])) +
        S (length
          (rev
            ((right_rail_map first rest dir_head dir_remaining between ++
              [right_mark target]) ++
             [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++ [1]))))
      (entry_config 15
        (4 :: source_bit true :: dir_head :: dir_remaining ++
         3 :: 5 :: stored)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit target :: between ++ 7 ::
         [q0_stable_control_tag c1; q0_stable_control_tag c2] ++
         source_bit true :: (symbols ++ 4 :: suffix))) =
    entry_config 1 (5 :: stored)
      (1 ::
       ((right_rail_map first rest dir_head dir_remaining between ++
         [right_mark target]) ++
        [q0_stable_control_tag c1; q0_stable_control_tag c2]) ++
       3 :: symbols ++ 4 :: suffix).
Proof.
  intros first rest dir_head dir_remaining target between stored
    c1 c2 symbols suffix H21 Hdir15 Hbetween Hpass Hprefix Hleft.
  rewrite dispatch_run_add.
  unfold right_q1_step_clock.
  rewrite (q15_q22_right_four_prefix_q1_step first rest
    dir_head dir_remaining true target between
    ([q0_stable_control_tag c1; q0_stable_control_tag c2] ++
     source_bit true :: (symbols ++ 4 :: suffix)) stored
    H21 Hdir15 Hbetween Hpass).
  fold (right_rail_map first rest dir_head dir_remaining between).
  replace (if target then 3 else 2) with (right_mark target) by reflexivity.
  apply (q4_read_one_from_q1_output
    (right_rail_map first rest dir_head dir_remaining between)
    (right_mark target) c1 c2 stored symbols suffix Hprefix Hleft).
Qed.

Print Assumptions q15_right_loop_q0_read1.
Print Assumptions q15_right_loop_q4_read0.
Print Assumptions q15_right_loop_q4_read1.

(** ** Complete left loops

    The tagged left cycle is a 21-step native run from a supplied q15
    frame to q3 (target=true) or q2 (target=false).  Composing with the
    verified q3->q5 and q2->q1 reentries yields the two complete left
    loops from the tagged movement entry back to the next q1/q5 phase. *)

Lemma q0_stable_control_tag_dispatch_left :
  forall b, dispatch_left_symbol (q0_stable_control_tag b).
Proof.
  intros []; unfold dispatch_left_symbol, q0_stable_control_tag; auto 12.
Qed.

Lemma q0_stable_control_tag_dispatch_right :
  forall b, dispatch_right_symbol (q0_stable_control_tag b).
Proof.
  intros []; unfold dispatch_right_symbol, q0_stable_control_tag; auto 12.
Qed.

Lemma q0_stable_control_tags_dispatch_left :
  forall bits,
    Forall dispatch_left_symbol (map q0_stable_control_tag bits).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - constructor.
    + apply q0_stable_control_tag_dispatch_left.
    + exact IH.
Qed.

Lemma q0_stable_control_rail_dispatch_left :
  forall bits,
    Forall dispatch_left_symbol
      (rev (map q0_stable_control_tag bits) ++ [0; 6]).
Proof.
  intros bits.
  rewrite Forall_app. split.
  - apply Forall_rev. apply q0_stable_control_tags_dispatch_left.
  - constructor.
    + unfold dispatch_left_symbol; auto 12.
    + constructor.
      * unfold dispatch_left_symbol; auto 12.
      * constructor.
Qed.

Lemma q0_stable_control_tags_pass :
  forall bits, Forall q0_pass (map q0_stable_control_tag bits).
Proof.
  induction bits as [|b rest IH].
  - constructor.
  - constructor.
    + apply q0_stable_control_tag_pass.
    + exact IH.
Qed.

(** target=true: q15 -> ... -> q3 -> q5. *)
Theorem q15_left_loop_target1_to_q5 :
  forall (old next extra : bool) (outer symbols suffix : list nat),
    Forall dispatch_right_symbol symbols ->
    run (21 + (length symbols + 1))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (q0_stable_control_tag next ::
         q0_stable_control_tag extra :: source_bit true ::
         symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++
       3 :: rev [q0_stable_control_tag next;
                 q0_stable_control_tag extra] ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
      (4 :: suffix).
Proof.
  intros old next extra outer symbols suffix Hsymbols.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_target_dispatch
    old next extra true outer (symbols ++ 4 :: suffix)).
  apply (q3_scan_to_q5
    (3 :: rev [q0_stable_control_tag next;
               q0_stable_control_tag extra] ++
     0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
    symbols suffix Hsymbols).
Qed.

(** target=false: q15 -> ... -> q2 -> q1. *)
Theorem q15_left_loop_target0_to_q1 :
  forall (old next extra : bool) (outer suffix : list nat),
    run (21 + S (length (rev [q0_stable_control_tag next;
                              q0_stable_control_tag extra] ++ [0; 6])))
      (entry_config 15
        (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
        (q0_stable_control_tag next ::
         q0_stable_control_tag extra :: source_bit false :: suffix)) =
    entry_config 1 (5 :: source_bit old :: 6 :: outer)
      (rev (rev [q0_stable_control_tag next;
                 q0_stable_control_tag extra] ++ [0; 6]) ++
       2 :: suffix).
Proof.
  intros old next extra outer suffix.
  rewrite dispatch_run_add.
  rewrite (q15_left_false_guard_native_tagged_target_dispatch
    old next extra false outer suffix).
  replace (rev [q0_stable_control_tag next;
                q0_stable_control_tag extra] ++
           0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
    with ((rev [q0_stable_control_tag next;
                q0_stable_control_tag extra] ++ [0]) ++
          6 :: 5 :: source_bit old :: 6 :: outer)
    by (rewrite <- app_assoc; reflexivity).
  apply (q2_rail_reenter_q1
    (rev [q0_stable_control_tag next;
          q0_stable_control_tag extra] ++ [0])
    6 (source_bit old :: 6 :: outer) (2 :: suffix)).
  change (Forall dispatch_left_symbol
    (rev (map q0_stable_control_tag [next; extra]) ++ [0; 6])).
  apply q0_stable_control_rail_dispatch_left.
Qed.

Print Assumptions q15_left_loop_target1_to_q5.
Print Assumptions q15_left_loop_target0_to_q1.

(** ** Leftward 4-prefix bridge

    The canonical q14 output carries a leading X=4.  The right branch
    absorbs it in the q16 backscan.  The same absorption is possible on
    the left branch: q15 scans the tagged rail, q16 crosses the 4 while
    returning, and q20/q17/q18 relocate the controlled sacrificial bit.
    The resulting q5 tail begins with the restored 4, exactly the
    q0-passable prefix needed by the generalized left gate below. *)



Lemma q0_stable_control_scan_q15 :
  forall bits, Forall q15_pass (rev (map q0_stable_control_tag bits)).
Proof. apply q15_stable_control_rail_reverse_safe. Qed.

Lemma q0_stable_control_scan_q16 :
  forall bits, Forall q16_pass (map q0_stable_control_tag bits).
Proof. apply q16_stable_control_rail_safe. Qed.

Theorem q15_q22_left_four_prefix_to_q20 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old next target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    run (S (length (rev (map q0_stable_control_tag (first :: rest)))) +
         S (length (map q0_stable_control_tag (first :: rest) ++ [4])) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore
              (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros first rest dir_head dir_remaining old next target outer suffix H21.
  assert (H16 : Forall q16_pass
      (map q0_stable_control_tag (first :: rest) ++ [4])).
  {
    rewrite Forall_app. split.
    - apply q0_stable_control_scan_q16.
    - constructor.
      + unfold q16_pass; auto 12.
      + constructor.
  }
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip_local old next
    (map q0_stable_control_tag (first :: rest))
    (dir_head :: dir_remaining ++ 2 :: source_bit target :: outer)
    suffix (q0_stable_control_scan_q15 (first :: rest)) H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 2 :: source_bit target :: outer)
      (dir_head :: 7 :: map q16_restore
        (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore
              (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix)).
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22).
  { destruct old; simpl; auto. }
  rewrite (q21_scan_to_left_direction dir_remaining dir_head
    (if old then 22 else 21) (source_bit target :: outer)
    (7 :: map q16_restore
       (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
     source_bit next :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Print Assumptions q15_q22_left_four_prefix_to_q20.

Theorem q15_q22_left_four_prefix_relocates_to_q5 :
  forall (first : bool) (rest : list bool)
         dir_head dir_remaining old next target outer suffix,
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass (rev (dir_head :: dir_remaining)) ->
    run ((S (length (rev (map q0_stable_control_tag (first :: rest)))) +
          S (length (map q0_stable_control_tag (first :: rest) ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (1 + S (length
           (source_bit old :: rev (dir_head :: dir_remaining)))))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev (map q0_stable_control_tag (first :: rest)) ++
         source_bit next :: suffix)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore
         (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros first rest dir_head dir_remaining old next target outer suffix
    H21 Hreturn.
  assert (Hreturn' :
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining))).
  {
    constructor.
    - destruct old; unfold q17_pass, source_bit; simpl;
        [right; left; reflexivity | left; reflexivity].
    - exact Hreturn.
  }
  rewrite writeback_run_add.
  rewrite (q15_q22_left_four_prefix_to_q20
    first rest dir_head dir_remaining old next target outer suffix H21).
  match goal with
  | |- _ = ?expected =>
    change (run (S (length
      (source_bit old :: rev (dir_head :: dir_remaining))))
    (step (entry_config 20 outer
      (source_bit target :: source_bit old ::
       rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore
              (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix))) = expected)
  end.
  rewrite (q20_raw_to_m target outer
    (source_bit old :: rev (dir_head :: dir_remaining) ++
     7 :: map q16_restore
            (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
     source_bit next :: suffix)).
  destruct target.
  - exact (q18_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore
         (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix) Hreturn').
  - exact (q17_scan_to_marker
      (source_bit old :: rev (dir_head :: dir_remaining))
      (6 :: outer)
      (map q16_restore
         (rev (map q0_stable_control_tag (first :: rest) ++ [4])) ++
       source_bit next :: suffix) Hreturn').
Qed.

Print Assumptions q15_q22_left_four_prefix_relocates_to_q5.

(** ** Generalized left gate with a passable prefix

    The restored 4 is q0-passable, so the left q5/q1/q0 gate can carry it
    as a prefix before the two stable control tags.  This is the exact
    extra degree of freedom needed after the four-prefix relocation. *)

Lemma q5_left_four_steps :
  forall (old : bool) (prefix outer tail : list nat),
    run 4
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: prefix ++ tail)) =
    entry_config 0 (0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
      (prefix ++ tail).
Proof.
  intros old prefix outer tail. reflexivity.
Qed.

Theorem q5_left_false_gate_tagged_target_prefix :
  forall (old next extra target : bool) (prefix outer tail : list nat),
    Forall q0_pass prefix ->
    run (length prefix + 7)
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: prefix ++
         q0_stable_control_tag next ::
         q0_stable_control_tag extra :: source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (prefix ++
        [q0_stable_control_tag next; q0_stable_control_tag extra]) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail
    else cfg_ml 2
      (rev (prefix ++
        [q0_stable_control_tag next; q0_stable_control_tag extra]) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: tail).
Proof.
  intros old next extra target prefix outer tail Hprefix.
  replace (length prefix + 7) with (4 + (length prefix + 3)) by lia.
  rewrite dispatch_run_add.
  rewrite (q5_left_four_steps old prefix outer
    (q0_stable_control_tag next ::
     q0_stable_control_tag extra :: source_bit target :: tail)).
  apply (q0_tagged_control_pair_dispatches_target
    prefix (0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
    tail next extra target Hprefix).
Qed.

Print Assumptions q5_left_false_gate_tagged_target_prefix.

(** ** Left four-prefix gate

    Composing the four-prefix relocation with the generalized left gate
    yields the exact q3/q2 entry of the next phase, with the restored 4
    carried as a q0-passable prefix.  This is the left-branch analogue of
    the right four-prefix q1/q0/q4 dispatch. *)

Lemma four_prefix_q0_shape :
  forall (prefix spacer tail : list nat) (next extra target : bool),
    prefix ++ q0_stable_control_tag next ::
    q0_stable_control_tag extra :: spacer ++ source_bit target :: tail =
    (prefix ++
     [q0_stable_control_tag next; q0_stable_control_tag extra] ++
     spacer) ++ source_bit target :: tail.
Proof.
  intros. repeat rewrite <- app_assoc. reflexivity.
Qed.

Theorem q5_left_false_gate_tagged_target_spacer :
  forall (old next extra target : bool)
         (prefix spacer outer tail : list nat),
    Forall q0_pass prefix ->
    Forall q0_pass spacer ->
    run (length prefix + length spacer + 7)
      (entry_config 5 (5 :: source_bit old :: 6 :: outer)
        (6 :: 2 :: prefix ++
         q0_stable_control_tag next ::
         q0_stable_control_tag extra ::
         spacer ++ source_bit target :: tail)) =
    if target
    then entry_config 3
      (3 :: rev (prefix ++
        [q0_stable_control_tag next; q0_stable_control_tag extra] ++
        spacer) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail
    else cfg_ml 2
      (rev (prefix ++
        [q0_stable_control_tag next; q0_stable_control_tag extra] ++
        spacer) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: tail).
Proof.
  intros old next extra target prefix spacer outer tail Hprefix Hspacer.
  assert (Hmarked : Forall q0_pass
      (prefix ++
       [q0_stable_control_tag next; q0_stable_control_tag extra] ++
       spacer)).
  {
    repeat rewrite Forall_app. repeat split.
    - exact Hprefix.
    - apply q0_two_stable_control_tags_pass.
    - exact Hspacer.
  }
  replace (length prefix + length spacer + 7)
    with (4 + S (length
      (prefix ++
       [q0_stable_control_tag next; q0_stable_control_tag extra] ++
       spacer))) by (rewrite app_length; rewrite app_length; cbn [length]; lia).
  rewrite dispatch_run_add.
  rewrite (q5_left_four_steps old prefix outer
    (q0_stable_control_tag next ::
     q0_stable_control_tag extra ::
     spacer ++ source_bit target :: tail)).
  destruct target.
  - rewrite (four_prefix_q0_shape prefix spacer tail next extra true).
    apply (q0_scan_one
      (prefix ++
       [q0_stable_control_tag next; q0_stable_control_tag extra] ++
       spacer)
      (0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail Hmarked).
  - rewrite (four_prefix_q0_shape prefix spacer tail next extra false).
    apply (q0_scan_zero
      (prefix ++
       [q0_stable_control_tag next; q0_stable_control_tag extra] ++
       spacer)
      (0 :: 6 :: 5 :: source_bit old :: 6 :: outer) tail Hmarked).
Qed.

Lemma four_prefix_restored_map :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control : bool),
    map q16_restore
      (rev (map q0_stable_control_tag
        (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) =
    [4] ++ q0_stable_control_tag next_control ::
    q0_stable_control_tag extra ::
    rev (map q0_stable_control_tag (first :: rest_prefix)).
Proof.
  intros first rest_prefix extra next_control.
  rewrite rev_app_distr. cbn [rev].
  rewrite map_app.
  rewrite q16_stable_control_rail_reverse_restore.
  replace (map q16_restore [4]) with ([4] : list nat) by reflexivity.
  replace (map q0_stable_control_tag
      (first :: (rest_prefix ++ [extra; next_control])))
    with (map q0_stable_control_tag (first :: rest_prefix) ++
          [q0_stable_control_tag extra; q0_stable_control_tag next_control]).
  2:{
    replace (first :: (rest_prefix ++ [extra; next_control]))
      with ((first :: rest_prefix) ++ [extra; next_control])
      by reflexivity.
    rewrite map_app. reflexivity.
  }
  rewrite rev_app_distr. cbn [rev].
  reflexivity.
Qed.

Lemma four_prefix_q5_frame :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control old read : bool)
         (outer suffix : list nat),
    cfg_ml 5
      (rev (source_bit old :: rev (6 :: [5])) ++ 6 :: outer)
      (2 :: map q16_restore
             (rev (map q0_stable_control_tag
               (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) ++
       source_bit read :: suffix) =
    entry_config 5 (5 :: source_bit old :: 6 :: outer)
      (6 :: 2 :: [4] ++
       [q0_stable_control_tag next_control;
        q0_stable_control_tag extra] ++
       rev (map q0_stable_control_tag (first :: rest_prefix)) ++
       source_bit read :: suffix).
Proof.
  intros. rewrite four_prefix_restored_map. reflexivity.
Qed.

Theorem q15_left_four_prefix_gate :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control old read : bool) (outer suffix : list nat),
    run (((S (length (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))))) +
          S (length (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) +
          S (length (6 :: [5]))) +
         (1 + S (length (source_bit old :: rev (6 :: [5]))))) +
        (length [4] + length (rev (map q0_stable_control_tag (first :: rest_prefix))) + 7))
      (entry_config 15
        (4 :: source_bit old :: 6 :: [5] ++ 2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))) ++
         source_bit read :: suffix)) =
    if read
    then entry_config 3
      (3 :: rev ([4] ++
        [q0_stable_control_tag next_control;
         q0_stable_control_tag extra] ++
        rev (map q0_stable_control_tag (first :: rest_prefix))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) suffix
    else cfg_ml 2
      (rev ([4] ++
        [q0_stable_control_tag next_control;
         q0_stable_control_tag extra] ++
        rev (map q0_stable_control_tag (first :: rest_prefix))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer) (2 :: suffix).
Proof.
  intros first rest_prefix extra next_control old read outer suffix.
  assert (H21 : Forall q21_pass (6 :: [5])).
  {
    constructor.
    - unfold q21_pass; auto 12.
    - constructor.
      + unfold q21_pass; auto 12.
      + constructor.
  }
  assert (H17 : Forall q17_pass (rev (6 :: [5]))).
  {
    cbn [rev]. constructor.
    - unfold q17_pass; auto 12.
    - constructor.
      + unfold q17_pass; auto 12.
      + constructor.
  }
  rewrite (dispatch_run_add
    (((S (length (rev (map q0_stable_control_tag
            (first :: (rest_prefix ++ [extra; next_control]))))) +
        S (length (map q0_stable_control_tag
            (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) +
        S (length (6 :: [5]))) +
       (1 + S (length (source_bit old :: rev (6 :: [5]))))))
    (length [4] + length (rev (map q0_stable_control_tag (first :: rest_prefix))) + 7)
    (entry_config 15
      (4 :: source_bit old :: 6 :: [5] ++ 2 :: source_bit false :: outer)
      (rev (map q0_stable_control_tag
            (first :: (rest_prefix ++ [extra; next_control]))) ++
       source_bit read :: suffix))).
  rewrite (q15_q22_left_four_prefix_relocates_to_q5
    first (rest_prefix ++ [extra; next_control]) 6 [5]
    old read false outer suffix H21 H17).
  rewrite four_prefix_q5_frame.
  assert (Hpre : Forall q0_pass [4]).
  { constructor.
    - unfold q0_pass; auto 12.
    - constructor. }
  assert (Hsp : Forall q0_pass
      (rev (map q0_stable_control_tag (first :: rest_prefix)))).
  { apply Forall_rev. apply q0_stable_control_tags_pass. }
  apply (q5_left_false_gate_tagged_target_spacer
    old next_control extra read [4]
    (rev (map q0_stable_control_tag (first :: rest_prefix)))
    outer suffix Hpre Hsp).
Qed.

Print Assumptions q15_left_four_prefix_gate.

(** ** Complete left four-prefix loops

    The four-prefix gate ends at q3/q2.  Composing with the native
    q3->q5 and q2->q1 reentries closes the left movement loop while the
    restored 4 travels in the q5/q1 rail. *)

Lemma four_prefix_left_rail_tail :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control : bool),
    Forall dispatch_left_symbol
      (map q0_stable_control_tag (first :: rest_prefix) ++
       [q0_stable_control_tag extra;
        q0_stable_control_tag next_control; 4; 0; 6]).
Proof.
  intros first rest_prefix extra next_control.
  rewrite Forall_app. split.
  - apply q0_stable_control_tags_dispatch_left.
  - constructor.
    + apply q0_stable_control_tag_dispatch_left.
    + constructor.
      * apply q0_stable_control_tag_dispatch_left.
      * constructor.
        -- unfold dispatch_left_symbol; auto 12.
        -- constructor.
           ++ unfold dispatch_left_symbol; auto 12.
           ++ constructor.
              ** unfold dispatch_left_symbol; auto 12.
              ** constructor.
Qed.

Lemma four_prefix_left_rail_safe :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control : bool),
    Forall dispatch_left_symbol
      (rev ([4] ++
        [q0_stable_control_tag next_control;
         q0_stable_control_tag extra] ++
        rev (map q0_stable_control_tag (first :: rest_prefix))) ++ [0; 6]).
Proof.
  intros first rest_prefix extra next_control.
  replace (rev ([4] ++
      [q0_stable_control_tag next_control;
       q0_stable_control_tag extra] ++
      rev (map q0_stable_control_tag (first :: rest_prefix))) ++ [0; 6])
    with (map q0_stable_control_tag (first :: rest_prefix) ++
      [q0_stable_control_tag extra;
       q0_stable_control_tag next_control; 4; 0; 6]).
  2:{
    repeat rewrite rev_app_distr.
    cbn [rev].
    rewrite rev_involutive.
    repeat rewrite app_nil_r.
    repeat rewrite app_nil_l.
    repeat rewrite <- app_assoc.
    reflexivity.
  }
  apply four_prefix_left_rail_tail.
Qed.

Theorem q15_left_four_prefix_loop_read1_to_q5 :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control old : bool)
         (outer symbols suffix : list nat),
    Forall dispatch_right_symbol symbols ->
    run ((((S (length (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))))) +
           S (length (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) +
           S (length (6 :: [5]))) +
          (1 + S (length (source_bit old :: rev (6 :: [5]))))) +
         (length [4] +
          length (rev (map q0_stable_control_tag (first :: rest_prefix))) +
          7)) +
        (length symbols + 1))
      (entry_config 15
        (4 :: source_bit old :: 6 :: [5] ++
         2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))) ++
         source_bit true :: symbols ++ 4 :: suffix)) =
    cfg_ml 5
      (rev symbols ++
       3 :: rev ([4] ++
         [q0_stable_control_tag next_control;
          q0_stable_control_tag extra] ++
         rev (map q0_stable_control_tag (first :: rest_prefix))) ++
       0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
      (4 :: suffix).
Proof.
  intros first rest_prefix extra next_control old outer symbols suffix
    Hsymbols.
  rewrite dispatch_run_add.
  rewrite (q15_left_four_prefix_gate
    first rest_prefix extra next_control old true outer
    (symbols ++ 4 :: suffix)).
  apply (q3_scan_to_q5
    (3 :: rev ([4] ++
      [q0_stable_control_tag next_control;
       q0_stable_control_tag extra] ++
      rev (map q0_stable_control_tag (first :: rest_prefix))) ++
     0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
    symbols suffix Hsymbols).
Qed.

Theorem q15_left_four_prefix_loop_read0_to_q1 :
  forall (first : bool) (rest_prefix : list bool)
         (extra next_control old : bool)
         (outer suffix : list nat),
    run ((((S (length (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))))) +
           S (length (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control])) ++ [4])) +
           S (length (6 :: [5]))) +
          (1 + S (length (source_bit old :: rev (6 :: [5]))))) +
         (length [4] +
          length (rev (map q0_stable_control_tag (first :: rest_prefix))) +
          7)) +
        S (length
          ((rev ([4] ++
            [q0_stable_control_tag next_control;
             q0_stable_control_tag extra] ++
            rev (map q0_stable_control_tag (first :: rest_prefix))) ++
           [0]) ++ [6])))
      (entry_config 15
        (4 :: source_bit old :: 6 :: [5] ++
         2 :: source_bit false :: outer)
        (rev (map q0_stable_control_tag
              (first :: (rest_prefix ++ [extra; next_control]))) ++
         source_bit false :: suffix)) =
    entry_config 1 (5 :: source_bit old :: 6 :: outer)
      (rev ((rev ([4] ++
        [q0_stable_control_tag next_control;
         q0_stable_control_tag extra] ++
        rev (map q0_stable_control_tag (first :: rest_prefix))) ++
        [0]) ++ [6]) ++ 2 :: suffix).
Proof.
  intros first rest_prefix extra next_control old outer suffix.
  rewrite dispatch_run_add.
  rewrite (q15_left_four_prefix_gate
    first rest_prefix extra next_control old false outer suffix).
  replace (rev ([4] ++
      [q0_stable_control_tag next_control;
       q0_stable_control_tag extra] ++
      rev (map q0_stable_control_tag (first :: rest_prefix))) ++
      0 :: 6 :: 5 :: source_bit old :: 6 :: outer)
    with ((rev ([4] ++
      [q0_stable_control_tag next_control;
       q0_stable_control_tag extra] ++
      rev (map q0_stable_control_tag (first :: rest_prefix))) ++ [0]) ++
      6 :: 5 :: source_bit old :: 6 :: outer)
    by (rewrite <- app_assoc; reflexivity).
  apply (q2_rail_reenter_q1
    (rev ([4] ++
      [q0_stable_control_tag next_control;
       q0_stable_control_tag extra] ++
      rev (map q0_stable_control_tag (first :: rest_prefix))) ++ [0])
    6 (source_bit old :: 6 :: outer) (2 :: suffix)).
  apply four_prefix_left_rail_safe.
Qed.

Print Assumptions q15_left_four_prefix_loop_read1_to_q5.
Print Assumptions q15_left_four_prefix_loop_read0_to_q1.
