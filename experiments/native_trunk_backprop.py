"""Proper autograd reference for the wide causal trunk.

This is the differentiable upper-bound/control, not the native runtime.  It
matches mth_trunk_wide.nas: learned QKV, causal softmax over the context,
residual Wout, and a tanh MLP.  It exists to gradient-check and to quantify what
local raw credit must approximate.
"""
from __future__ import annotations

import argparse
import json
import math

import torch
from torch import nn
from torch.nn import functional as F


class WideTrunk(nn.Module):
    def __init__(self, dim: int = 16, hidden: int = 64, vocab: int = 16):
        super().__init__()
        self.dim = dim
        self.hidden = hidden
        self.wq = nn.Parameter(torch.randn(dim, dim) * 0.02)
        self.wk = nn.Parameter(torch.randn(dim, dim) * 0.02)
        self.wv = nn.Parameter(torch.randn(dim, dim) * 0.02)
        self.wout = nn.Parameter(torch.randn(dim, dim) * 0.02)
        self.w1 = nn.Parameter(torch.randn(hidden, dim) * 0.02)
        self.w2 = nn.Parameter(torch.randn(dim, hidden) * 0.02)
        self.readout = nn.Parameter(torch.randn(vocab, dim) * 0.02)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [B, T, D], causal context ending at the last token.
        q = x[:, -1] @ self.wq.T
        k = x @ self.wk.T
        v = x @ self.wv.T
        scores = torch.einsum("bd,btd->bt", q, k) / math.sqrt(self.dim)
        alpha = torch.softmax(scores, dim=-1)
        context = torch.einsum("bt,btd->bd", alpha, v)
        h = x[:, -1] + context @ self.wout.T
        hidden = torch.tanh(h @ self.w1.T)
        out = h + hidden @ self.w2.T
        return out @ self.readout.T


def make_batch(batch: int, tokens: int, dim: int, vocab: int,
               generator: torch.Generator):
    # Random dense token vectors; the final token determines the class.
    x = torch.randn(batch, tokens, dim, generator=generator)
    target = (x[:, -1].argmax(dim=-1) % vocab).long()
    return x, target


def gradient_check(model: WideTrunk, x: torch.Tensor, y: torch.Tensor) -> float:
    model.zero_grad(set_to_none=True)
    loss = F.cross_entropy(model(x), y)
    loss.backward()
    index = (3, 5)
    analytic = float(model.wq.grad[index])
    original = float(model.wq[index].detach())
    eps = 1e-4
    with torch.no_grad():
        model.wq[index] = original + eps
        plus = float(F.cross_entropy(model(x), y))
        model.wq[index] = original - eps
        minus = float(F.cross_entropy(model(x), y))
        model.wq[index] = original
    numeric = (plus - minus) / (2.0 * eps)
    return abs(analytic - numeric)


def run(steps: int = 100, batch: int = 32, tokens: int = 16,
        dim: int = 16, hidden: int = 64, vocab: int = 16,
        seed: int = 0, lr: float = 3e-3) -> dict:
    torch.manual_seed(seed)
    generator = torch.Generator().manual_seed(seed + 1)
    model = WideTrunk(dim, hidden, vocab)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    losses = []
    for _ in range(steps):
        x, y = make_batch(batch, tokens, dim, vocab, generator)
        opt.zero_grad(set_to_none=True)
        loss = F.cross_entropy(model(x), y)
        loss.backward()
        opt.step()
        losses.append(float(loss.detach()))
    x, y = make_batch(batch, tokens, dim, vocab, generator)
    grad_error = gradient_check(model, x, y)
    with torch.no_grad():
        accuracy = float((model(x).argmax(dim=-1) == y).float().mean())
    return {
        "schema": "nanlm.trunk-backprop/1",
        "steps": steps,
        "dim": dim,
        "hidden": hidden,
        "tokens": tokens,
        "first_loss": losses[0],
        "last_loss": losses[-1],
        "loss_ratio": losses[-1] / max(losses[0], 1e-9),
        "batch_accuracy": accuracy,
        "gradient_check_abs_error": grad_error,
        "parameters": sum(p.numel() for p in model.parameters()),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=100)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--tokens", type=int, default=16)
    ap.add_argument("--dim", type=int, default=16)
    ap.add_argument("--hidden", type=int, default=64)
    ap.add_argument("--vocab", type=int, default=16)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    print(json.dumps(run(steps=args.steps, batch=args.batch,
                         tokens=args.tokens, dim=args.dim,
                         hidden=args.hidden, vocab=args.vocab,
                         seed=args.seed), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
