"""Reference tests for the shared deep trunk + sparse 255-adapter field."""
from __future__ import annotations

import unittest

import torch

from experiments.sparse_shared.model import (
    SparseConfig, SparseSharedModel, parameter_budget)
from experiments.sparse_shared.train import run


class SparseSharedTests(unittest.TestCase):
    def setUp(self):
        self.cfg = SparseConfig(d_model=32, layers=2, mlp=64, context=8)
        torch.manual_seed(7)
        self.model = SparseSharedModel(self.cfg)

    def test_budget_has_one_shared_trunk_and_255_adapters(self):
        budget = parameter_budget(self.cfg)
        self.assertGreater(budget["trunk"], 0)
        self.assertGreater(budget["adapters"], 0)
        self.assertLess(budget["active_adapter_fraction"], 0.05)

    def test_sparse_topk_is_unique_and_only_active_adapters_get_grad(self):
        ids = torch.randint(0, 256, (1, 8))
        logits, aux = self.model(ids, active=4)
        self.assertEqual(logits.shape, (1, 8, 256))
        selected = aux["indices"]
        for row in selected.reshape(-1, 4):
            self.assertEqual(len(set(row.tolist())), 4)
        self.model.zero_grad(set_to_none=True)
        self.model.loss(ids, active=4)[0].backward()
        down = self.model.adapters.down.grad.reshape(self.cfg.heads, -1)
        active = set(selected.reshape(-1).tolist())
        for head in range(self.cfg.heads):
            if head not in active:
                self.assertEqual(float(down[head].abs().sum()), 0.0)

    def test_hotspot_promotes_a_triad(self):
        grad = torch.zeros(self.cfg.heads)
        grad[6:9] = 10.0
        self.model.adapters.update_hotspots(grad, decay=0.0, threshold=1.0)
        self.assertTrue(bool((self.model.adapters.hotspot[6:9] > 0).all()))
        self.assertEqual(float(self.model.adapters.hotspot[:6].abs().sum()), 0.0)

    def test_modern_hopfield_retrieves_the_nearest_pattern(self):
        cfg = SparseConfig(d_model=8, n_heads=1, layers=1, mlp=16,
                           context=4, memory_slots=4, memory_active=1,
                           memory_beta=100.0)
        model = SparseSharedModel(cfg)
        patterns = torch.randn(4, 8)
        with torch.no_grad():
            model.memory.patterns.copy_(patterns)
            model.memory.q_proj.weight.copy_(torch.eye(8))
            model.memory.q_proj.bias.zero_()
        retrieved, aux = model.memory.retrieve(
            patterns[2].reshape(1, 1, 8), active=1)
        self.assertTrue(torch.allclose(retrieved[0, 0], patterns[2], atol=1e-5))
        self.assertEqual(int(aux["indices"][0, 0, 0]), 2)

    def test_memory_topk_only_selected_patterns_get_grad(self):
        cfg = SparseConfig(d_model=32, layers=2, mlp=64, context=8,
                           memory_slots=32, memory_active=4)
        model = SparseSharedModel(cfg)
        ids = torch.randint(0, 256, (1, 8))
        loss, aux = model.loss(ids, active=4, memory_active=4)
        model.zero_grad(set_to_none=True)
        loss.backward()
        selected = set(aux["memory"]["indices"].reshape(-1).tolist())
        grad = model.memory.patterns.grad
        for slot in range(cfg.memory_slots):
            if slot not in selected:
                self.assertEqual(float(grad[slot].abs().sum()), 0.0)

    def test_memory_changes_the_residual_output(self):
        cfg = SparseConfig(d_model=8, n_heads=1, layers=1, mlp=16,
                           context=4, memory_slots=4, memory_active=2)
        model = SparseSharedModel(cfg)
        with torch.no_grad():
            model.memory.out_proj.weight.copy_(torch.eye(8))
            model.memory.out_proj.bias.zero_()
            model.memory.gate.weight.zero_()
            model.memory.gate.bias.fill_(20.0)
        x = torch.randn(1, 2, 8)
        with torch.no_grad():
            out, aux = model.memory(x, active=2)
        self.assertFalse(torch.allclose(out, x))
        self.assertEqual(tuple(aux["indices"].shape), (1, 2, 2))

    def test_memory_budget_is_reported(self):
        cfg = SparseConfig(memory_slots=32, memory_active=4)
        budget = parameter_budget(cfg)
        self.assertGreater(budget["memory"], 0)
        self.assertLess(budget["active_memory_fraction"], 0.2)

    def test_sparse_training_reduces_fixed_batch_loss(self):
        result = run(steps=5, seq=8, batch=1, cfg=self.cfg, active=4,
                     same_batch=True)
        self.assertLess(result["last_loss"], result["first_loss"])
        self.assertLess(result["parameters"]["active_adapter_fraction"], 0.05)


if __name__ == "__main__":
    unittest.main()
