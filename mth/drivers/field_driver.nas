; Full raw NaN16 driver: base command surface + paged native head block.
;
; The base image is kept separate so fixtures that append test code after the
; driver can include field_driver_base.nas without crossing the 0x4000 command
; block.  Opcode122 uses the high CALLF trampoline in the base handler and the
; head block is placed at 0x8020 by mth_head_block.nas. The byte/word/token
; projection routes occupy 0x4200, 0x5000, 0x6000 and 0x7000.
.include "field_driver_base.nas"
.include "../nan16/mth_context_top5.nas"
.include "../nan16/mth_context_direct256.nas"
.include "../nan16/unified_projection_entries.nas"
.include "../nan16/mth_head_block.nas"
