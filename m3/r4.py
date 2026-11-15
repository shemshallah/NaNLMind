#!/usr/bin/env python3
"""M3 R4: causally evaluated NaN16 byte/BPE/word/sentence-class hierarchy.

NumPy experiment only, NOT a NaN-native VM or inherited neural checkpoint.
Each level occupies a tagged channel in the same 256-head mirror geometry.
"""
from __future__ import annotations

import argparse
from collections import Counter, deque
import hashlib
import json
import math
from pathlib import Path
import re
import time
import numpy as np

LEVELS = ("byte", "bpe", "word", "sentence_class")
ARMS = ("prior", "base", "symmetric", "same", "crossed", "triangle", "plain_trigram", "wrong_book")
SAMPLES = (256, 256, 128, 16)
WORD = re.compile(rb"[A-Za-z]+(?:'[A-Za-z]+)?|[0-9]+")
SENTENCE = re.compile(rb"[^.!?]+[.!?]+", re.DOTALL)


def rev8(x):
    x = ((x & 240) >> 4) | ((x & 15) << 4)
    x = ((x & 204) >> 2) | ((x & 51) << 2)
    return ((x & 170) >> 1) | ((x & 85) << 1)


def addr(a, b):
    if not (0 <= a < 256 and 0 <= b < 256):
        raise ValueError("head index out of range")
    return (a << 8) | rev8(b)


def mirror(x):
    return (rev8(x & 255) << 8) | rev8(x >> 8)


def pair_rank(a, b):
    if a == b:
        return None
    x, y = sorted((a, b))
    return y * (y - 1) // 2 + x


def triangle_rank(a, b, c):
    if len({a, b, c}) != 3:
        return None
    x, y, z = sorted((a, b, c))
    return math.comb(z, 3) + math.comb(y, 2) + x


def head(blob):
    return hashlib.blake2b(blob, digest_size=1, person=b"NaN16R4").digest()[0]


def merge_seq(seq, pair, new_id, offsets=None):
    result = []
    mapped = [] if offsets is not None else None
    i = 0
    while i < len(seq):
        found = i+1 < len(seq) and (seq[i], seq[i+1]) == pair
        result.append(new_id if found else seq[i])
        if mapped is not None:
            mapped.append(offsets[i])
        i += 2 if found else 1
    return result, mapped


def train_bpe(raws, n=32):
    sequences = [list(raw[:12000]) for raw in raws]
    merges = []
    for i in range(n):
        counts = Counter()
        for seq in sequences:
            counts.update(zip(seq, seq[1:]))
        if not counts:
            break
        pair, freq = min(counts.items(), key=lambda item: (-item[1], item[0]))
        if freq < 2:
            break
        merges.append(pair)
        sequences = [merge_seq(seq, pair, 256+i)[0] for seq in sequences]
    return merges


def bpe_vocab(merges):
    tokens = [bytes([i]) for i in range(256)]
    for x, y in merges:
        tokens.append(tokens[x] + tokens[y])
    return tokens


def bpe_encode(raw, merges):
    ids, offsets = list(raw), list(range(len(raw)))
    for i, pair in enumerate(merges):
        ids, offsets = merge_seq(ids, pair, 256+i, offsets)
    return ids, offsets


def sent_class(blob):
    length = len(blob.strip())
    bucket = 0 if length < 40 else 1 if length < 100 else 2 if length < 200 else 3
    ending = {b".": 0, b"?": 1, b"!": 2}.get(blob.rstrip()[-1:], 3)
    return 4*bucket + ending


def events(level, raw, merges, word_ids):
    if level == 0:
        return list(raw), list(range(len(raw)))
    if level == 1:
        return bpe_encode(raw, merges)
    matches = list((WORD if level == 2 else SENTENCE).finditer(raw))
    if level == 2:
        ids = [word_ids.get(m.group().lower(), len(word_ids)) for m in matches]
    else:
        ids = [sent_class(m.group()) for m in matches]
    return ids, [m.start() for m in matches]


class Memory:
    def __init__(self, recent=128, older=2048):
        self.recent, self.older = recent, older
        self.counts = np.zeros((4, 2, 256, 256), dtype=np.int32)
        self.queues = [[deque(), deque()] for _ in LEVELS]
        self.triq = [[deque(), deque()] for _ in LEVELS]
        self.tric = [[Counter(), Counter()] for _ in LEVELS]
        self.last = [None]*4
        self.before = [None]*4

    def _append(self, level, item, q, bank, max_recent, max_older):
        q[0].append(item)
        bank[0][item] += 1
        if len(q[0]) > max_recent:
            old = q[0].popleft()
            bank[0][old] -= 1
            if isinstance(bank[0], Counter) and not bank[0][old]:
                del bank[0][old]
            q[1].append(old)
            bank[1][old] += 1
        if len(q[1]) > max_older:
            gone = q[1].popleft()
            bank[1][gone] -= 1
            if isinstance(bank[1], Counter) and not bank[1][gone]:
                del bank[1][gone]

    def observe(self, level, value):
        last, before = self.last[level], self.before[level]
        if last is not None:
            self._append(level, (last, value), self.queues[level],
                         self.counts[level], self.recent, self.older)
        if before is not None and last is not None and triangle_rank(before, last, value) is not None:
            self._append(level, (before, last, value), self.triq[level],
                         self.tric[level], self.recent, self.older)
        self.before[level], self.last[level] = last, value

    def rails(self, level, bank, a, b):
        x = int(self.counts[level, bank, a, b])
        y = int(self.counts[level, bank, b, a])
        return (x+y)/2, (x-y)/2


class Alphabet:
    def __init__(self, level, counts, labels=None):
        if level == 0:
            size = 256
            self.heads = np.arange(256, dtype=np.uint8)
        elif level == 1:
            size = len(labels)
            self.heads = np.array([head(t) for t in labels], dtype=np.uint8)
        elif level == 2:
            size = len(labels) + 1
            self.heads = np.array([head(t) for t in labels]+[head(b"<UNK>")], dtype=np.uint8)
        else:
            size = 16
            self.heads = np.array([head(bytes([i])) for i in range(16)], dtype=np.uint8)
        prior = np.array([counts.get(i, 0)+.25 for i in range(size)], dtype=np.float64)
        self.prior = prior/prior.sum()
        self.head_prior = np.bincount(self.heads, weights=self.prior, minlength=256)


def smoothed(row, prior, tau=12.):
    return (row.astype(np.float64)+tau*prior)/(float(row.sum())+tau)


def predict(memory, level, alphabet, mode, wrong=None):
    if mode == "prior" or memory.last[level] is None:
        return alphabet.prior.copy()
    comparison = wrong if mode == "wrong_book" else memory
    last = memory.last[level]  # correct-history last observation in every arm
    fresh, older = comparison.counts[level]
    if mode == "symmetric":
        base_row = (fresh[last, :]+fresh[:, last])*.5
        old_row = (older[last, :]+older[:, last])*.5
    else:
        base_row = fresh[last, :]
        old_row = older[:, last] if mode == "crossed" else older[last, :]
    base = smoothed(base_row, alphabet.head_prior)
    old = smoothed(old_row, alphabet.head_prior)
    distribution = (.1*alphabet.head_prior+.9*base) if mode == "base" else (
        .1*alphabet.head_prior+.55*base+.35*old)
    if mode in ("triangle", "plain_trigram") and memory.before[level] is not None:
        a = memory.before[level]
        tri = np.zeros(256, dtype=np.float64)
        for z in range(256):
            if triangle_rank(a, last, z) is not None:
                key = (a, last, z)
                tri[z] = memory.tric[level][0][key] + .5*memory.tric[level][1][key]
        if tri.sum():
            distribution = .85*distribution+.15*smoothed(tri, alphabet.head_prior, 3.)
    p = distribution[alphabet.heads]*alphabet.prior/np.maximum(alphabet.head_prior[alphabet.heads], 1e-15)
    return p/p.sum()


class Metrics:
    def __init__(self):
        self.n = self.bits = self.exact1 = self.exact5 = self.class1 = self.class5 = 0
        self.known = self.known_hit = self.unk = self.byte_count = 0

    def add(self, prob, label, byte_count, is_unk=False):
        top = np.argsort(prob)[-5:]
        hit1, hit5 = int(top[-1] == label), int(label in top)
        self.n += 1
        self.bits -= math.log2(max(float(prob[label]), 1e-300))
        self.class1 += hit1
        self.class5 += hit5
        self.exact1 += hit1*(not is_unk)
        self.exact5 += hit5*(not is_unk)
        self.byte_count += byte_count
        self.unk += is_unk
        self.known += not is_unk
        self.known_hit += hit1*(not is_unk)

    def output(self):
        return {"samples":self.n, "top1":round(self.exact1/self.n, 6),
                "top5":round(self.exact5/self.n, 6),
                "bits_per_unit":round(self.bits/self.n, 6),
                "perplexity_closed_class":round(2**(self.bits/self.n), 6),
                "mean_bytes_per_unit":round(self.byte_count/self.n, 6),
                "bits_per_consumed_byte":round(self.bits/self.byte_count, 6),
                "unknown_rate":round(self.unk/self.n, 6),
                "known_exact_top1":round(self.known_hit/self.known, 6) if self.known else None,
                "closed_class_top1_including_unknown":round(self.class1/self.n, 6),
                "closed_class_top5_including_unknown":round(self.class5/self.n, 6)}


def eval_book(level, raw, merges, words, target):
    anchor = len(raw)//2
    begin = max(0, anchor-35000)
    fragment = raw[begin:min(len(raw), anchor+14000)]
    ids, offsets = events(level, fragment, merges, words)
    start = next((i for i, x in enumerate(offsets) if x >= anchor-begin), len(ids))
    if len(ids)-start < target:
        return None
    first = max(0, start-2178)
    lengths = [offsets[i+1]-offsets[i] for i in range(len(offsets)-1)] + [len(fragment)-offsets[-1]]
    return ids[first:start+target], lengths[first:start+target], start-first


def evaluate(paths, alphabets, merges, word_ids):
    stats = [[Metrics() for _ in ARMS] for _ in LEVELS]
    books = {}
    for index, path in enumerate(paths):
        raw = path.read_bytes()
        wrong_raw = paths[(index+1)%len(paths)].read_bytes()
        books[path.name] = {"sha256":hashlib.sha256(raw).hexdigest()}
        for level, kind in enumerate(LEVELS):
            local = [Metrics() for _ in ARMS]
            own = eval_book(level, raw, merges, word_ids, SAMPLES[level])
            wrong = eval_book(level, wrong_raw, merges, word_ids, SAMPLES[level])
            if own is None or wrong is None:
                books[path.name][kind] = "not_enough_events"
                continue
            items, lengths, boundary = own
            others, _, other_boundary = wrong
            memory, donor = Memory(), Memory()
            alpha = alphabets[level]
            for value in items[:boundary]:
                memory.observe(level, int(alpha.heads[value]))
            for value in others[:other_boundary]:
                donor.observe(level, int(alpha.heads[value]))
            for i in range(boundary, len(items)):
                label = items[i]
                unknown = level == 2 and label == len(word_ids)
                for arm, mode in enumerate(ARMS):
                    distribution = predict(memory, level, alpha, mode, donor)
                    stats[level][arm].add(distribution, label, lengths[i], unknown)
                    local[arm].add(distribution, label, lengths[i], unknown)
                memory.observe(level, int(alpha.heads[label]))
            books[path.name][kind] = {"samples":len(items)-boundary,
                                      "modes":{arm:local[a].output() for a,arm in enumerate(ARMS)}}
    return {"metrics":{kind:{arm:stats[l][a].output() for a, arm in enumerate(ARMS) if stats[l][a].n}
                       for l, kind in enumerate(LEVELS)}, "books":books}


def run(root, bpe_merges=32, max_words=1024, exploratory_test=False):
    began = time.perf_counter()
    paths = {s:sorted((root/s).glob("*.txt")) for s in ("train", "dev", "test")}
    if [len(paths[s]) for s in paths] != [12,12,14]:
        raise ValueError("corpus inventory differs from R2")
    ids = [p.stem for files in paths.values() for p in files]
    if len(ids) != len(set(ids)):
        raise ValueError("book split is not disjoint")
    train = [p.read_bytes() for p in paths["train"]]
    merges = train_bpe(train, bpe_merges)
    word_freq = Counter(m.group().lower() for raw in train for m in WORD.finditer(raw[:50000]))
    words = [w for w, _ in sorted(word_freq.items(), key=lambda x:(-x[1],x[0]))[:max_words]]
    word_ids = {w:i for i,w in enumerate(words)}
    counts = [Counter() for _ in LEVELS]
    for raw in train:
        for l in range(4):
            seq, _ = events(l, raw[:50000], merges, word_ids)
            counts[l].update(seq)
    alphabets = [Alphabet(l, counts[l], None if l in (0,3) else bpe_vocab(merges) if l == 1 else words)
                 for l in range(4)]
    result = {"metadata":{
        "system":"M3 R4", "status":"no-pretraining exploratory diagnostic; not a promoted LM",
        "author":"Justin Howard-Stanley", "train_books":12, "dev_books":12, "test_books":14,
        "base_events":128, "older_events":2048, "samples_per_book":dict(zip(LEVELS,SAMPLES)),
        "fixed_weights":{"base":.55,"old":.35,"prior":.10,"triangle":.15},
        "test_warning":"R2 previously exposed TEST books; TEST here is NOT sealed validation",
        "word_warning":"OOV gets zero exact-word credit; closed-class loss/perplexity includes UNK",
        "plain_trigram_control":"The sparse triangle readout is an oriented n-gram count stored using a C(256,3) identity; an otherwise identical ordinary trigram readout is mathematically equivalent. No topology-specific predictive gain is established.",
        "sentence_warning":"Only 16 length/punctuation classes, NOT exact sentence prediction or sentence text compression",
        "bpbyte_warning":"Word and sentence-class bits/byte are class-coding ratios, not raw-text BPB"},
        "vocabulary":{"bpe_merges":merges,"bpe_vocab_size":256+len(merges),"word_vocab_plus_unknown":len(words)+1},
        "dev":evaluate(paths["dev"],alphabets,merges,word_ids)}
    if exploratory_test:
        result["test_previously_exposed"] = evaluate(paths["test"],alphabets,merges,word_ids)
    result["elapsed_seconds"] = round(time.perf_counter()-began,3)
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--corpus",type=Path,default=Path("nan16_resonance_corpus/books"))
    p.add_argument("--output",type=Path,default=Path("m3/results.json"))
    p.add_argument("--test-exploratory", action="store_true")
    args = p.parse_args()
    result = run(args.corpus,exploratory_test=args.test_exploratory)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({s:{l:{m:{k:v for k,v in d.items() if k in ("top1","top5","bits_per_unit","unknown_rate")}
                             for m,d in arms.items() if m in ("prior","same","crossed","triangle")}
                        for l,arms in report["metrics"].items()}
                      for s,report in result.items() if s in ("dev","test_previously_exposed")},indent=2))
    print("elapsed",result["elapsed_seconds"])


if __name__ == "__main__":
    main()
