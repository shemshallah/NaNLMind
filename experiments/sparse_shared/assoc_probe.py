"""Fast associative-recall probe for the optional Hopfield memory bank."""
from __future__ import annotations

import argparse
import time

import torch

from .model import SparseConfig, SparseSharedModel


def table(n: int, seed: int) -> tuple[torch.Tensor, torch.Tensor]:
    g = torch.Generator().manual_seed(seed)
    perm = torch.randperm(n, generator=g)
    keys = torch.arange(n)
    values = n + perm
    return torch.stack((keys, values), dim=1), values


def evaluate(model: SparseSharedModel, ids: torch.Tensor, values: torch.Tensor) -> float:
    with torch.no_grad():
        logits, _ = model(ids[:, :-1], active=8)
        pred = logits[:, -1].argmax(dim=-1)
    return float((pred == values).float().mean())


def run(memory_slots: int, *, keys: int = 64, steps: int = 200,
        seed: int = 0, context: int = 2, d: int = 16, layers: int = 1,
        mlp: int = 32, lr: float = 1e-3, batch: int = 64) -> dict:
    torch.manual_seed(seed)
    torch.set_num_threads(2)
    cfg = SparseConfig(d_model=d, layers=layers, mlp=mlp, vocab=2 * keys,
                       context=context, memory_slots=memory_slots,
                       memory_active=min(8, memory_slots) if memory_slots else 0,
                       memory_beta=8.0)
    ids, values = table(keys, seed)
    model = SparseSharedModel(cfg)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
    losses = []
    start = time.perf_counter()
    for step in range(steps):
        idx = torch.randint(0, keys, (batch,))
        batch_ids = ids[idx]
        opt.zero_grad(set_to_none=True)
        loss, _ = model.loss(batch_ids, active=8)
        loss.backward()
        opt.step()
        losses.append(float(loss.detach()))
    elapsed = time.perf_counter() - start
    return {
        "memory_slots": memory_slots,
        "keys": keys,
        "steps": steps,
        "first_loss": losses[0],
        "last_loss": losses[-1],
        "train_accuracy": evaluate(model, ids, values),
        "seconds": elapsed,
        "params": sum(p.numel() for p in model.parameters()),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--memory-slots", type=int, default=64)
    ap.add_argument("--keys", type=int, default=64)
    ap.add_argument("--steps", type=int, default=200)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    for slots in (0, args.memory_slots):
        print(run(slots, keys=args.keys, steps=args.steps, seed=args.seed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


def episodic_batch(batch: int, pairs: int, keys: int,
                   generator: torch.Generator) -> tuple[torch.Tensor, torch.Tensor]:
    # Each episode has its own random key->value permutation, so the model must
    # bind the pair in context; a static pattern bank cannot know the episode.
    ids = torch.empty(batch, 2 * pairs + 2, dtype=torch.long)
    answers = torch.empty(batch, dtype=torch.long)
    for b in range(batch):
        ks = torch.randperm(keys, generator=generator)[:pairs]
        vs = keys + torch.randperm(keys, generator=generator)[:pairs]
        seq = []
        for k, v in zip(ks.tolist(), vs.tolist()):
            seq.extend((k, v))
        q = int(torch.randint(pairs, (1,), generator=generator))
        seq.extend((int(ks[q]), int(vs[q])))
        ids[b] = torch.tensor(seq)
        answers[b] = int(vs[q])
    return ids, answers


def run_episodic(memory_slots: int, *, pairs: int = 4, keys: int = 16,
                 steps: int = 300, seed: int = 0, d: int = 32,
                 layers: int = 2, mlp: int = 64, lr: float = 1e-3,
                 batch: int = 32) -> dict:
    torch.manual_seed(seed)
    torch.set_num_threads(2)
    cfg = SparseConfig(d_model=d, layers=layers, mlp=mlp, vocab=2 * keys,
                       context=2 * pairs + 2, memory_slots=memory_slots,
                       memory_active=min(8, memory_slots) if memory_slots else 0,
                       memory_beta=8.0)
    model = SparseSharedModel(cfg)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
    g = torch.Generator().manual_seed(seed + 99)
    losses = []
    start = time.perf_counter()
    for step in range(steps):
        ids, answers = episodic_batch(batch, pairs, keys, g)
        opt.zero_grad(set_to_none=True)
        logits, _ = model(ids[:, :-1], active=8)
        loss = torch.nn.functional.cross_entropy(logits[:, -1], answers)
        loss.backward()
        opt.step()
        losses.append(float(loss.detach()))
    elapsed = time.perf_counter() - start
    val_ids, val_answers = episodic_batch(256, pairs, keys,
                                          torch.Generator().manual_seed(seed + 7))
    with torch.no_grad():
        logits, _ = model(val_ids[:, :-1], active=8)
        pred = logits[:, -1].argmax(dim=-1)
    return {
        "task": "episodic",
        "memory_slots": memory_slots,
        "pairs": pairs,
        "keys": keys,
        "steps": steps,
        "last_loss": losses[-1],
        "accuracy": float((pred == val_answers).float().mean()),
        "seconds": elapsed,
        "params": sum(p.numel() for p in model.parameters()),
    }
