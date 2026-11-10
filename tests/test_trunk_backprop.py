from __future__ import annotations

import unittest

from experiments.native_trunk_backprop import run


class TrunkBackpropTests(unittest.TestCase):
    def test_autograd_reduces_loss_and_matches_finite_difference(self):
        result = run(steps=30, batch=16, tokens=8, dim=8, hidden=16,
                     vocab=8, seed=3)
        self.assertLess(result["last_loss"], result["first_loss"])
        self.assertLess(result["gradient_check_abs_error"], 5e-3)


if __name__ == "__main__":
    unittest.main()
