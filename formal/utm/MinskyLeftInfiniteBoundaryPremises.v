(** * Empty-buffer q12 passability and restored-frame premises

    The nonempty right cycle proves a block of q12 hypotheses with the
    new read bit taken from the first buffer cell.  At the empty wall
    there is no buffer cell; the read bit and the remaining condition
    come from the rotated next state:

      bit = hd hit_init,
      between = map source_bit (tl hit_init).

    This file packages the exact block needed by
    [book_q5_raw_empty_boundary_halt]. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyActionMacro MinskyMatchMacro
  MinskyCanonicalInstruction MinskyDirectionDecision MinskyRelocationMacro
  MinskyHeadMoveMacro MinskyBookLayout MinskyBookCycle MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft MinskyLeftInfiniteEncoding
  MinskyLeftInfiniteBoundary MinskyLeftInfiniteBoundaryLocate
  MinskyLeftInfiniteBoundaryBook.

Local Open Scope nat_scope.

Lemma book_return_rail_raw_nil_eq :
  forall init,
    book_return_rail_raw init [] = rev (map source_bit init) ++ [5].
Proof. reflexivity. Qed.

Theorem book_q12_empty_boundary_premises :
  forall (init : list bool) (w_read w_tape : bool)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_init : list bool)
         (hit_w c0 : bool) (creast : list bool) (tail : list nat),
    hit_init <> [] ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    br_action hit = hit_init ++ [hit_w] ->
    br_cond next = c0 :: creast ->
    Forall q12_pass
      (match_mark hit_w :: rev (map match_mark hit_init) ++ [5]) /\
    Forall q14_pass
      ([5] ++ map match_mark hit_init ++ [match_mark hit_w]) /\
    map q14_restore
      (rev ([5] ++ map match_mark hit_init ++ [match_mark hit_w])) =
      source_bit hit_w ::
      hd 0 (book_return_rail_raw hit_init []) ::
      tl (book_return_rail_raw hit_init []) /\
    Forall q21_pass (book_return_rail_raw hit_init []) /\
    rev (book_return_rail_raw hit_init []) =
      5 :: source_bit (hd false hit_init) :: map source_bit (tl hit_init) /\
    Forall q17_pass (map source_bit (tl hit_init)) /\
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark hit_init ++ [match_mark hit_w]) ++
    book_cycle_dir_mark hit ::
      (book_raw_tail (next :: rest) ++ 5 :: tail) =
    rev (book_cycle_tags steps (init ++ [w_read]) hit) ++
    source_bit c0 ::
      (book_after_suffix creast next rest ++ 5 :: tail) /\
    Forall q15_pass
      (rev (book_cycle_tags steps (init ++ [w_read]) hit)) /\
    Forall q16_pass
      (book_cycle_tags steps (init ++ [w_read]) hit ++ [4]).
Proof.
  intros init w_read w_tape steps hit next rest hit_init hit_w c0 creast
    tail Hne Hsteps Hcond Hact Hnext.
  assert (Hraw : raw_source_buffer ([] : list nat)) by constructor.
  split.
  - (* H12 *)
    constructor.
    + apply q12_pass_match_mark.
    + apply Forall_app. split.
      * apply Forall_rev, Forall_q12_match_marks.
      * constructor.
        -- unfold q12_pass; auto 10.
        -- constructor.
  - split.
    + (* H14 *)
      apply Forall_app. split.
      * constructor; [unfold q14_pass; auto 10 | constructor].
      * apply Forall_app. split.
        -- apply Forall_q14_match_marks.
        -- constructor; [apply q14_pass_match_mark | constructor].
    + split.
      * (* Hrestored *)
        rewrite rev_app_distr. cbn [rev].
        rewrite rev_app_distr. cbn [rev].
        rewrite map_app. cbn [map].
        rewrite map_app. cbn [map].
        rewrite map_rev.
        rewrite map_q14_restore_match_marks.
        cbn [app map].
        rewrite q14_restore_match_mark.
        rewrite book_return_rail_raw_nil_eq.
        destruct (rev (map source_bit hit_init)) as [|x xs] eqn:E;
          cbn [hd tl app]; reflexivity.
      * split.
        -- (* H21 *)
           rewrite book_return_rail_raw_nil_eq.
           apply Forall_app. split.
           ++ apply Forall_rev, Forall_source_bits_q21.
           ++ constructor; [unfold q21_pass; auto 10 | constructor].
        -- split.
           ++ (* Hsplit *)
              rewrite book_return_rail_raw_nil_eq.
              rewrite rev_app_distr. cbn [rev].
              rewrite rev_involutive.
              destruct hit_init as [|h0 t0]; [contradiction|].
              cbn [map app]. reflexivity.
           ++ split.
              ** (* H17 *)
                 apply Forall_source_bits_q17.
              ** split.
                 *** (* Hright *)
                     rewrite book_cycle_tags_rev_eq.
                     unfold book_cycle_marked.
                     rewrite Hact.
                     replace (map match_mark (hit_init ++ [hit_w]))
                       with (map match_mark hit_init ++ [match_mark hit_w])
                       by (rewrite map_app; reflexivity).
                     rewrite book_raw_tail_cons.
                     rewrite (book_raw_desc_cons_cond next c0 creast rest
                       Hnext).
                     unfold book_cycle_dir_mark.
                     cbn [app].
                     repeat rewrite <- app_assoc.
                     cbn [app].
                     reflexivity.
                 *** split.
                     --- (* H15 *)
                         rewrite book_cycle_tags_rev_eq.
                         apply Forall_q15_cycle_rail.
                     --- (* H16 *)
                         apply Forall_q16_cycle_tags_snoc.
Qed.

Print Assumptions book_q12_empty_boundary_premises.
