(** * Clock invariance under the left-window choice

    The left window only changes the passive ptape; no native clock reads
    it.  This file records the boundary-clock instance. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft MinskyLeftInfiniteEncoding
  MinskyLeftInfiniteBoundary MinskyLeftInfiniteBoundaryLocate
  MinskyLeftInfiniteBoundaryBook MinskyLeftInfiniteBoundaryPremises
  MinskyLeftInfiniteBoundaryFinal MinskyLeftInfiniteBoundaryLookup
  MinskyLeftInfiniteBoundaryLifted MinskyLeftInfiniteLift
  MinskyLeftInfiniteBounded MinskyLeftInfiniteLeftDepth.

Local Open Scope nat_scope.

Lemma lic_q5_empty_boundary_clock_lo_ind :
  forall (lo lo' : Z) (c : LeftInfiniteConfig)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool)
         (steps_fail : list book_failure) (last_fail : book_failure),
    lic_q5_empty_boundary_clock lo c steps hit hit_init hit_w
      steps_fail last_fail =
    lic_q5_empty_boundary_clock lo' c steps hit hit_init hit_w
      steps_fail last_fail.
Proof. intros. reflexivity. Qed.

Print Assumptions lic_q5_empty_boundary_clock_lo_ind.
