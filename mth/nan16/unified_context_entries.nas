; High-memory 64-token context layer and state readout in one field-driver VM.
.org 0x9000
.include "mth_head_block64.nas"

.org 0xB000
.include "mth_head_block64_last.nas"

.org 0xC000
.include "mth_head_state_readout.nas"
