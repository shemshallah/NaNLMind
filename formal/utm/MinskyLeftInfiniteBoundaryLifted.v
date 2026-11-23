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
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
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
