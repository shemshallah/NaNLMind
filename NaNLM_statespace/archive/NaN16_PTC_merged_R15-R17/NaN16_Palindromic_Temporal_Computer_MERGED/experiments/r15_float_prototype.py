"""
R15 harness: does a pool of 256 identical heads self-specialize?

Design rules (from the critique of the R14 write-up):
  * Heads start identical. Symmetry must be broken by an explicit mechanism,
    and the mechanism IS the hypothesis. We test several.
  * Heads are exchangeable, so run-to-run comparison cannot use head index.
    We compare (a) mutual information I(task; winning head) and
    (b) Hungarian-matched profile similarity between independent runs.
  * Controls: shuffled-label MI (null), random fixed routing, no-learning.
  * Task order is shuffled between runs.

Each "task type" emits input vectors from a distinct cluster in feature space
(6 types, mirroring the R15 proposal: semantic inference, exception resolution,
pattern recognition, prediction, contradiction detection, counterfactual).
"""
import numpy as np
from scipy.optimize import linear_sum_assignment

N_HEADS, DIM, N_TASKS = 256, 32, 6
STEPS, BATCH = 6000, 1


def make_tasks(rng, noise=0.6, overlap=0.0):
    """Task t draws x = proto_t + noise. 'overlap' blends prototypes to make it hard."""
    P = rng.normal(size=(N_TASKS, DIM))
    P /= np.linalg.norm(P, axis=1, keepdims=True)
    if overlap > 0:
        P = (1 - overlap) * P + overlap * P.mean(0, keepdims=True)
        P /= np.linalg.norm(P, axis=1, keepdims=True)
    def sample(t):
        x = P[t] + noise * rng.normal(size=DIM) / np.sqrt(DIM)
        return x / np.linalg.norm(x)
    return sample


class HeadPool:
    """256 heads, each a unit weight vector. Identical init (all equal)."""
    def __init__(self, mode, rng, lr=0.05, eps=1e-3):
        self.mode, self.rng, self.lr = mode, rng, lr
        base = rng.normal(size=DIM); base /= np.linalg.norm(base)
        self.W = np.tile(base, (N_HEADS, 1))           # IDENTICAL initial conditions
        self.W += eps * rng.normal(size=self.W.shape) if mode == "noise" else 0
        self.W /= np.linalg.norm(self.W, axis=1, keepdims=True)
        self.load = np.zeros(N_HEADS)                   # for conscience/inhibition
        self.fixed_route = rng.integers(0, N_HEADS, size=4096) if mode == "random_fixed" else None

    def step(self, x, t_idx):
        s = self.W @ x
        if self.mode == "identical_noinhib":
            # Pure Hebbian on argmax with deterministic tie-break: heads stay identical,
            # one head (index 0) wins everything. Expected: NO specialization.
            w = int(np.argmax(s))
        elif self.mode == "noise":
            # tiny init noise only, winner-take-all
            w = int(np.argmax(s))
        elif self.mode == "inhibition":
            # symmetry broken by dynamics: heads that have won a lot get penalized
            # (conscience / lateral inhibition). Init identical; ties broken by load.
            w = int(np.argmax(s - 0.5 * self.load / (1 + self.load.sum() / N_HEADS)
                              + 1e-9 * self.rng.random(N_HEADS)))
        elif self.mode == "random_fixed":
            w = int(self.fixed_route[t_idx % len(self.fixed_route)])   # control: routing ignores input
        elif self.mode == "frozen":
            w = int(np.argmax(s + 1e-9 * self.rng.random(N_HEADS)))   # control: no learning
            self.load[w] += 1
            return w
        else:
            raise ValueError(self.mode)
        if self.mode != "random_fixed":
            self.W[w] += self.lr * (x - self.W[w])
            self.W[w] /= np.linalg.norm(self.W[w])
        self.load[w] += 1
        return w


def run(mode, seed, task_order_seed, noise=0.6, overlap=0.0):
    rng = np.random.default_rng(seed)
    sample = make_tasks(np.random.default_rng(12345), noise, overlap)   # same task world across runs
    pool = HeadPool(mode, rng)
    order = np.random.default_rng(task_order_seed).integers(0, N_TASKS, size=STEPS)
    counts = np.zeros((N_HEADS, N_TASKS))
    for i, t in enumerate(order):
        w = pool.step(sample(t), i)
        if i >= STEPS // 2:                    # measure after burn-in
            counts[w, t] += 1
    return counts


def mutual_info(counts):
    """I(task; head) in bits from a head x task contingency table."""
    p = counts / counts.sum()
    ph, pt = p.sum(1, keepdims=True), p.sum(0, keepdims=True)
    nz = p > 0
    return float((p[nz] * np.log2(p[nz] / (ph @ pt)[nz])).sum())


def mi_null(counts, rng, n=200):
    """Shuffled-label control: permute the task label of every event."""
    tasks = np.repeat(np.tile(np.arange(N_TASKS), N_HEADS), counts.astype(int).ravel().tolist()) \
        if False else None
    # Rebuild event list then shuffle labels
    heads, labs = [], []
    for h in range(N_HEADS):
        for t in range(N_TASKS):
            c = int(counts[h, t]); heads += [h] * c; labs += [t] * c
    heads, labs = np.array(heads), np.array(labs)
    out = []
    for _ in range(n):
        c = np.zeros_like(counts)
        np.add.at(c, (heads, rng.permutation(labs)), 1)
        out.append(mutual_info(c))
    return np.array(out)


def profile(counts):
    """Row-normalized task profile of each *used* head."""
    used = counts.sum(1) > 0
    P = counts[used] / counts[used].sum(1, keepdims=True)
    return P


def cross_run_similarity(c1, c2):
    """Exchangeable-head comparison: Hungarian-match used heads by profile distance,
    return mean cosine similarity of matched profiles weighted by usage."""
    P1, P2 = profile(c1), profile(c2)
    w1, w2 = c1.sum(1)[c1.sum(1) > 0], c2.sum(1)[c2.sum(1) > 0]
    # compare task-profiles via cosine
    # center on the population-mean profile: raw cosine of near-uniform profiles is ~1 for everything
    m1, m2 = np.average(P1, axis=0, weights=w1), np.average(P2, axis=0, weights=w2)
    A, B = P1 - m1, P2 - m2
    A = A / (np.linalg.norm(A, axis=1, keepdims=True) + 1e-12)
    B = B / (np.linalg.norm(B, axis=1, keepdims=True) + 1e-12)
    S = A @ B.T
    r, c = linear_sum_assignment(-S)
    wt = np.minimum(w1[r], w2[c])
    return float((S[r, c] * wt).sum() / wt.sum())


def purity(counts):
    used = counts.sum(1) > 0
    return float((counts[used].max(1)).sum() / counts[used].sum())


if __name__ == "__main__":
    import json, sys
    modes = ["identical_noinhib", "noise", "inhibition", "random_fixed", "frozen"]
    results = {}
    for overlap in (0.0, 0.6):
        for mode in modes:
            mis, nulls, purs, nused, sims = [], [], [], [], []
            runs = []
            for k in range(6):
                c = run(mode, seed=100 + k, task_order_seed=900 + k, overlap=overlap)
                runs.append(c)
                mis.append(mutual_info(c)); purs.append(purity(c))
                nused.append(int((c.sum(1) > 0).sum()))
                nulls.append(mi_null(c, np.random.default_rng(k), n=50).mean())
            for i in range(len(runs)):
                for j in range(i + 1, len(runs)):
                    sims.append(cross_run_similarity(runs[i], runs[j]))
            results[f"{mode}|overlap={overlap}"] = dict(
                MI_bits=float(np.mean(mis)), MI_null=float(np.mean(nulls)),
                max_possible_bits=float(np.log2(N_TASKS)),
                purity=float(np.mean(purs)), heads_used=float(np.mean(nused)),
                cross_run_sim=float(np.mean(sims)))
    print(json.dumps(results, indent=1))
    json.dump(results, open("r15_results.json", "w"), indent=1)
