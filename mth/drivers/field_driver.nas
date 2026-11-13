; Full raw NaN16 driver: base command surface + paged native head block.
;
; The base image is kept separate so fixtures that append test code after the
; driver can include field_driver_base.nas without crossing the 0x4000 command
; block.  Opcode122 uses the low CALLF trampoline in the base handler and the
; head block is placed at 0x3E60 by mth_head_block.nas.
.include "field_driver_base.nas"
.include "../nan16/mth_head_block.nas"
.include "../nan16/mth_context_top5.nas"
