"""Fast byte-level held-out probe for the optional Hopfield memory bank."""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import torch

from .model import SparseConfig, SparseSharedModel


def _batches(src: torch.Tensor, context: int, batch: int, steps: int,
             seed: int):
    g = torch.Generator().manual_seed(seed)
    for _ in range(steps):
        starts = torch.randint(0, len(src) - context - 1, (batch,),
                               generator=g)
        yield torch.stack([src[i:i + context + 1] for i in starts])


def run(*, corpus: str = "data/alice_excerpt.txt", memory_slots: int = 128,
        steps: int = 80, batch: int = 8, context: int = 32, d_model: int = 32,
        layers: int = 2, mlp: int = 64, seed: int = 0) -> dict:
    torch.manual_seed(seed)
    torch.set_num_threads(2)
    raw = Path(corpus).read_bytes()
    data = torch.tensor(list(raw), dtype=torch.long)
    cut = int(0.9 * len(data))
    train, val = data[:cut], data[cut:]
    cfg = SparseConfig(d_model=d_model, layers=layers, mlp=mlp,
                       context=context, memory_slots=memory_slots,
                       memory_active=min(8, memory_slots) if memory_slots else 0,
                       memory_beta=8.0)
    model = SparseSharedModel(cfg)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3)
    start = time.perf_counter()
    for ids in _batches(train, context, batch, steps, seed + 1):
        opt.zero_grad(set_to_none=True)
        loss, _ = model.loss(ids, active=8)
        loss.backward()
        opt.step()
    train_seconds = time.perf_counter() - start
    with torch.no_grad():
        losses = [float(model.loss(ids, active=8)[0])
                  for ids in _batches(val, context, 8, 10, seed + 2)]
    val_loss = sum(losses) / len(losses)
    return {
        "schema": "nanlm.hopfield-lm-probe/1",
        "corpus": corpus,
        "memory_slots": memory_slots,
        "steps": steps,
        "seed": seed,
        "train_seconds": train_seconds,
        "val_loss": val_loss,
        "val_bpc": val_loss / 2.302585092994046,
        "params": sum(p.numel() for p in model.parameters()),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="data/alice_excerpt.txt")
    ap.add_argument("--memory-slots", type=int, default=128)
    ap.add_argument("--steps", type=int, default=80)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    for slots in (0, args.memory_slots):
        print(run(corpus=args.corpus, memory_slots=slots,
                  steps=args.steps, seed=args.seed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
