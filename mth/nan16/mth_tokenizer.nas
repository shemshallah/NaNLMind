; Raw NaN16 subword and meta tokenizer.
;
; The host stages ASCII/UTF-8 bytes; all word splitting, lowercasing, subword
; hashing, word hashing, and three-word context construction run in the guest.
;
; ABI for mth_tokenize:
;   r1 = text bytes (one byte per guest word)
;   r2 = byte length
;   r3 = word output (32-bit word IDs)
;   r4 = subword output (32-bit subword IDs)
;   r5 = meta output (four words per word: word_id, context_id, triad, vote)
;   r6 = maximum words
; Returns:
;   r1 = word count, r2 = subword count
;
; The subword vocabulary is deterministic byte-trigram hashing with a word
; boundary seed. It is a real subword stream, not a character stream, and the
; host never sees a word string.

; FNV-1a hash of one word: r1=text, r2=start, r3=len -> r1=hash.
mth_tok_hash_word:
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r6,0
mth_tok_hw_loop:
  CMP r6,r3
  JMP[GE] @mth_tok_hw_done
  MOVI r7,0
  ADD r7,r2,r6
  ADD r7,r1,r7
  LD r5,r7,0
  ; lowercase ASCII A-Z
  MOVI r8,65
  CMP r5,r8
  JMP[LT] @mth_tok_hw_lower_done
  MOVI r8,90
  CMP r5,r8
  JMP[GT] @mth_tok_hw_lower_done
  ADDI r5,r5,32
mth_tok_hw_lower_done:
  BOOL.6 r4,r4,r5
  MOVI r8,0x0193
  MOVHI r8,0x0100
  MUL r4,r4,r8
  ADDI r6,r6,1
  JMP @mth_tok_hw_loop
mth_tok_hw_done:
  ADD r1,r4,r0
  RET

; FNV-1a hash of one subword chunk: r1=text, r2=start, r3=len(<=3),
; r4=chunk index -> r1=hash.
mth_tok_hash_sub:
  MOVI r5,0x9DC5
  MOVHI r5,0x811C
  MOVI r7,1
  ADD r7,r4,r7
  BOOL.6 r5,r5,r7
  MOVI r7,0x0193
  MOVHI r7,0x0100
  MUL r5,r5,r7
  MOVI r6,0
mth_tok_hs_loop:
  CMP r6,r3
  JMP[GE] @mth_tok_hs_done
  MOVI r7,0
  ADD r7,r2,r6
  ADD r7,r1,r7
  LD r8,r7,0
  ; lowercase ASCII A-Z
  MOVI r9,65
  CMP r8,r9
  JMP[LT] @mth_tok_hs_lower_done
  MOVI r9,90
  CMP r8,r9
  JMP[GT] @mth_tok_hs_lower_done
  ADDI r8,r8,32
mth_tok_hs_lower_done:
  BOOL.6 r5,r5,r8
  MOVI r9,0x0193
  MOVHI r9,0x0100
  MUL r5,r5,r9
  ADDI r6,r6,1
  JMP @mth_tok_hs_loop
mth_tok_hs_done:
  ADD r1,r5,r0
  RET

; Hash three word IDs: r1=w0,r2=w1,r3=w2 -> r1=context hash.
mth_tok_hash3:
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r5,0x0193
  MOVHI r5,0x0100
  BOOL.6 r4,r4,r1
  MUL r4,r4,r5
  BOOL.6 r4,r4,r2
  MUL r4,r4,r5
  BOOL.6 r4,r4,r3
  MUL r4,r4,r5
  ADD r1,r4,r0
  RET

; is_word_char: r1=byte -> r1=1/0.
mth_tok_is_word:
  MOVI r2,39
  CMP r1,r2
  JMP[EQ] @mth_tok_iw_yes
  MOVI r2,45
  CMP r1,r2
  JMP[EQ] @mth_tok_iw_yes
  MOVI r2,48
  CMP r1,r2
  JMP[LT] @mth_tok_iw_no
  MOVI r2,57
  CMP r1,r2
  JMP[LE] @mth_tok_iw_yes
  MOVI r2,65
  CMP r1,r2
  JMP[LT] @mth_tok_iw_nonascii
  MOVI r2,90
  CMP r1,r2
  JMP[LE] @mth_tok_iw_yes
  MOVI r2,97
  CMP r1,r2
  JMP[LT] @mth_tok_iw_nonascii
  MOVI r2,122
  CMP r1,r2
  JMP[LE] @mth_tok_iw_yes
mth_tok_iw_nonascii:
  MOVI r2,128
  CMP r1,r2
  JMP[GE] @mth_tok_iw_yes
mth_tok_iw_no:
  MOVI r1,0
  RET
mth_tok_iw_yes:
  MOVI r1,1
  RET

; Finalize the word at start/length in the data block.
mth_tok_finalize:
  MOVI r12,@mth_tok_finlink
  ST r15,r12,0
  MOVI r12,@mth_tok_r10
  ST r10,r12,0
  MOVI r12,@mth_tok_r11
  ST r11,r12,0
  ; word hash
  MOVI r12,@mth_tok_text
  LD r1,r12,0
  MOVI r12,@mth_tok_start
  LD r2,r12,0
  MOVI r12,@mth_tok_wlen
  LD r3,r12,0
  CALL @mth_tok_hash_word
  MOVI r12,@mth_tok_word_id
  ST r1,r12,0
  ; emit word if capacity remains
  MOVI r12,@mth_tok_words
  LD r6,r12,0
  MOVI r12,@mth_tok_wcount
  LD r5,r12,0
  MOVI r12,@mth_tok_max_words
  LD r7,r12,0
  CMP r5,r7
  JMP[GE] @mth_tok_emit_subwords
  ADD r8,r6,r5
  MOVI r12,@mth_tok_word_id
  LD r7,r12,0
  ST r7,r8,0
  ; meta record
  MOVI r12,@mth_tok_meta
  LD r8,r12,0
  MOVI r12,4
  MUL r9,r5,r12
  ADD r8,r8,r9
  ST r7,r8,0
  ; three-word context = the three preceding words (excluding current)
  MOVI r12,@mth_tok_prev3
  LD r1,r12,0
  MOVI r12,@mth_tok_prev2
  LD r2,r12,0
  MOVI r12,@mth_tok_prev1
  LD r3,r12,0
  CALL @mth_tok_hash3
  ST r1,r8,1
  ; triad = hash % 85
  MOVI r9,85
  MODU r7,r1,r9
  ST r7,r8,2
  MOVI r7,7
  ST r7,r8,3
  ; advance previous IDs: prev3=old prev2; prev2=old prev1; prev1=current
  MOVI r12,@mth_tok_prev2
  LD r2,r12,0
  MOVI r12,@mth_tok_prev3
  ST r2,r12,0
  MOVI r12,@mth_tok_prev1
  LD r2,r12,0
  MOVI r12,@mth_tok_prev2
  ST r2,r12,0
  MOVI r12,@mth_tok_word_id
  LD r1,r12,0
  MOVI r12,@mth_tok_prev1
  ST r1,r12,0
  MOVI r12,@mth_tok_wcount
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
mth_tok_emit_subwords:
  ; Two-piece word encoding: a prefix piece and a suffix piece, each hashed
  ; with the subword chunk marker. This keeps the subword stream bounded and
  ; avoids a per-character loop in the first tokenizer layer.
  MOVI r12,@mth_tok_wlen
  LD r6,r12,0
  MOVI r8,3
  CMP r6,r8
  JMP[LE] @mth_tok_prefix_len_done
  ADD r6,r8,r0
mth_tok_prefix_len_done:
  MOVI r12,@mth_tok_text
  LD r1,r12,0
  MOVI r12,@mth_tok_start
  LD r2,r12,0
  ADD r3,r6,r0
  MOVI r4,0
  CALL @mth_tok_hash_sub
  MOVI r12,@mth_tok_subwords
  LD r7,r12,0
  MOVI r12,@mth_tok_scount
  LD r6,r12,0
  ADD r7,r7,r6
  ST r1,r7,0
  ADDI r6,r6,1
  MOVI r12,@mth_tok_scount
  ST r6,r12,0

  ; suffix piece: last min(3,len) bytes
  MOVI r12,@mth_tok_wlen
  LD r6,r12,0
  MOVI r8,3
  CMP r6,r8
  JMP[LE] @mth_tok_suffix_len_done
  ADD r6,r8,r0
mth_tok_suffix_len_done:
  MOVI r12,@mth_tok_start
  LD r9,r12,0
  MOVI r12,@mth_tok_wlen
  LD r8,r12,0
  ADD r9,r9,r8
  SUB r9,r9,r6
  MOVI r12,@mth_tok_text
  LD r1,r12,0
  ADD r2,r9,r0
  ADD r3,r6,r0
  MOVI r4,1
  CALL @mth_tok_hash_sub
  MOVI r12,@mth_tok_subwords
  LD r7,r12,0
  MOVI r12,@mth_tok_scount
  LD r6,r12,0
  ADD r7,r7,r6
  ST r1,r7,0
  ADDI r6,r6,1
  MOVI r12,@mth_tok_scount
  ST r6,r12,0

mth_tok_final_done:
  MOVI r12,@mth_tok_r10
  LD r10,r12,0
  MOVI r12,@mth_tok_r11
  LD r11,r12,0
  MOVI r12,@mth_tok_finlink
  LD r15,r12,0
  RET

; Main tokenizer.
mth_tokenize:
  MOVI r12,@mth_tok_r10
  ST r10,r12,0
  MOVI r12,@mth_tok_r11
  ST r11,r12,0
  MOVI r12,@mth_tok_r12
  ST r12,r12,0
  MOVI r12,@mth_tok_r13
  ST r13,r12,0
  MOVI r12,@mth_tok_r14
  ST r14,r12,0
  MOVI r12,@mth_tok_r15
  ST r15,r12,0
  MOVI r12,@mth_tok_text
  ST r1,r12,0
  MOVI r12,@mth_tok_len
  ST r2,r12,0
  MOVI r12,@mth_tok_words
  ST r3,r12,0
  MOVI r12,@mth_tok_subwords
  ST r4,r12,0
  MOVI r12,@mth_tok_meta
  ST r5,r12,0
  MOVI r12,@mth_tok_max_words
  ST r6,r12,0
  MOVI r12,@mth_tok_pos
  ST r0,r12,0
  MOVI r12,@mth_tok_inword
  ST r0,r12,0
  MOVI r12,@mth_tok_wcount
  ST r0,r12,0
  MOVI r12,@mth_tok_scount
  ST r0,r12,0
  MOVI r12,@mth_tok_prev1
  ST r0,r12,0
  MOVI r12,@mth_tok_prev2
  ST r0,r12,0
  MOVI r12,@mth_tok_prev3
  ST r0,r12,0
mth_tok_scan:
  MOVI r12,@mth_tok_pos
  LD r5,r12,0
  MOVI r12,@mth_tok_len
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_tok_scan_done
  MOVI r12,@mth_tok_text
  LD r7,r12,0
  ADD r7,r7,r5
  LD r1,r7,0
  CALL @mth_tok_is_word
  CMP r1,r0
  JMP[EQ] @mth_tok_sep
  MOVI r12,@mth_tok_inword
  LD r1,r12,0
  CMP r1,r0
  JMP[NE] @mth_tok_next
  MOVI r12,@mth_tok_start
  ST r5,r12,0
  MOVI r12,@mth_tok_inword
  MOVI r1,1
  ST r1,r12,0
  JMP @mth_tok_next
mth_tok_sep:
  MOVI r12,@mth_tok_inword
  LD r1,r12,0
  CMP r1,r0
  JMP[EQ] @mth_tok_next
  MOVI r12,@mth_tok_start
  LD r1,r12,0
  SUB r1,r5,r1
  MOVI r12,@mth_tok_wlen
  ST r1,r12,0
  CALL @mth_tok_finalize
  MOVI r12,@mth_tok_inword
  ST r0,r12,0
mth_tok_next:
  MOVI r12,@mth_tok_pos
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_tok_scan
mth_tok_scan_done:
  MOVI r12,@mth_tok_inword
  LD r1,r12,0
  CMP r1,r0
  JMP[EQ] @mth_tok_return
  MOVI r12,@mth_tok_start
  LD r1,r12,0
  MOVI r12,@mth_tok_len
  LD r5,r12,0
  SUB r1,r5,r1
  MOVI r12,@mth_tok_wlen
  ST r1,r12,0
  CALL @mth_tok_finalize
mth_tok_return:
  MOVI r12,@mth_tok_wcount
  LD r1,r12,0
  MOVI r12,@mth_tok_scount
  LD r2,r12,0
  MOVI r12,@mth_tok_r10
  LD r10,r12,0
  MOVI r12,@mth_tok_r11
  LD r11,r12,0
  MOVI r12,@mth_tok_r12
  LD r12,r12,0
  MOVI r12,@mth_tok_r13
  LD r13,r12,0
  MOVI r12,@mth_tok_r14
  LD r14,r12,0
  MOVI r12,@mth_tok_r15
  LD r15,r12,0
  RET

mth_tok_r10:
  .word 0
mth_tok_r11:
  .word 0
mth_tok_r12:
  .word 0
mth_tok_r13:
  .word 0
mth_tok_r14:
  .word 0
mth_tok_r15:
  .word 0
mth_tok_finlink:
  .word 0
mth_tok_text:
  .word 0
mth_tok_len:
  .word 0
mth_tok_words:
  .word 0
mth_tok_subwords:
  .word 0
mth_tok_meta:
  .word 0
mth_tok_max_words:
  .word 0
mth_tok_pos:
  .word 0
mth_tok_inword:
  .word 0
mth_tok_start:
  .word 0
mth_tok_wlen:
  .word 0
mth_tok_wcount:
  .word 0
mth_tok_scount:
  .word 0
mth_tok_chunk:
  .word 0
mth_tok_offset:
  .word 0
mth_tok_prev1:
  .word 0
mth_tok_prev2:
  .word 0
mth_tok_prev3:
  .word 0
mth_tok_word_id:
  .word 0
