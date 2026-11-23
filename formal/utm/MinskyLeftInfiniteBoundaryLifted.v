(** * Lifted boundary halt with the first-match witnesses computed

    The boundary theorem [lic_q5_encode_lifted_boundary_step_premises]
    takes the rotated lookup halt as a hypothesis.  For the marker-lifted
    rows that halt is automatic: the rotated source starts with [true],
    every lifted row condition starts with [false], and the first-bit
    mismatch is a valid [book_failure].  This file computes the failure
    witnesses and packages the run. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch
  MinskyBookLocateRows MinskyBookLocateLookup MinskyBookRawBuffer
  MinskyBookEncode
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteEncoding
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteBoundaryLookup
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteBoundaryBook
  MinskyLeftInfiniteBoundaryFinal MinskyLeftInfiniteLift.

Local Open Scope nat_scope.

Theorem lic_q5_encode_lifted_boundary_halt :
  forall (lo : Z) (c : LeftInfiniteConfig) (steps : list book_failure)
         (hit next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w c0 : bool) (creast : list bool)
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
    (exists s, tl hit_init ++ [hd false hit_init] = true :: s) ->
    (forall r, In r (map bf_row steps ++ hit :: next :: rest) ->
       exists s, br_cond r = false :: s) ->
    exists steps_fail last_fail,
      run (lic_q5_empty_boundary_clock lo c steps hit hit_init hit_w
             steps_fail last_fail)
        (lic_q5_encode lo c
          (map bf_row steps ++ hit :: next :: rest) tail)
      = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
          (source_bit hit_w :: rev (raw_ptape c lo)) tail /\
      c_halted
        (boundary_halt_encode_from_failed [6] [] steps_fail last_fail
          (source_bit hit_w :: rev (raw_ptape c lo)) tail) = true.
Proof.
  intros lo c steps hit next rest hit_init hit_w c0 creast tail
    Hrawbuf Hptape Hne Hsteps Hcond Hlen Hact Hdir Hnext Hrot Hrows.
  destruct (book_first_match_first_bit_halt
    (tl hit_init ++ [hd false hit_init])
    (map bf_row steps ++ hit :: next :: rest)
    (app_cons_book_row_neq_nil (map bf_row steps) hit (next :: rest))
    Hrot Hrows)
    as [steps_fail [last_fail Hbf]].
  exists steps_fail, last_fail. split.
  - apply (lic_q5_encode_lifted_boundary_step_premises lo c steps hit
      next rest hit_init hit_w c0 creast steps_fail last_fail tail
      Hrawbuf Hptape Hne Hsteps Hcond Hlen Hact Hdir Hnext Hbf).
  - unfold boundary_halt_encode_from_failed, dispatch_halt_at_y.
    reflexivity.
Qed.

Print Assumptions lic_q5_encode_lifted_boundary_halt.

(** ** Lifted source-row instantiation *)

Theorem lic_q5_encode_lifted_boundary_halt_state :
  forall (lo : Z) (c : LeftInfiniteConfig) (rows : list WideSourceRow)
         (r : WideSourceRow) (rows_book : list book_row)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_w c0 : bool) (creast : list bool)
         (tail : list nat),
    raw_buf c = [] ->
    raw_ptape_prefix c lo ++ [source_bit (raw_last c lo)] =
      raw_ptape c lo ->
    rows_book = lic_book_rows (lic_lift_rows rows) ->
    hit = source_row_to_book (lic_lift_row r) ->
    rows_book = map bf_row steps ++ hit :: next :: rest ->
    Forall (fun st =>
      bf_src st = lic_state c ++ [lic_tape c (lic_head c)]) steps ->
    br_cond hit = lic_state c ++ [lic_tape c (lic_head c)] ->
    length (br_action hit) =
      length (lic_state c ++ [lic_tape c (lic_head c)]) ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    exists steps_fail last_fail,
      run (lic_q5_empty_boundary_clock lo c steps hit
             (lic_lift_state (wr_next r)) (wr_write r)
             steps_fail last_fail)
        (lic_q5_encode lo c rows_book tail)
      = boundary_halt_encode_from_failed [6] [] steps_fail last_fail
          (source_bit (wr_write r) :: rev (raw_ptape c lo)) tail /\
      c_halted
        (boundary_halt_encode_from_failed [6] [] steps_fail last_fail
          (source_bit (wr_write r) :: rev (raw_ptape c lo)) tail) = true.
Proof.
  intros lo c rows r rows_book steps hit next rest hit_w c0 creast tail
    Hrawbuf Hptape Hrows_book Hhit Hrows0 Hsteps Hcond Hlen Hdir Hnext.
  assert (Hact : br_action hit =
    lic_lift_state (wr_next r) ++ [wr_write r]).
  { rewrite Hhit. reflexivity. }
  assert (Hhit_init : lic_lift_state (wr_next r) <> []).
  { unfold lic_lift_state. discriminate. }
  assert (Hrot : exists s,
    tl (lic_lift_state (wr_next r)) ++
      [hd false (lic_lift_state (wr_next r))] = true :: s).
  { exists (wr_next r ++ [false]).
    unfold lic_lift_state. cbn. reflexivity. }
  assert (Hrows_lift : Forall
    (fun br => exists s, br_cond br = false :: s)
    rows_book).
  { rewrite Hrows_book. apply lic_book_rows_lift_first_bit. }
  assert (Hrows : forall r0, In r0
    (map bf_row steps ++ hit :: next :: rest) ->
    exists s, br_cond r0 = false :: s).
  { intros r0 Hin.
    apply (proj1 (Forall_forall
      (fun br => exists s, br_cond br = false :: s) rows_book)
      Hrows_lift r0).
    rewrite Hrows0. exact Hin. }
  assert (Hlen0 : length (br_action hit) =
    length (lic_state c ++ [lic_tape c (lic_head c)])) by exact Hlen.
  destruct (lic_q5_encode_lifted_boundary_halt lo c steps hit next rest
    (lic_lift_state (wr_next r)) (wr_write r) c0 creast tail
    Hrawbuf Hptape Hhit_init Hsteps Hcond Hlen Hact Hdir Hnext Hrot
    Hrows) as [steps_fail [last_fail [Hrun Hhalted]]].
  exists steps_fail, last_fail. split.
  - rewrite Hrows0. exact Hrun.
  - exact Hhalted.
Qed.

Print Assumptions lic_q5_encode_lifted_boundary_halt_state.
