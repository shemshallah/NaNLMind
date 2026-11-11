"""Static MC0 source regression; complements, never replaces, native VM tests."""
from pathlib import Path
import unittest

SOURCE=Path(__file__).parents[1]/"mth/nan16/mth_meta_attention16_f32.nas"
class TestMetaMasking(unittest.TestCase):
    def test_masked_score_uses_negative_sentinel(self):
        code=SOURCE.read_text()
        masked=code.split("mth_ma_masked:",1)[1].split("mth_ma_score_done:",1)[0]
        self.assertIn("ST r10,r11,0",masked)
        self.assertNotIn("ST r15,r11,0",masked)
    def test_all_invalid_rejected(self):
        code=SOURCE.read_text()
        self.assertIn("mth_ma_mask_gate:",code)
        self.assertIn("mth_ma_mask_gate_done:",code)
        gate=code.split("mth_ma_mask_gate_done:",1)[1].split("  ; scale =",1)[0]
        self.assertIn("JMP[EQ] @mth_ma_reject",gate)
if __name__=="__main__":unittest.main()
