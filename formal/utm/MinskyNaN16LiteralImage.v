(** * ISA-OBL-2: the literal assembled image against the Coq fixture

    This file closes the image-side gap left by
    [MinskyNaN16LiteralDecode.v] (ISA-OBL-1, word 0 only).  It starts from
    the full 4366-word assembled fixture image reproduced from

      mth/tests/mth_minsky_test.nas
        sha256 173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e
      third_party/nan0s/tools/nmk.awk  (HEAD blob)
        sha256 587116bdffc7715d0dffd6846767dbda76a9d14b55085e9ed8ed08cbdfe1009b
      LC_ALL=C gawk -f nmk.awk -v CMD=emit ...

    The exact assembler text is checked in as
    [formal/utm/data/mth_minsky_test.nan] with sha256

      f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77

    (4366 words, 141409 bytes including comments).  The word-only dump
    [formal/utm/data/mth_minsky_test.words] has sha256

      43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7

    and [LiteralImageData.v] is its Coq [N] transcription.  The Python
    checker [check_nan16_literal_image.py] cross-checks all three
    representations and can re-run the pinned assembler from git HEAD
    with [--assemble].  The hash strings are pinned as Coq constants
    below, but the cryptographic check itself is external; nothing here
    is an axiom or an admitted obligation.

    What is proved:

    - [literal_image] has exactly 4366 words;
    - the code slices [0,84) and [96,99) decode, word for word, to the
      fixture instruction lists [main], [run100], [step prelude],
      [scan], [action], [step_ret], [next], [no_trans], and [fail];
    - the data cells at 99/100/101/102/103 hold the literal
      [tbase=4096, state=0, head=0, halt=0, rlink=0] values;
    - the 184x8 table payload slice at 104..1575 is exactly
      [fixture_table] from [MinskyNaN16RunConcrete.v];
    - the tape base cell 99 payload is [fixture_tape_base = 4096], the
      128-word prefix at 4096..4223 is all payload 2, and the
      [.org 4096] padding at 1649..4095 is all payload 0.

    Scope and honest gaps (ISA-OBL-2 is not the full literal-image
    refinement):

    - The decoder covers exactly the [Instr] subset of
      [MinskyNaN16VM.v]: MOVI, ST, LD, CMP, JMP[p], CALL, RET, ADD, SUB,
      SHL, HALT.  The [puts] block [84,96) uses BOOL.8, PUTC, SHR and a
      predicated RET; those are not in [Instr], so that block is not
      decoded here.  [main] still calls it at word 27 and [fail] at 97,
      which is fine for a word-level decode but is not a run theorem.
    - The predicate decoder accepts only the four [n] values that occur
      in the covered slices: 3 (NE), 4 (EQ), 5 (GE), 15 (ALWAYS).
    - The image is a text/Coq dump, not a raw binary blob; the pinned
      hash is over the assembler's exact stdout text.
    - The loader, host byte order, and [nan_cli] are outside this file.
      The payload projection [payload_word] is the same one used by
      [MinskyNaN16LiteralDecode.R]. *)

From Coq Require Import List Arith Bool Lia NArith.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralDecode
  MinskyNaN16Action MinskyNaN16Prelude MinskyNaN16RunConcrete
  LiteralImageData.

Open Scope nat_scope.

(** ** Image lookup and pins *)

Definition literal_word_at (i : nat) : N := nth i literal_image 0%N.

Lemma literal_image_4366 : length literal_image = 4366.
Proof. exact literal_image_length. Qed.

(** The two textual pins, available to other Coq modules.  The checker
    script proves the strings agree with the files; Coq records them. *)
Definition literal_image_pin : N := literal_image_sha256.
Definition literal_words_pin : N := literal_words_sha256.

(** The pins are 256-bit hexadecimal numerals in [N]; the strings in the
    generated file and in this comment are the external representation. *)
Lemma literal_image_pin_value :
  literal_image_pin =
  0xF78CCB99EB0843B849A2560E0D27A09606C787A94366562A6A90B2C606C0BF77%N.
Proof. reflexivity. Qed.

Lemma literal_words_pin_value :
  literal_words_pin =
  0x43FBE83226221463B91D99862EBA53CDB61A2FB7BA59D397ABC755AF4522A7D7%N.
Proof. reflexivity. Qed.

Theorem literal_image_pin_and_shape :
  literal_image_pin =
    0xF78CCB99EB0843B849A2560E0D27A09606C787A94366562A6A90B2C606C0BF77%N /\
  literal_words_pin =
    0x43FBE83226221463B91D99862EBA53CDB61A2FB7BA59D397ABC755AF4522A7D7%N /\
  length literal_image = 4366.
Proof.
  split; [apply literal_image_pin_value|split].
  - apply literal_words_pin_value.
  - apply literal_image_4366.
Qed.

(** ** Full-field decoder for the [Instr] subset

    The field layout is the one of [MinskyNaN16LiteralDecode.v].  The
    predicate field is the NaN16 truth-table selector [n]; in the
    covered slices only NE (3), EQ (4), GE (5), and ALWAYS (15) occur. *)

Definition pred_of_n (n : nat) : option preg :=
  match n with
  | 3 => Some pNE
  | 4 => Some pEQ
  | 5 => Some pGE
  | 15 => Some pALWAYS
  | _ => None
  end.

Definition decode_word_full (w : N) : option Instr :=
  if andb (nan_hvalid (word_near w)) (nan_hvalid (word_far w)) then
    let op := word_op w in
    let d := word_d w in
    let a := word_a w in
    let imm := word_imm w in
    if Nat.eqb op 1 then Some (iMOVI d imm)
    else if Nat.eqb op 3 then Some (iADD d a imm)
    else if Nat.eqb op 4 then Some (iSUB d a imm)
    else if Nat.eqb op 5 then Some (iSHL d a imm)
    else if Nat.eqb op 7 then Some (iCMP a imm)
    else if Nat.eqb op 8 then Some (iLD d a imm)
    else if Nat.eqb op 9 then Some (iST d a imm)
    else if Nat.eqb op 10 then
      match pred_of_n (word_n w) with
      | Some p => Some (iJMP p imm)
      | None => None
      end
    else if Nat.eqb op 11 then Some (iCALL imm)
    else if Nat.eqb op 12 then
      if Nat.eqb (word_n w) 15 then Some iRET else None
    else if Nat.eqb op 255 then
      if Nat.eqb (word_n w) 15 then Some iHALT else None
    else None
  else None.

Fixpoint decode_list (ws : list N) : option (list Instr) :=
  match ws with
  | [] => Some []
  | w :: rest =>
      match decode_word_full w, decode_list rest with
      | Some ins, Some ins' => Some (ins :: ins')
      | _, _ => None
      end
  end.

Definition decode_range (lo hi : nat) : option (list Instr) :=
  decode_list (map literal_word_at (seq lo (hi - lo))).

(** ** Decoded fixture slices

    The boundaries are the literal labels of NAN0S_LAYOUT.md:
    main 0, run100 29, step 36, scan 47, mleft 67, mdone 70,
    step_ret 78, next 79, no_trans 81, puts 84, fail 96.  The [puts]
    block is deliberately absent: its instructions are outside [Instr]. *)

Definition slice_main : list Instr := [
  iMOVI 13 1;
  iMOVI 1 5;
  iST 1 0 100;
  iMOVI 1 166;
  iST 1 0 101;
  iST 0 0 102;
  iCALL 29;
  iLD 1 0 100;
  iMOVI 2 2;
  iCMP 1 2;
  iJMP pNE 96;
  iLD 1 0 101;
  iMOVI 2 166;
  iCMP 1 2;
  iJMP pNE 96;
  iMOVI 3 4224;
  iMOVI 4 1576;
  iMOVI 5 73;
  iLD 1 3 0;
  iLD 2 4 0;
  iCMP 1 2;
  iJMP pNE 96;
  iADD 3 3 13;
  iADD 4 4 13;
  iSUB 5 5 13;
  iJMP pNE 18;
  iMOVI 1 4352;
  iCALL 84;
  iHALT
].

Definition slice_run100 : list Instr := [
  iST 15 0 103;
  iMOVI 11 100;
  iCALL 36;
  iSUB 11 11 13;
  iJMP pNE 31;
  iLD 15 0 103;
  iRET
].

Definition slice_step_prelude : list Instr := [
  iLD 1 0 102;
  iCMP 1 0;
  iJMP pNE 78;
  iLD 1 0 100;
  iLD 2 0 101;
  iLD 3 0 99;
  iADD 3 3 2;
  iLD 4 3 0;
  iMOVI 5 104;
  iMOVI 6 184;
  iMOVI 8 0
].

Definition slice_scan : list Instr := [
  iCMP 8 6;
  iJMP pGE 81;
  iSHL 7 8 3;
  iADD 7 7 5;
  iLD 9 7 0;
  iCMP 9 1;
  iJMP pNE 79;
  iLD 9 7 1;
  iCMP 9 4;
  iJMP pNE 79;
  iLD 9 7 2;
  iST 9 3 0;
  iLD 9 7 3;
  iMOVI 10 0;
  iCMP 9 10;
  iJMP pEQ 67;
  iMOVI 10 2;
  iCMP 9 10;
  iJMP pEQ 69;
  iJMP pALWAYS 70
].

Definition slice_action : list Instr := [
  iSUB 2 2 13;
  iJMP pALWAYS 70;
  iADD 2 2 13;
  iST 2 0 101;
  iLD 9 7 4;
  iST 9 0 100;
  iLD 9 7 5;
  iCMP 9 0;
  iJMP pEQ 78;
  iMOVI 9 1;
  iST 9 0 102
].

Definition slice_step_ret : list Instr := [ iRET ].

Definition slice_next : list Instr := [
  iADD 8 8 13;
  iJMP pALWAYS 47
].

Definition slice_no_trans : list Instr := [
  iMOVI 9 1;
  iST 9 0 102;
  iRET
].

Definition slice_fail : list Instr := [
  iMOVI 1 4359;
  iCALL 84;
  iHALT
].

(** ** Word 0 and the ISA-OBL-1 bridge *)

Lemma literal_word_0 : literal_word_at 0 = 0xFFF801D00001F8FF%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_decodes_full :
  decode_word_full (literal_word_at 0) = Some (iMOVI 13 1).
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word0_decodes_movi :
  decode_word (literal_word_at 0) = Some (iMOVI 13 1).
Proof.
  rewrite literal_word_0. apply decode_word_literal_word0.
Qed.

(** ** Code-slice decode theorems *)

Lemma decode_slice_main :
  decode_range 0 29 = Some slice_main.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_run100 :
  decode_range 29 36 = Some slice_run100.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_step_prelude :
  decode_range 36 47 = Some slice_step_prelude.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_scan :
  decode_range 47 67 = Some slice_scan.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_action :
  decode_range 67 78 = Some slice_action.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_step_ret :
  decode_range 78 79 = Some slice_step_ret.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_next :
  decode_range 79 81 = Some slice_next.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_no_trans :
  decode_range 81 84 = Some slice_no_trans.
Proof. vm_compute. reflexivity. Qed.

Lemma decode_slice_fail :
  decode_range 96 99 = Some slice_fail.
Proof. vm_compute. reflexivity. Qed.

(** The contiguous supported code block [0,84) is exactly the
    concatenation of the named slices, in address order. *)
Lemma decode_supported_code :
  decode_range 0 84 =
  Some (slice_main ++ slice_run100 ++ slice_step_prelude ++ slice_scan ++
        slice_action ++ slice_step_ret ++ slice_next ++ slice_no_trans).
Proof. vm_compute. reflexivity. Qed.

Lemma slice_lengths :
  length slice_main = 29 /\
  length slice_run100 = 7 /\
  length slice_step_prelude = 11 /\
  length slice_scan = 20 /\
  length slice_action = 11 /\
  length slice_step_ret = 1 /\
  length slice_next = 2 /\
  length slice_no_trans = 3 /\
  length slice_fail = 3.
Proof. vm_compute. repeat split; reflexivity. Qed.

(** ** Data cells 99..103 *)

Lemma literal_word_99 : literal_word_at 99 = 0x7FF800001000F87F%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word_100 : literal_word_at 100 = 0x7FF800000000F87F%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word_101 : literal_word_at 101 = 0x7FF800000000F87F%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word_102 : literal_word_at 102 = 0x7FF800000000F87F%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_word_103 : literal_word_at 103 = 0x7FF800000000F87F%N.
Proof. vm_compute. reflexivity. Qed.

(** The [tbase] cell at 99 carries the tape image base 4096. *)
Lemma literal_tbase_cell :
  payload_word (literal_word_at tape_base_addr) = fixture_tape_base.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_state_cell :
  payload_word (literal_word_at action_state_addr) = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_head_cell :
  payload_word (literal_word_at action_head_addr) = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_halt_cell :
  payload_word (literal_word_at action_halt_addr) = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_rlink_cell :
  payload_word (literal_word_at 103) = 0.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_data_cells :
  payload_word (literal_word_at 99) = 4096 /\
  payload_word (literal_word_at 100) = 0 /\
  payload_word (literal_word_at 101) = 0 /\
  payload_word (literal_word_at 102) = 0 /\
  payload_word (literal_word_at 103) = 0.
Proof. vm_compute. repeat split; reflexivity. Qed.

(** ** Table slice 104..1575 *)

(** The payload projection of the 184x8 words beginning at the literal
    [fixture_table_base].  The rows are laid out exactly as the fixture
    scan expects: row [i], field [f] is word [104 + 8*i + f]. *)
Definition literal_table_rows : list (list nat) :=
  map (fun i =>
         map (fun f =>
                payload_word
                  (literal_word_at (fixture_table_base + 8 * i + f)))
             (seq 0 8))
      (seq 0 (length fixture_table)).

(** The literal table slice is the Coq fixture table, not merely a list
    of the same length.  This is the address-sensitive image-side table
    correspondence. *)
Theorem literal_table_slice_eq_fixture :
  literal_table_rows = fixture_table.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_table_slice_shape :
  length literal_table_rows = 184 /\
  Forall (fun row => length row = 8) literal_table_rows.
Proof.
  split.
  - rewrite literal_table_slice_eq_fixture. apply fixture_table_length.
  - rewrite literal_table_slice_eq_fixture. apply fixture_table_rows8.
Qed.

Lemma literal_table_slice_base :
  fixture_table_base = 104.
Proof. reflexivity. Qed.

Lemma literal_table_slice_end :
  fixture_table_base + 8 * length literal_table_rows = 1576.
Proof.
  rewrite literal_table_slice_eq_fixture.
  vm_compute. reflexivity.
Qed.

(** ** Tape image base 4096 and the surrounding regions *)

Lemma literal_tape_base_word : literal_word_at 4096 = 0x7FF800000002F87F%N.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_tape_base_payload :
  payload_word (literal_word_at fixture_tape_base) = 2.
Proof. vm_compute. reflexivity. Qed.

(** Boolean image checks.  These avoid building multi-thousand-element
    [Forall] proof terms for the [.org] padding and tape prefix. *)
Definition payload_forallb (want : nat) (ws : list N) : bool :=
  forallb (fun w => Nat.eqb (payload_word w) want) ws.

Lemma forallb_forall_in :
  forall (A : Type) (P : A -> bool) (l : list A),
    forallb P l = true ->
    forall x, In x l -> P x = true.
Proof.
  intros A P l. induction l as [|a l IH]; simpl; intros H x Hin.
  - destruct Hin.
  - apply andb_true_iff in H. destruct H as [Ha Hl].
    destruct Hin as [->|Hin].
    + exact Ha.
    + apply IH; assumption.
Qed.

Lemma payload_forallb_true :
  forall want ws,
    payload_forallb want ws = true ->
    Forall (fun w => payload_word w = want) ws.
Proof.
  intros want ws. induction ws as [|w ws IH]; simpl; intros H.
  - constructor.
  - apply andb_true_iff in H. destruct H as [Hw Hws].
    constructor.
    + apply Nat.eqb_eq. exact Hw.
    + apply IH. exact Hws.
Qed.

(** The 128 words at 4096..4223 are all payload 2, matching the fixture's
    [.org 4096] tape prefix. *)
Lemma literal_tape_prefix_check :
  forallb (fun i =>
             Nat.eqb (payload_word (literal_word_at (fixture_tape_base + i))) 2)
          (seq 0 128) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_tape_prefix_all_two :
  payload_forallb 2 (map literal_word_at (seq fixture_tape_base 128)) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_tape_prefix_payload :
  forall i, i < 128 ->
    payload_word (literal_word_at (fixture_tape_base + i)) = 2.
Proof.
  intros i Hi.
  apply Nat.eqb_eq.
  apply (forallb_forall_in nat
           (fun i => Nat.eqb (payload_word (literal_word_at (fixture_tape_base + i))) 2)
           (seq 0 128)).
  - exact literal_tape_prefix_check.
  - apply in_seq. lia.
Qed.

(** The [.org 4096] padding at 1649..4095 is all payload 0. *)
Lemma literal_org_padding_check :
  forallb (fun i => Nat.eqb (payload_word (literal_word_at (1649 + i))) 0)
          (seq 0 2447) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_org_padding_all_zero :
  payload_forallb 0 (map literal_word_at (seq 1649 2447)) = true.
Proof. vm_compute. reflexivity. Qed.

Lemma literal_org_padding_payload :
  forall i, i < 2447 ->
    payload_word (literal_word_at (1649 + i)) = 0.
Proof.
  intros i Hi.
  apply Nat.eqb_eq.
  apply (forallb_forall_in nat
           (fun i => Nat.eqb (payload_word (literal_word_at (1649 + i))) 0)
           (seq 0 2447)).
  - exact literal_org_padding_check.
  - apply in_seq. lia.
Qed.

(** The last padding word and first tape word pin the [.org 4096]
    boundary from both sides. *)
Lemma literal_org_boundary :
  payload_word (literal_word_at 4095) = 0 /\
  payload_word (literal_word_at 4096) = 2.
Proof. vm_compute. split; reflexivity. Qed.

(** ** ISA-OBL-2 headline theorem *)

Theorem literal_image_matches_fixture :
  length literal_image = 4366 /\
  (decode_range 0 29 = Some slice_main) /\
  (decode_range 29 36 = Some slice_run100) /\
  (decode_range 36 47 = Some slice_step_prelude) /\
  (decode_range 47 67 = Some slice_scan) /\
  (decode_range 67 78 = Some slice_action) /\
  (decode_range 78 79 = Some slice_step_ret) /\
  (decode_range 79 81 = Some slice_next) /\
  (decode_range 81 84 = Some slice_no_trans) /\
  (decode_range 96 99 = Some slice_fail) /\
  (payload_word (literal_word_at tape_base_addr) = fixture_tape_base) /\
  (payload_word (literal_word_at action_state_addr) = 0) /\
  (payload_word (literal_word_at action_head_addr) = 0) /\
  (payload_word (literal_word_at action_halt_addr) = 0) /\
  (payload_word (literal_word_at 103) = 0) /\
  (literal_table_rows = fixture_table) /\
  (forall i, i < 128 ->
     payload_word (literal_word_at (fixture_tape_base + i)) = 2) /\
  (forall i, i < 2447 ->
     payload_word (literal_word_at (1649 + i)) = 0).
Proof.
  split; [apply literal_image_4366|].
  split; [apply decode_slice_main|].
  split; [apply decode_slice_run100|].
  split; [apply decode_slice_step_prelude|].
  split; [apply decode_slice_scan|].
  split; [apply decode_slice_action|].
  split; [apply decode_slice_step_ret|].
  split; [apply decode_slice_next|].
  split; [apply decode_slice_no_trans|].
  split; [apply decode_slice_fail|].
  split; [apply literal_tbase_cell|].
  split; [apply literal_state_cell|].
  split; [apply literal_head_cell|].
  split; [apply literal_halt_cell|].
  split; [apply literal_rlink_cell|].
  split; [apply literal_table_slice_eq_fixture|].
  split; [apply literal_tape_prefix_payload|].
  apply literal_org_padding_payload.
Qed.

(** ** Assumption audit *)

Print Assumptions literal_image_matches_fixture.
Print Assumptions decode_supported_code.
Print Assumptions literal_table_slice_eq_fixture.
