(** * Raw window arithmetic for the left-infinite source step

    This file proves the step-to-window mapping lemmas:

      raw_buf  (step c) = tail (raw_buf c)          (right, head < R)
      raw_ptape(step c) = raw_ptape c ++ [write]    (right, lo <= head)
      raw_last (step c) = write                     (right)
      tape(step c)(head+1) = raw_to_bool (hd buf)   (right)

    and the left analogues:

      raw_buf  (step c) = write :: raw_buf c        (left)
      raw_ptape(step c)(lo-1) = prefix of raw_ptape c (lo-1)
                                                  (left, with window shift)

    These are [seq]/[Z.to_nat] identities, not table traces. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode.

(** ** Generic list/seq helpers *)

Lemma tail_map_seq :
  forall (A : Type) (f : nat -> A) (n : nat),
    0 < n ->
    tl (map f (seq 0 n)) =
    map (fun k => f (S k)) (seq 0 (n - 1)).
Proof.
  intros A f n Hpos.
  destruct n as [|m]; [lia|].
  replace (S m - 1) with m by lia.
  cbn [seq map tl].
  rewrite <- (seq_shift m 0).
  rewrite map_map. reflexivity.
Qed.

Lemma map_seq_snoc :
  forall (A : Type) (f : nat -> A) (n : nat),
    map f (seq 0 (S n)) = map f (seq 0 n) ++ [f n].
Proof.
  intros A f n.
  rewrite seq_S.
  rewrite map_app. cbn [map]. reflexivity.
Qed.

Lemma Z_to_nat_sub_succ :
  forall (a b : Z),
    (a < b)%Z ->
    Z.to_nat (b - (a + 1)%Z) = Z.to_nat (b - a) - 1.
Proof.
  intros a b Hlt.
  replace (b - (a + 1))%Z with (b - a - 1)%Z by lia.
  rewrite Z2Nat.inj_sub by lia.
  cbn [Z.to_nat]. lia.
Qed.

Lemma Z_to_nat_succ_sub :
  forall (a b : Z),
    (a <= b)%Z ->
    Z.to_nat (b + 1 - a) = S (Z.to_nat (b - a)).
Proof.
  intros a b Hle.
  replace (b + 1 - a)%Z with (Z.succ (b - a))%Z by lia.
  rewrite Z2Nat.inj_succ by lia.
  reflexivity.
Qed.

Lemma Z_to_nat_add_one :
  forall (a b : Z),
    (a <= b)%Z ->
    Z.to_nat (b - a + 1) = S (Z.to_nat (b - a)).
Proof.
  intros a b Hle.
  replace (b - a + 1)%Z with (Z.succ (b - a))%Z by lia.
  rewrite Z2Nat.inj_succ by lia.
  reflexivity.
Qed.

(** ** Right window: buffer decrements *)

Lemma Z_to_nat_pos_of_pos :
  forall z : Z, (0 < z)%Z -> 0 < Z.to_nat z.
Proof.
  intros z Hpos.
  pose proof (proj1 (Z2Nat.inj_lt 0 z ltac:(lia) ltac:(lia)) Hpos) as Hn.
  cbn [Z.to_nat] in Hn. exact Hn.
Qed.

Lemma raw_buf_length_pos :
  forall c, (lic_head c < lic_R c)%Z ->
    0 < Z.to_nat (lic_R c - lic_head c).
Proof. intros c Hlt. apply Z_to_nat_pos_of_pos. lia. Qed.

Lemma source_write_at_below :
  forall (t : Z -> bool) (h z : Z) (bit : bool),
    (z < h)%Z -> source_write_at t h bit z = t z.
Proof.
  intros t h z bit Hlt.
  unfold source_write_at.
  destruct (Z.eqb z h) eqn:E.
  - apply Z.eqb_eq in E. lia.
  - reflexivity.
Qed.

Lemma raw_to_bool_source_bit_bool :
  forall b, raw_to_bool (source_bit b) = b.
Proof. intros []; reflexivity. Qed.

Lemma raw_buf_nonempty :
  forall c, (lic_head c < lic_R c)%Z -> raw_buf c <> [].
Proof.
  intros c Hlt Hnil.
  assert (Hlen : length (raw_buf c) =
                 Z.to_nat (lic_R c - lic_head c))
    by (apply raw_buf_length; lia).
  rewrite Hnil in Hlen. cbn [length] in Hlen.
  assert (Hpos : (0 < lic_R c - lic_head c)%Z) by lia.
  assert (Hnpos : 0 < Z.to_nat (lic_R c - lic_head c)).
  { pose proof (proj1 (Z2Nat.inj_lt 0 (lic_R c - lic_head c)
      ltac:(lia) ltac:(lia)) Hpos) as Hn.
    cbn [Z.to_nat] in Hn. exact Hn. }
  rewrite <- Hlen in Hnpos. cbn [length] in Hnpos. lia.
Qed.

Lemma raw_buf_hd :
  forall c,
    raw_buf c <> [] ->
    hd 0 (raw_buf c) = source_bit (lic_tape c (lic_head c + 1)).
Proof.
  intros c Hne.
  unfold raw_buf.
  destruct (Z.to_nat (lic_R c - lic_head c)) as [|m] eqn:E.
  - exfalso. apply Hne. unfold raw_buf. rewrite E. reflexivity.
  - cbn [seq map hd]. rewrite Z.add_0_r. reflexivity.
Qed.

Lemma raw_buf_right_step :
  forall rows c r,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    raw_buf (left_infinite_step rows c) = tl (raw_buf c).
Proof.
  intros rows c r Hh Hlookup Hright Hlt.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright.
    destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E.
    - apply Z.eqb_eq in E. lia.
    - reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [Htape [HR _]]]].
  rewrite Hright in Hhead.
  unfold raw_buf.
  rewrite Hhead, Htape, HR.
  rewrite (Z_to_nat_sub_succ (lic_head c) (lic_R c) Hlt).
  rewrite (tail_map_seq nat
    (fun k => source_bit (lic_tape c (lic_head c + 1 + Z.of_nat k)))
    (Z.to_nat (lic_R c - lic_head c)) (raw_buf_length_pos c Hlt)).
  apply map_ext. intros k.
  rewrite source_write_at_above by lia.
  f_equal. f_equal.
  replace (Z.of_nat (S k)) with (Z.of_nat k + 1)%Z by lia.
  ring.
Qed.

Lemma raw_buf_right_step_hd :
  forall rows c r,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    hd 0 (raw_buf c) = source_bit (lic_tape c (lic_head c + 1)).
Proof.
  intros. apply raw_buf_hd. apply raw_buf_nonempty. exact H2.
Qed.

(** ** Right window: ptape appends the write bit *)

Lemma raw_ptape_right_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    (lo <= lic_head c)%Z ->
    raw_ptape (left_infinite_step rows c) lo =
    raw_ptape c lo ++ [source_bit (wr_write r)].
Proof.
  intros rows c r lo Hh Hlookup Hright Hlt Hle.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright.
    destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E.
    - apply Z.eqb_eq in E. lia.
    - reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [Htape [HR _]]]].
  rewrite Hright in Hhead.
  unfold raw_ptape at 1.
  rewrite Hhead, Htape.
  rewrite (Z_to_nat_succ_sub lo (lic_head c) Hle).
  rewrite map_seq_snoc.
  assert (Hpre : map
      (fun k => source_bit
        (source_write_at (lic_tape c) (lic_head c) (wr_write r)
          (lo + Z.of_nat k)))
      (seq 0 (Z.to_nat (lic_head c - lo))) =
      raw_ptape c lo).
  { unfold raw_ptape.
    apply map_ext_in. intros k Hk.
    apply in_seq in Hk. destruct Hk as [_ Hk].
    rewrite source_write_at_below by lia.
    reflexivity. }
  rewrite Hpre.
  rewrite (Z2Nat.id (lic_head c - lo) ltac:(lia)).
  replace (lo + (lic_head c - lo))%Z with (lic_head c)%Z by ring.
  unfold source_write_at. rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma raw_ptape_prefix_right_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    (lo <= lic_head c)%Z ->
    raw_ptape_prefix (left_infinite_step rows c) lo = raw_ptape c lo.
Proof.
  intros rows c r lo Hh Hlookup Hright Hlt Hle.
  unfold raw_ptape_prefix.
  rewrite (raw_ptape_right_step rows c r lo Hh Hlookup Hright Hlt Hle).
  rewrite rev_app_distr. cbn [rev app].
  rewrite rev_involutive. reflexivity.
Qed.

Lemma raw_last_right_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    (lo <= lic_head c)%Z ->
    raw_last (left_infinite_step rows c) lo = wr_write r.
Proof.
  intros rows c r lo Hh Hlookup Hright Hlt Hle.
  unfold raw_last.
  rewrite (raw_ptape_right_step rows c r lo Hh Hlookup Hright Hlt Hle).
  rewrite rev_app_distr. cbn [rev app].
  rewrite raw_to_bool_source_bit_bool.
  reflexivity.
Qed.

Lemma raw_read_right_step :
  forall rows c r,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    lic_tape (left_infinite_step rows c) (lic_head c + 1) =
    raw_to_bool (hd 0 (raw_buf c)).
Proof.
  intros rows c r Hh Hlookup Hright Hlt.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright.
    destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E.
    - apply Z.eqb_eq in E. lia.
    - reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [_ [Htape _]]].
  rewrite Htape.
  rewrite source_write_at_above by lia.
  rewrite (raw_buf_hd c (raw_buf_nonempty c Hlt)).
  rewrite raw_to_bool_source_bit_bool.
  reflexivity.
Qed.

Print Assumptions raw_buf_right_step.
Print Assumptions raw_ptape_right_step.
Print Assumptions raw_ptape_prefix_right_step.
Print Assumptions raw_last_right_step.
Print Assumptions raw_read_right_step.

(** ** Left window: buffer prepends the write bit *)

Lemma raw_buf_left_step :
  forall rows c r,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lic_head c <= lic_R c)%Z ->
    raw_buf (left_infinite_step rows c) =
    source_bit (wr_write r) :: raw_buf c.
Proof.
  intros rows c r Hh Hlookup Hright Hle.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright. reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [Htape [HR _]]]].
  rewrite Hright in Hhead.
  unfold raw_buf.
  rewrite Hhead, Htape, HR.
  replace (lic_R c - (lic_head c + -1))%Z
    with (lic_R c - lic_head c + 1)%Z by lia.
  rewrite (Z_to_nat_add_one (lic_head c) (lic_R c) Hle).
  cbn [seq map].
  rewrite <- (seq_shift (Z.to_nat (lic_R c - lic_head c)) 0).
  rewrite map_map.
  f_equal.
  - replace (lic_head c + -1 + 1 + Z.of_nat 0)%Z with (lic_head c)%Z
      by ring.
    unfold source_write_at. rewrite Z.eqb_refl. reflexivity.
  - apply map_ext. intros k.
    rewrite source_write_at_above by lia.
    f_equal. f_equal.
    replace (Z.of_nat (S k)) with (Z.of_nat k + 1)%Z by lia.
    ring.
Qed.


Print Assumptions raw_buf_left_step.

(** ** Left ptape window: the prefix drop *)

Lemma Z_add_neg_sub_diag :
  forall z : Z, (z + (-1)%Z - z)%Z = (-1)%Z.
Proof. intros. ring. Qed.

Lemma snoc_neq_nil :
  forall (A : Type) (l : list A) (x : A),
    l ++ [x] <> [].
Proof.
  intros A l x H.
  destruct (app_eq_nil l [x] H) as [_ Hx]. discriminate Hx.
Qed.

Lemma tl_app :
  forall (A : Type) (l1 l2 : list A),
    l1 <> [] -> tl (l1 ++ l2) = tl l1 ++ l2.
Proof.
  intros A l1 l2 Hne.
  destruct l1 as [|x xs]; [contradiction|reflexivity].
Qed.

Lemma rev_tl_rev :
  forall (A : Type) (l : list A),
    rev (tl (rev l)) = removelast l.
Proof.
  intros A l. induction l as [|a rest IH].
  - reflexivity.
  - destruct rest as [|b rest'].
    + reflexivity.
    + cbn [rev].
      rewrite tl_app.
      2:{ change (rev rest' ++ [b] <> []). apply snoc_neq_nil. }
      rewrite rev_app_distr. cbn [rev].
      change (([] ++ [a]) ++ rev (tl (rev (b :: rest'))) =
              removelast (a :: b :: rest')).
      rewrite IH.
      cbn [removelast]. reflexivity.
Qed.

Lemma raw_ptape_prefix_removelast :
  forall c lo,
    raw_ptape_prefix c lo = removelast (raw_ptape c lo).
Proof.
  intros c lo. unfold raw_ptape_prefix.
  destruct (rev (raw_ptape c lo)) as [|s rest] eqn:H.
  - assert (Hnil : raw_ptape c lo = []).
    { apply (f_equal (@rev nat)) in H.
      rewrite rev_involutive in H. exact H. }
    rewrite Hnil. reflexivity.
  - cbn [rev].
    assert (Hrev : raw_ptape c lo = rev (s :: rest)).
    { apply (f_equal (@rev nat)) in H.
      rewrite rev_involutive in H. exact H. }
    rewrite Hrev. cbn [rev].
    rewrite removelast_last. reflexivity.
Qed.

Lemma removelast_map_seq_pos :
  forall (f : nat -> nat) (n : nat),
    0 < n -> removelast (map f (seq 0 n)) = map f (seq 0 (n - 1)).
Proof.
  intros f n Hpos.
  destruct n as [|m]; [lia|].
  replace (S m - 1) with m by lia.
  rewrite seq_S. rewrite map_app. cbn [map].
  rewrite removelast_app by discriminate.
  rewrite app_nil_r. reflexivity.
Qed.

Lemma raw_ptape_length_pos :
  forall c lo, (lo < lic_head c)%Z ->
    0 < Z.to_nat (lic_head c - lo).
Proof.
  intros c lo Hlt. apply Z_to_nat_pos_of_pos. lia.
Qed.

Lemma raw_ptape_left_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lo <= lic_head c)%Z ->
    raw_ptape (left_infinite_step rows c) lo =
    raw_ptape_prefix c lo.
Proof.
  intros rows c r lo Hh Hlookup Hright Hle.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright. reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [Htape _]]].
  rewrite Hright in Hhead.
  destruct (Z.eq_dec lo (lic_head c)) as [Heq | Hneq].
  - subst lo.
    unfold raw_ptape, raw_ptape_prefix.
    rewrite Hhead, Htape.
    rewrite Z_add_neg_sub_diag.
    unfold raw_ptape.
    rewrite Z.sub_diag.
    cbn [Z.to_nat seq map rev].
    reflexivity.
  - assert (Hlt : (lo < lic_head c)%Z) by lia.
    unfold raw_ptape at 1.
    rewrite Hhead, Htape.
    rewrite raw_ptape_prefix_removelast.
    unfold raw_ptape.
    replace (lic_head c + -1 - lo)%Z with (lic_head c - (lo + 1))%Z by lia.
    rewrite (Z_to_nat_sub_succ lo (lic_head c) Hlt).
    rewrite removelast_map_seq_pos.
    2:{ apply raw_ptape_length_pos. exact Hlt. }
    apply map_ext_in. intros k Hk.
    apply in_seq in Hk. destruct Hk as [_ Hk].
    rewrite source_write_at_below by lia.
    reflexivity.
Qed.

Print Assumptions raw_ptape_left_step.

(** ** Left companions: prefix drop, last, read *)

Definition last_raw (l : list nat) : bool :=
  match rev l with
  | [] => false
  | s :: _ => raw_to_bool s
  end.

Lemma raw_ptape_prefix_left_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lo <= lic_head c)%Z ->
    raw_ptape_prefix (left_infinite_step rows c) lo =
    removelast (raw_ptape_prefix c lo).
Proof.
  intros rows c r lo Hh Hlookup Hright Hle.
  rewrite raw_ptape_prefix_removelast.
  rewrite (raw_ptape_left_step rows c r lo Hh Hlookup Hright Hle).
  reflexivity.
Qed.

Lemma last_app_singleton :
  forall (A : Type) (l : list A) (x d : A),
    last (l ++ [x]) d = x.
Proof.
  intros A l. induction l as [|a rest IH]; intros x d.
  - reflexivity.
  - cbn [app last].
    destruct (rest ++ [x]) as [|y ys] eqn:E.
    + exfalso. apply (snoc_neq_nil A rest x). exact E.
    + rewrite <- E. apply IH.
Qed.

Lemma last_map_seq :
  forall (f : nat -> nat) (n : nat) (d : nat),
    0 < n -> last (map f (seq 0 n)) d = f (n - 1).
Proof.
  intros f n d Hpos.
  destruct n as [|m]; [lia|].
  replace (S m - 1) with m by lia.
  rewrite seq_S. rewrite map_app. cbn [map].
  rewrite last_app_singleton.
  cbn [Nat.add]. reflexivity.
Qed.

Lemma source_bit_inj :
  forall b1 b2, source_bit b1 = source_bit b2 -> b1 = b2.
Proof. intros [] [] H; try reflexivity; discriminate H. Qed.

Lemma raw_ptape_last_tape :
  forall c lo,
    (lo < lic_head c)%Z ->
    last (raw_ptape c lo) 0 =
    source_bit (lic_tape c (lic_head c - 1)).
Proof.
  intros c lo Hlt.
  unfold raw_ptape.
  rewrite (last_map_seq
    (fun k => source_bit (lic_tape c (lo + Z.of_nat k)))
    (Z.to_nat (lic_head c - lo)) 0
    (raw_ptape_length_pos c lo Hlt)).
  f_equal.
  replace (Z.of_nat (Z.to_nat (lic_head c - lo) - 1))
    with (Z.of_nat (Z.to_nat (lic_head c - lo)) - 1)%Z.
  2:{ rewrite Nat2Z.inj_sub by lia. cbn [Z.of_nat]. reflexivity. }
  rewrite (Z2Nat.id (lic_head c - lo) ltac:(lia)).
  f_equal.
  lia.
Qed.

Lemma raw_last_eq_tape :
  forall c lo,
    (lo < lic_head c)%Z ->
    raw_last c lo = lic_tape c (lic_head c - 1).
Proof.
  intros c lo Hlt.
  assert (Hne : raw_ptape c lo <> [])
    by (apply raw_ptape_nonempty; exact Hlt).
  pose proof (raw_ptape_prefix_last c lo Hne) as Hsplit.
  pose proof (app_removelast_last (l := raw_ptape c lo) 0 Hne) as Hlast.
  rewrite <- raw_ptape_prefix_removelast in Hlast.
  assert (Heq : raw_ptape_prefix c lo ++ [source_bit (raw_last c lo)] =
                raw_ptape_prefix c lo ++ [last (raw_ptape c lo) 0]).
  { rewrite Hsplit. rewrite Hlast at 1. reflexivity. }
  apply source_bit_inj.
  pose proof (@app_inv_head nat (raw_ptape_prefix c lo)
    [source_bit (raw_last c lo)] [last (raw_ptape c lo) 0] Heq) as Hsingle.
  injection Hsingle as Hx.
  rewrite Hx. apply raw_ptape_last_tape. exact Hlt.
Qed.

Lemma raw_last_left_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lo <= lic_head c)%Z ->
    raw_last (left_infinite_step rows c) lo =
    last_raw (raw_ptape_prefix c lo).
Proof.
  intros rows c r lo Hh Hlookup Hright Hle.
  unfold raw_last, last_raw.
  rewrite (raw_ptape_left_step rows c r lo Hh Hlookup Hright Hle).
  reflexivity.
Qed.

Lemma raw_read_left_step :
  forall rows c r lo,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lo < lic_head c)%Z ->
    lic_tape (left_infinite_step rows c) (lic_head c - 1) =
    raw_last c lo.
Proof.
  intros rows c r lo Hh Hlookup Hright Hlt.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright. reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [Htape _]]].
  rewrite Hright in Hhead.
  rewrite Htape.
  rewrite source_write_at_below by lia.
  symmetry. apply raw_last_eq_tape. exact Hlt.
Qed.

Print Assumptions raw_ptape_prefix_left_step.
Print Assumptions raw_last_left_step.
Print Assumptions raw_read_left_step.
