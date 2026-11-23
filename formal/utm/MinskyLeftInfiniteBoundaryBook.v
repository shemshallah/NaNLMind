(** * Book-level empty-buffer boundary composition *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyMatchMacro MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyConcreteDispatch
  MinskyCanonicalMatch MinskyActionMacro MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyRelocationMacro MinskyBookLayout
  MinskyBookCycle MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteEncoding MinskyLeftInfiniteBoundary
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteLift.

Local Open Scope nat_scope.

Definition book_q12_empty_boundary_clock
    (init : list bool) (w_read w_tape : bool) (steps : list book_failure)
    (hit : book_row) (hit_init : list bool) (hit_w : bool)
    (steps_fail : list book_failure) (last_fail : book_failure) : nat :=
  (S (length (match_mark hit_w ::
              rev (map match_mark hit_init) ++ [5])) +
   S (length ([5] ++ rev (rev (map match_mark hit_init)) ++
              [match_mark hit_w]))) +
  ((S (length (rev (book_cycle_tags steps (init ++ [w_read]) hit))) +
    S (length (book_cycle_tags steps (init ++ [w_read]) hit ++ [4])) +
    S (length (book_return_rail_raw hit_init []))) +
   (2 + S (length (map source_bit (tl hit_init))))) +
  (S (length (map source_bit (tl hit_init)) + 1) +
   (book_failures_clock_pass [6] [] steps_fail +
    book_halt_clock_pass [6] (map bf_row steps_fail) last_fail)).

Theorem book_q5_raw_empty_boundary_halt :
  forall (init : list bool) (w_read w_tape : bool)
         (ptape tail : list nat) (steps : list book_failure)
         (hit next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w c0 : bool) (creast : list bool)
         (steps_fail : list book_failure) (last_fail : book_failure),
    hit_init <> [] ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    book_first_match (tl hit_init ++ [hd false hit_init])
      (map bf_row steps ++ hit :: next :: rest) =
      book_lookup_halt steps_fail last_fail ->
    Forall q12_pass
      (match_mark hit_w :: rev (map match_mark hit_init) ++ [5]) ->
    Forall q14_pass
      ([5] ++ map match_mark hit_init ++ [match_mark hit_w]) ->
    map q14_restore
      (rev ([5] ++ map match_mark hit_init ++ [match_mark hit_w])) =
      source_bit hit_w ::
      hd 0 (book_return_rail_raw hit_init []) ::
      tl (book_return_rail_raw hit_init []) ->
    Forall q21_pass (book_return_rail_raw hit_init []) ->
    rev (book_return_rail_raw hit_init []) =
      5 :: source_bit (hd false hit_init) :: map source_bit (tl hit_init) ->
    Forall q17_pass (map source_bit (tl hit_init)) ->
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark hit_init ++ [match_mark hit_w]) ++
    book_cycle_dir_mark hit ::
      (book_raw_tail (next :: rest) ++ 5 :: tail) =
    rev (book_cycle_tags steps (init ++ [w_read]) hit) ++
    source_bit c0 ::
      (book_after_suffix creast next rest ++ 5 :: tail) ->
    Forall q15_pass
      (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ->
    Forall q16_pass
      (book_cycle_tags steps (init ++ [w_read]) hit ++ [4]) ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q12_empty_boundary_clock init w_read w_tape steps hit
           hit_init hit_w steps_fail last_fail)
      (book_q5_raw init [] w_tape ptape w_read
        (map bf_row steps ++ hit :: next :: rest) tail)
    = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
        (source_bit hit_w :: rev (ptape ++ [source_bit w_tape])) tail.
Proof.
  intros init w_read w_tape ptape tail steps hit next rest hit_init
    hit_w c0 creast steps_fail last_fail Hne Hsteps Hcond Hlen Hact
    Hdir Hnext Hbf H12 H14 Hrestored H21 Hsplit H17 Hright H15 H16.
  destruct (book_first_match_halt_sound
    (tl hit_init ++ [hd false hit_init])
    (map bf_row steps ++ hit :: next :: rest)
    steps_fail last_fail Hbf) as [Hrows_fail Hforall_fail].
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
    (book_q12_empty_boundary_clock init w_read w_tape steps hit
       hit_init hit_w steps_fail last_fail)).
  rewrite (book_steady_q5_locate_to_q12_raw_gen init w_read w_tape []
    ptape tail steps hit (next :: rest) Hsteps Hcond Hlen).
  rewrite Hdir, Hact.
  rewrite map_app, rev_app_distr. cbn [map rev app].
  assert (Hne_rail : book_return_rail_raw hit_init [] <> []).
  { unfold book_return_rail_raw. cbn [rev app].
    apply snoc_neq_nil. }
  assert (Hrail :
    hd 0 (book_return_rail_raw hit_init []) ::
    tl (book_return_rail_raw hit_init []) =
    book_return_rail_raw hit_init []).
  { destruct (book_return_rail_raw hit_init []) as [|d ds] eqn:E.
    - exfalso. apply Hne_rail. reflexivity.
    - reflexivity. }
  assert (H21' : Forall q21_pass
    (hd 0 (book_return_rail_raw hit_init []) ::
     tl (book_return_rail_raw hit_init []))).
  { rewrite Hrail. exact H21. }
  assert (Hsplit' : rev
    (hd 0 (book_return_rail_raw hit_init []) ::
     tl (book_return_rail_raw hit_init [])) =
    5 :: source_bit (hd false hit_init) :: map source_bit (tl hit_init)).
  { rewrite Hrail. exact Hsplit. }
  unfold book_q12_empty_boundary_clock.
  rewrite <- Hrail.
  fold (book_q12_empty_boundary_clock init w_read w_tape steps hit
    hit_init hit_w steps_fail last_fail).
  rewrite (book_q12_empty_boundary_halt
    (match_mark hit_w) (rev (map match_mark hit_init))
    (ptape ++ [source_bit w_tape])
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark hit_init ++ [match_mark hit_w])
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    (book_cycle_tags steps (init ++ [w_read]) hit)
    hit_w
    (hd 0 (book_return_rail_raw hit_init []))
    (tl (book_return_rail_raw hit_init []))
    (hd false hit_init) c0 (map source_bit (tl hit_init))
    (book_after_suffix creast next rest ++ 5 :: tail)
    (tl hit_init) (hd false hit_init) hit_w steps_fail last_fail
    (map bf_row steps ++ hit :: next :: rest) tail
    H12
    ltac:(rewrite rev_involutive; exact H14)
    ltac:(rewrite rev_involutive; exact Hrestored)
    H21' Hsplit' H17 Hright H15 H16
    eq_refl eq_refl eq_refl Hforall_fail Hrows_fail
    ltac:(rewrite (book_cycle_restored_raw_desc_tail steps
      (init ++ [w_read]) hit next rest c0 creast (5 :: tail)
      Hcond Hnext);
      destruct (map bf_row steps) as [|r rs] eqn:E;
      [cbn [app]; reflexivity |
       cbn [app]; rewrite book_raw_tail_cons; reflexivity])).
  reflexivity.
Qed.

Print Assumptions book_q5_raw_empty_boundary_halt.

(** ** Source-level corollary *)

Definition lic_q5_empty_boundary_clock
    (lo : Z) (c : LeftInfiniteConfig)
    (steps : list book_failure) (hit : book_row)
    (hit_init : list bool) (hit_w : bool)
    (steps_fail : list book_failure) (last_fail : book_failure) : nat :=
  book_steady_locate_q12_clock_gen (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo) steps hit +
  book_q12_empty_boundary_clock (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo) steps hit hit_init hit_w
    steps_fail last_fail.

Theorem lic_q5_encode_lifted_boundary_step :
  forall (lo : Z) (c : LeftInfiniteConfig) (steps : list book_failure)
         (hit next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w c0 : bool) (creast : list bool)
         (steps_fail : list book_failure) (last_fail : book_failure)
         (tail : list nat),
    raw_buf c = [] ->
    raw_ptape_prefix c lo ++ [source_bit (raw_last c lo)] =
      raw_ptape c lo ->
    hit_init <> [] ->
    Forall (fun st =>
      bf_src st = lic_state c ++ [lic_tape c (lic_head c)]) steps ->
    br_cond hit = lic_state c ++ [lic_tape c (lic_head c)] ->
    length (br_action hit) =
      length (lic_state c ++ [lic_tape c (lic_head c)]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    book_first_match (tl hit_init ++ [hd false hit_init])
      (map bf_row steps ++ hit :: next :: rest) =
      book_lookup_halt steps_fail last_fail ->
    Forall q12_pass
      (match_mark hit_w :: rev (map match_mark hit_init) ++ [5]) ->
    Forall q14_pass
      ([5] ++ map match_mark hit_init ++ [match_mark hit_w]) ->
    map q14_restore
      (rev ([5] ++ map match_mark hit_init ++ [match_mark hit_w])) =
      source_bit hit_w ::
      hd 0 (book_return_rail_raw hit_init []) ::
      tl (book_return_rail_raw hit_init []) ->
    Forall q21_pass (book_return_rail_raw hit_init []) ->
    rev (book_return_rail_raw hit_init []) =
      5 :: source_bit (hd false hit_init) :: map source_bit (tl hit_init) ->
    Forall q17_pass (map source_bit (tl hit_init)) ->
    ((book_cycle_region steps ++
      map match_mark (lic_state c ++ [lic_tape c (lic_head c)])) ++
     map match_mark hit_init ++ [match_mark hit_w]) ++
    book_cycle_dir_mark hit ::
      (book_raw_tail (next :: rest) ++ 5 :: tail) =
    rev (book_cycle_tags steps
           (lic_state c ++ [lic_tape c (lic_head c)]) hit) ++
    source_bit c0 ::
      (book_after_suffix creast next rest ++ 5 :: tail) ->
    Forall q15_pass
      (rev (book_cycle_tags steps
             (lic_state c ++ [lic_tape c (lic_head c)]) hit)) ->
    Forall q16_pass
      (book_cycle_tags steps
        (lic_state c ++ [lic_tape c (lic_head c)]) hit ++ [4]) ->
    run (lic_q5_empty_boundary_clock lo c steps hit hit_init hit_w
           steps_fail last_fail)
      (lic_q5_encode lo c
        (map bf_row steps ++ hit :: next :: rest) tail)
    = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
        (source_bit hit_w :: rev (raw_ptape c lo)) tail.
Proof.
  intros lo c steps hit next rest hit_init hit_w c0 creast
    steps_fail last_fail tail Hrawbuf Hptape Hne Hsteps Hcond Hlen
    Hact Hdir Hnext Hbf H12 H14 Hrestored H21 Hsplit H17 Hright
    H15 H16.
  unfold lic_q5_encode, book_q5_raw.
  rewrite Hrawbuf.
  change (run (lic_q5_empty_boundary_clock lo c steps hit hit_init
                 hit_w steps_fail last_fail)
    (book_q5_raw (lic_state c) [] (raw_last c lo)
      (raw_ptape_prefix c lo) (lic_tape c (lic_head c))
      (map bf_row steps ++ hit :: next :: rest) tail) =
    boundary_halt_encode_from_failed [6] [] steps_fail last_fail
      (source_bit hit_w :: rev (raw_ptape c lo)) tail).
  rewrite <- Hptape.
  exact (book_q5_raw_empty_boundary_halt (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo)
    (raw_ptape_prefix c lo) tail steps hit next rest hit_init hit_w
    c0 creast steps_fail last_fail Hne Hsteps Hcond Hlen Hact Hdir
    Hnext Hbf H12 H14 Hrestored H21 Hsplit H17 Hright H15 H16).
Qed.

Print Assumptions lic_q5_encode_lifted_boundary_step.
