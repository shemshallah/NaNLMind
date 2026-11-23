(** * Final empty-buffer boundary corollaries

    The q12 passability/restored premise block is packaged in
    [MinskyLeftInfiniteBoundaryPremises.book_q12_empty_boundary_premises].
    The only remaining input is the rotated first-match halt [Hbf]. *)

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
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteBoundaryBook
  MinskyLeftInfiniteBoundaryPremises.

Local Open Scope nat_scope.

Corollary book_q5_raw_empty_boundary_halt_premises :
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
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q12_empty_boundary_clock init w_read w_tape steps hit
           hit_init hit_w steps_fail last_fail)
      (book_q5_raw init [] w_tape ptape w_read
        (map bf_row steps ++ hit :: next :: rest) tail)
    = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
        (source_bit hit_w :: rev (ptape ++ [source_bit w_tape])) tail.
Proof.
  intros init w_read w_tape ptape tail steps hit next rest hit_init
    hit_w c0 creast steps_fail last_fail Hne Hsteps Hcond Hlen
    Hact Hdir Hnext Hbf.
  destruct (book_q12_empty_boundary_premises init w_read w_tape steps
    hit next rest hit_init hit_w c0 creast tail Hne Hsteps Hcond
    Hact Hnext) as [H12 [H14 [Hrestored [H21 [Hsplit [H17
    [Hright [H15 H16]]]]]]]].
  exact (book_q5_raw_empty_boundary_halt init w_read w_tape ptape tail
    steps hit next rest hit_init hit_w c0 creast steps_fail last_fail
    Hne Hsteps Hcond Hlen Hact Hdir Hnext Hbf H12 H14 Hrestored H21
    Hsplit H17 Hright H15 H16).
Qed.

Corollary lic_q5_encode_lifted_boundary_step_premises :
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
    run (lic_q5_empty_boundary_clock lo c steps hit hit_init hit_w
           steps_fail last_fail)
      (lic_q5_encode lo c
        (map bf_row steps ++ hit :: next :: rest) tail)
    = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
        (source_bit hit_w :: rev (raw_ptape c lo)) tail.
Proof.
  intros lo c steps hit next rest hit_init hit_w c0 creast
    steps_fail last_fail tail Hrawbuf Hptape Hne Hsteps Hcond Hlen
    Hact Hdir Hnext Hbf.
  destruct (book_q12_empty_boundary_premises (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo) steps hit next rest
    hit_init hit_w c0 creast tail Hne Hsteps Hcond Hact Hnext)
    as [H12 [H14 [Hrestored [H21 [Hsplit [H17 [Hright [H15 H16]]]]]]]].
  exact (lic_q5_encode_lifted_boundary_step lo c steps hit next rest
    hit_init hit_w c0 creast steps_fail last_fail tail Hrawbuf Hptape
    Hne Hsteps Hcond Hlen Hact Hdir Hnext Hbf H12 H14 Hrestored H21
    Hsplit H17 Hright H15 H16).
Qed.

Print Assumptions book_q5_raw_empty_boundary_halt_premises.
Print Assumptions lic_q5_encode_lifted_boundary_step_premises.
