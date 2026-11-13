; Fixed high-memory trampolines for the field-driver projection layer.
; All kernels live in the same guest image as the byte/context routes.
.org 0x6000
mth_unified_word_build:
  JMP @mth_word_build
mth_unified_word_batch:
  JMP @mth_word_batch
mth_unified_word_top5:
  JMP @mth_word_top5

.include "mth_word_projection.nas"

.org 0x7000
mth_unified_token_build:
  JMP @mth_token_build
mth_unified_token_top5:
  JMP @mth_token_top5

.include "mth_token_projection.nas"
