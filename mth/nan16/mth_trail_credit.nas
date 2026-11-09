; NaN16 TRAIL two-rail TD eligibility credit.
;
; ABI (Q16.16):
;   r1  = reward r_t
;   r2  = V-(s_{t+1})
;   r3  = V+(s_t)
;   r4  = V+(s_{t-1})
;   r5  = V-(s_t)
;   r6  = e+
;   r7  = e-
;   r8  = dV+/dtheta
;   r9  = dV-/dtheta
;   r10 = gamma
;   r11 = lambda
; Returns:
;   r1 = e+_new
;   r2 = e-_new
;   r3 = credit = delta+*e+_new - delta-*e-_new
;
; No activation tape is retained. The two traces and local TD errors live in
; the caller's rails/scratch; this kernel computes one update step.
mth_trail_credit:
  MOVI r12,@mth_trail_link
  ST r15,r12,0
  MOVI r12,@mth_trail_r
  ST r1,r12,0
  MOVI r12,@mth_trail_vm_next
  ST r2,r12,0
  MOVI r12,@mth_trail_vp
  ST r3,r12,0
  MOVI r12,@mth_trail_vp_prev
  ST r4,r12,0
  MOVI r12,@mth_trail_vm
  ST r5,r12,0
  MOVI r12,@mth_trail_ep
  ST r6,r12,0
  MOVI r12,@mth_trail_em
  ST r7,r12,0
  MOVI r12,@mth_trail_gp
  ST r8,r12,0
  MOVI r12,@mth_trail_gm
  ST r9,r12,0
  MOVI r12,@mth_trail_gamma
  ST r10,r12,0
  MOVI r12,@mth_trail_lambda
  ST r11,r12,0

  ; delta+ = r + gamma*V-(s_next) - V+(s_t)
  MOVI r12,@mth_trail_gamma
  LD r1,r12,0
  MOVI r12,@mth_trail_vm_next
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_r
  LD r5,r12,0
  ADD r1,r1,r5
  MOVI r12,@mth_trail_vp
  LD r5,r12,0
  SUB r1,r1,r5
  MOVI r12,@mth_trail_dp
  ST r1,r12,0

  ; delta- = r + gamma*V+(s_prev) - V-(s_t)
  MOVI r12,@mth_trail_gamma
  LD r1,r12,0
  MOVI r12,@mth_trail_vp_prev
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_r
  LD r5,r12,0
  ADD r1,r1,r5
  MOVI r12,@mth_trail_vm
  LD r5,r12,0
  SUB r1,r1,r5
  MOVI r12,@mth_trail_dm
  ST r1,r12,0

  ; decay = lambda*gamma
  MOVI r12,@mth_trail_lambda
  LD r1,r12,0
  MOVI r12,@mth_trail_gamma
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_decay
  ST r1,r12,0

  ; e+_new = decay*e+ + dV+/dtheta
  ADD r2,r1,r0
  MOVI r12,@mth_trail_ep
  LD r1,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_gp
  LD r5,r12,0
  ADD r1,r1,r5
  MOVI r12,@mth_trail_ep_new
  ST r1,r12,0

  ; e-_new = decay*e- + dV-/dtheta
  MOVI r12,@mth_trail_decay
  LD r2,r12,0
  MOVI r12,@mth_trail_em
  LD r1,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_gm
  LD r5,r12,0
  ADD r1,r1,r5
  MOVI r12,@mth_trail_em_new
  ST r1,r12,0

  ; credit = delta+*e+_new - delta-*e-_new
  MOVI r12,@mth_trail_dp
  LD r1,r12,0
  MOVI r12,@mth_trail_ep_new
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_credit_out
  ST r1,r12,0
  MOVI r12,@mth_trail_dm
  LD r1,r12,0
  MOVI r12,@mth_trail_em_new
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_trail_credit_out
  LD r5,r12,0
  SUB r5,r5,r1
  MOVI r12,@mth_trail_credit_out
  ST r5,r12,0

  MOVI r12,@mth_trail_ep_new
  LD r1,r12,0
  MOVI r12,@mth_trail_em_new
  LD r2,r12,0
  MOVI r12,@mth_trail_credit_out
  LD r3,r12,0
  MOVI r13,1
  MOVI r12,@mth_trail_link
  LD r15,r12,0
  RET

mth_trail_link:
  .word 0
mth_trail_r:
  .word 0
mth_trail_vm_next:
  .word 0
mth_trail_vp:
  .word 0
mth_trail_vp_prev:
  .word 0
mth_trail_vm:
  .word 0
mth_trail_ep:
  .word 0
mth_trail_em:
  .word 0
mth_trail_gp:
  .word 0
mth_trail_gm:
  .word 0
mth_trail_gamma:
  .word 0
mth_trail_lambda:
  .word 0
mth_trail_dp:
  .word 0
mth_trail_dm:
  .word 0
mth_trail_decay:
  .word 0
mth_trail_ep_new:
  .word 0
mth_trail_em_new:
  .word 0
mth_trail_credit_out:
  .word 0
