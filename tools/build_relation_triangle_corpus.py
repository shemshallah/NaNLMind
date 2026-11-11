#!/usr/bin/env python3
"""Build a provenance-bound inverse/relation triangle corpus from WordNet 3.1.

The output is the machine-readable ``N16TRI/1`` TSV consumed by
``nanlm-universal triangle-contrast-train``.  This tool performs host I/O and
label construction only: it parses the official WordNet data files, derives
positive, inverse, hard-negative, random-negative and self-negative rows, and
writes deterministic splits.  It does not compute embeddings, triangle
geometry, or model scores; those stay in the raw NaN16 guest.

Schema (tab separated, no header row in the machine file)::

    split relation label confidence subject_hex predicate_hex object_hex source_sha256 provenance

* ``split`` is ``train``, ``valid`` or ``test``.
* ``relation`` is one of ISA, HAS_SUBTYPE, PART_OF, HAS_PART, CONTRADICTS,
  ASSOCIATED.
* ``label`` is one of positive, inverse, hard_negative, negative,
  self_negative.  ``positive`` and ``inverse`` are valid relation rows and are
  the positive class for contrastive training.  The other three are invalid
  rows and are the negative class.
* ``confidence`` is a 0..65535 source prior, *not* a calibrated probability.
* the three ``*_hex`` fields are UTF-8 role text encoded as lowercase hex.
  The trainer phase-encodes the role text in the raw guest.  Subject/object
  role text is the first WordNet lemma; predicate role text is the canonical
  relation name.
* ``source_sha256`` is the SHA-256 of the raw WordNet data line for the row's
  subject synset.
* ``provenance`` is a tab-free audit string naming the source pointer, both
  synset IDs, gloss digests and the construction rule.

The companion readable TSV decodes the role text and synset IDs.  The manifest
records archive/file digests, label/split/relation histograms and the exact
generator options so a release can be reproduced and audited.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator, Sequence

SCHEMA = "N16TRI/1"
MANIFEST_SCHEMA = "nanlm.relation-triangle-corpus/1"
RELATIONS = (
    "ISA",
    "HAS_SUBTYPE",
    "PART_OF",
    "HAS_PART",
    "CONTRADICTS",
    "ASSOCIATED",
)
LABELS = ("positive", "inverse", "hard_negative", "negative", "self_negative")
SPLITS = ("train", "valid", "test")
POSITIVE_LABELS = {"positive", "inverse"}
NEGATIVE_LABELS = {"hard_negative", "negative", "self_negative"}

# WordNet pointer symbols that are used as canonical forward anchors.  The
# inverse symbols (~, ~i, %p, %m, %s) are deliberately not used as anchors:
# their edges are emitted by the inverse pass, which gives every relation both
# positive and negative rows without double-counting the same WordNet edge.
POINTER_RELATION = {
    "@": "ISA",
    "@i": "ISA",
    "#p": "PART_OF",
    "#m": "PART_OF",
    "#s": "PART_OF",
    "!": "CONTRADICTS",
    "&": "ASSOCIATED",
}
INVERSE_RELATION = {
    "ISA": "HAS_SUBTYPE",
    "HAS_SUBTYPE": "ISA",
    "PART_OF": "HAS_PART",
    "HAS_PART": "PART_OF",
    "CONTRADICTS": "CONTRADICTS",
    "ASSOCIATED": "ASSOCIATED",
}
SYMMETRIC_RELATIONS = {"CONTRADICTS", "ASSOCIATED"}
DIRECTIONAL_RELATIONS = {"ISA", "PART_OF"}

# Source priors.  These are deliberately conservative and are not calibrated
# probabilities.  The calibration script fits probabilities on the valid split.
POINTER_CONFIDENCE = {
    "@": 65535,
    "@i": 60000,
    "#p": 65535,
    "#m": 65535,
    "#s": 65535,
    "!": 60000,
    "&": 50000,
}
INVERSE_CONFIDENCE = {
    "ISA": 65000,
    "HAS_SUBTYPE": 65000,
    "PART_OF": 65000,
    "HAS_PART": 65000,
    "CONTRADICTS": 60000,
    "ASSOCIATED": 50000,
}
HARD_NEGATIVE_CONFIDENCE = 55000
HARD_NEGATIVE_FALLBACK_CONFIDENCE = 40000
RANDOM_NEGATIVE_CONFIDENCE = 45000
SELF_NEGATIVE_CONFIDENCE = 65535

STOPWORDS = frozenset(
    """a an and are as at be been being but by can could did do does for from
    had has have he her his how i if in into is it its may might more most no
    not of on one or other our out she should so some such than that the their
    them then there these they this those to up us was we were what when where
    which while who will with would you your""".split()
)
TOKEN_RE = re.compile(r"[a-z][a-z0-9_'-]{2,}")
LINE_RE = re.compile(r"^(\d{8})\s+(\d{2})\s+([nvars])\s+([0-9a-fA-F]{2})\s+")

DATA_FILES = ("data.noun", "data.verb", "data.adj", "data.adv")


@dataclass(frozen=True)
class Synset:
    pos: str
    offset: int
    lemmas: tuple[str, ...]
    gloss: str
    line_sha256: str
    file: str
    line_no: int
    pointers: tuple[tuple[str, str, int], ...] = ()

    @property
    def sid(self) -> str:
        return f"{self.pos}:{self.offset:08d}"

    @property
    def role_text(self) -> str:
        if self.lemmas:
            return self.lemmas[0].replace("_", " ").strip().lower()
        return f"synset {self.sid}"


@dataclass
class Anchor:
    src: Synset
    relation: str
    dst: Synset
    pointer: str
    source_file: str
    source_line: int
    source_sha256: str
    source_sid: str
    split: str


@dataclass
class Row:
    split: str
    relation: str
    label: str
    confidence: int
    subject: Synset
    predicate: str
    object: Synset
    source_sha256: str
    provenance: str
    readable_provenance: str


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_synsets(raw: bytes, filename: str) -> list[Synset]:
    """Parse one WordNet ``data.*`` file into exact synsets and pointers."""
    synsets: list[Synset] = []
    for line_no, raw_line in enumerate(raw.splitlines(), 1):
        line = raw_line.rstrip(b"\r")
        if not line or not LINE_RE.match(line.decode("latin-1", "replace")):
            continue
        text = line.decode("latin-1")
        body, _, gloss = text.partition("|")
        tok = body.split()
        if len(tok) < 6:
            continue
        try:
            offset = int(tok[0])
            pos = tok[2]
            wcnt = int(tok[3], 16)
        except (ValueError, IndexError):
            continue
        idx = 4
        lemmas: list[str] = []
        try:
            for _ in range(wcnt):
                lemma = tok[idx].replace("_", " ")
                lemmas.append(lemma)
                idx += 2
            pcnt = int(tok[idx])
            idx += 1
            pointers: list[tuple[str, str, int]] = []
            for _ in range(pcnt):
                sym = tok[idx]
                target_offset = int(tok[idx + 1])
                target_pos = tok[idx + 2]
                pointers.append((sym, target_pos, target_offset))
                idx += 4
        except (ValueError, IndexError):
            continue
        synsets.append(
            Synset(
                pos=pos,
                offset=offset,
                lemmas=tuple(lemmas),
                gloss=gloss.strip(),
                line_sha256=sha256_hex(line),
                file=filename,
                line_no=line_no,
                pointers=tuple(pointers),
            )
        )
    return synsets


def load_archive(archive: Path) -> tuple[dict[tuple[str, int], Synset], dict[str, str]]:
    """Load all synsets from a WordNet dict zip and return file digests."""
    synsets: dict[tuple[str, int], Synset] = {}
    digests: dict[str, str] = {}
    with zipfile.ZipFile(archive) as zf:
        names = {name.rsplit("/", 1)[-1]: name for name in zf.namelist()}
        for base in DATA_FILES:
            name = names.get(base)
            if name is None:
                raise SystemExit(f"archive is missing {base}")
            raw = zf.read(name)
            digests[base] = sha256_hex(raw)
            for synset in parse_synsets(raw, base):
                key = (synset.pos, synset.offset)
                if key in synsets:
                    raise SystemExit(f"duplicate synset {synset.sid} in {base}")
                synsets[key] = synset
    if not synsets:
        raise SystemExit("no synsets parsed")
    return synsets, digests


def normalize_pos(pos: str) -> str:
    return "a" if pos == "s" else pos


def resolve(
    synsets: dict[tuple[str, int], Synset], pos: str, offset: int
) -> Synset | None:
    direct = synsets.get((pos, offset))
    if direct is not None:
        return direct
    # Adjective satellites use ``s`` in pointer targets; data.adj stores them
    # as ``s`` too, but accept the normalized form as a fallback.
    return synsets.get((normalize_pos(pos), offset))


def lemma_tokens(synset: Synset) -> set[str]:
    tokens: set[str] = set()
    for lemma in synset.lemmas:
        for token in TOKEN_RE.findall(lemma.lower().replace("_", " ")):
            if token not in STOPWORDS:
                tokens.add(token)
    for token in TOKEN_RE.findall(synset.gloss.lower()):
        if token not in STOPWORDS:
            tokens.add(token)
    return tokens


def content_tokens(synset: Synset, limit: int = 16) -> set[str]:
    tokens = lemma_tokens(synset)
    # Keep the most specific-looking tokens first; this is deterministic and
    # only used to build a candidate index, never as a model feature.
    ordered = sorted(tokens, key=lambda t: (-len(t), t))
    return set(ordered[:limit])


def split_for_pair(a: str, b: str) -> str:
    lo, hi = sorted((a, b))
    digest = hashlib.sha256(f"{lo}|{hi}".encode("utf-8")).digest()
    bucket = int.from_bytes(digest[:4], "big") % 100
    if bucket < 80:
        return "train"
    if bucket < 90:
        return "valid"
    return "test"


def split_for_synset(sid: str) -> str:
    digest = hashlib.sha256(sid.encode("utf-8")).digest()
    bucket = int.from_bytes(digest[:4], "big") % 100
    if bucket < 80:
        return "train"
    if bucket < 90:
        return "valid"
    return "test"


def hex_text(text: str) -> str:
    return text.encode("utf-8").hex()


def pointer_text(pointer: str) -> str:
    return pointer


def row_provenance(
    *,
    subject: Synset,
    obj: Synset,
    relation: str,
    label: str,
    pointer: str = "",
    source_file: str = "",
    source_line: int = 0,
    source_sid: str = "",
    extra: str = "",
) -> str:
    gloss_digest = sha256_hex(obj.gloss.encode("utf-8", "replace"))[:16]
    subject_gloss = sha256_hex(subject.gloss.encode("utf-8", "replace"))[:16]
    parts = [
        "wordnet3.1",
        f"subject={subject.sid}",
        f"object={obj.sid}",
        f"relation={relation}",
        f"label={label}",
        f"subject_gloss_sha16={subject_gloss}",
        f"object_gloss_sha16={gloss_digest}",
    ]
    if pointer:
        parts.append(f"pointer={pointer}")
    if source_file:
        parts.append(f"file={source_file}")
    if source_line:
        parts.append(f"line={source_line}")
    if source_sid:
        parts.append(f"source_synset={source_sid}")
    if extra:
        parts.append(extra)
    return "|".join(parts)


def readable_provenance(row: Row) -> str:
    return (
        f"{row.subject.role_text} [{row.subject.sid}] {row.predicate} "
        f"{row.object.role_text} [{row.object.sid}] | {row.provenance}"
    )


def make_row(
    *,
    split: str,
    relation: str,
    label: str,
    confidence: int,
    subject: Synset,
    obj: Synset,
    source_sha256: str,
    provenance: str,
) -> Row:
    predicate = relation
    return Row(
        split=split,
        relation=relation,
        label=label,
        confidence=confidence,
        subject=subject,
        predicate=predicate,
        object=obj,
        source_sha256=source_sha256,
        provenance=provenance,
        readable_provenance="",
    )


class NegativeSampler:
    """Deterministic hard/random negative construction over the synset graph."""

    def __init__(
        self,
        synsets: dict[tuple[str, int], Synset],
        true_edges: set[tuple[str, str, str]],
        rng: random.Random,
    ) -> None:
        self.synsets = synsets
        self.true_edges = true_edges
        self.rng = rng
        self.by_pos: dict[str, list[Synset]] = defaultdict(list)
        for synset in synsets.values():
            self.by_pos[normalize_pos(synset.pos)].append(synset)
        for values in self.by_pos.values():
            values.sort(key=lambda s: s.sid)
        self.token_sets: dict[str, set[str]] = {
            synset.sid: content_tokens(synset) for synset in synsets.values()
        }
        self.token_index: dict[tuple[str, str], list[str]] = defaultdict(list)
        for synset in sorted(synsets.values(), key=lambda s: s.sid):
            pos = normalize_pos(synset.pos)
            for token in sorted(self.token_sets[synset.sid]):
                self.token_index[(pos, token)].append(synset.sid)

    def is_true(self, subject: Synset, relation: str, obj: Synset) -> bool:
        return (subject.sid, relation, obj.sid) in self.true_edges

    def hard_candidate(
        self, subject: Synset, relation: str, obj: Synset
    ) -> tuple[Synset, float, str] | None:
        pos = normalize_pos(subject.pos)
        obj_tokens = self.token_sets.get(obj.sid, set())
        if not obj_tokens:
            return None
        # Gather candidates through the rarest object tokens first.  This keeps
        # the candidate set small while still finding lexically close synsets.
        token_order = sorted(
            obj_tokens,
            key=lambda t: (len(self.token_index.get((pos, t), ())), t),
        )
        candidate_ids: list[str] = []
        seen: set[str] = set()
        for token in token_order[:5]:
            for sid in self.token_index.get((pos, token), ())[:64]:
                if sid not in seen:
                    seen.add(sid)
                    candidate_ids.append(sid)
        if not candidate_ids:
            return None
        scored: list[tuple[float, str, Synset]] = []
        for sid in candidate_ids[:320]:
            cand = self.synsets.get(tuple(self._sid_key(sid)))
            if cand is None or cand.sid in (subject.sid, obj.sid):
                continue
            if self.is_true(subject, relation, cand):
                continue
            cand_tokens = self.token_sets.get(cand.sid, set())
            union = obj_tokens | cand_tokens
            sim = len(obj_tokens & cand_tokens) / len(union) if union else 0.0
            # Siblings are especially hard negatives for taxonomy relations.
            if relation in ("ISA", "HAS_SUBTYPE") and cand.pos == obj.pos:
                # Same lemma token is already in the Jaccard term; a small
                # same-POS bonus avoids unrelated cross-POS candidates.
                sim += 0.05
            scored.append((sim, cand.sid, cand))
        if not scored:
            return None
        scored.sort(key=lambda item: (-item[0], item[1]))
        top = scored[:32]
        sim, sid, cand = self.rng.choice(top)
        return cand, sim, "lexical_jaccard"

    @staticmethod
    def _sid_key(sid: str) -> tuple[str, int]:
        pos, offset = sid.split(":", 1)
        return pos, int(offset)

    def random_candidate(
        self, subject: Synset, relation: str, obj: Synset
    ) -> tuple[Synset, str] | None:
        pool = self.by_pos.get(normalize_pos(subject.pos), ())
        if not pool:
            return None
        start = self.rng.randrange(len(pool))
        for step in range(len(pool)):
            cand = pool[(start + step) % len(pool)]
            if cand.sid in (subject.sid, obj.sid):
                continue
            if self.is_true(subject, relation, cand):
                continue
            return cand, "uniform_same_pos"
        return None


def build_anchors(
    synsets: dict[tuple[str, int], Synset],
) -> tuple[list[Anchor], Counter[str]]:
    """Build canonical forward anchors and report skipped pointer counts."""
    anchors: dict[tuple[str, str, str], Anchor] = {}
    skipped = Counter()
    for synset in sorted(synsets.values(), key=lambda s: s.sid):
        for sym, target_pos, target_offset in synset.pointers:
            relation = POINTER_RELATION.get(sym)
            if relation is None:
                if sym in ("~", "~i", "%p", "%m", "%s"):
                    skipped["inverse_pointer"] += 1
                else:
                    skipped["unsupported_pointer"] += 1
                continue
            target = resolve(synsets, target_pos, target_offset)
            if target is None:
                skipped["missing_target"] += 1
                continue
            if relation in SYMMETRIC_RELATIONS:
                src, dst = sorted((synset, target), key=lambda s: s.sid)
            else:
                src, dst = synset, target
            key = (src.sid, relation, dst.sid)
            if key in anchors:
                skipped["duplicate_anchor"] += 1
                continue
            anchors[key] = Anchor(
                src=src,
                relation=relation,
                dst=dst,
                pointer=sym,
                source_file=synset.file,
                source_line=synset.line_no,
                source_sha256=synset.line_sha256,
                source_sid=synset.sid,
                split="",
            )
    ordered = sorted(anchors.values(), key=lambda a: (a.relation, a.src.sid, a.dst.sid))
    return ordered, skipped


def build_rows(
    synsets: dict[tuple[str, int], Synset],
    anchors: Sequence[Anchor],
    *,
    seed: int,
    split_by: str = "pair",
    max_anchors_per_relation: int = 0,
) -> tuple[list[Row], dict[str, object]]:
    """Construct all rows, deduplicate them, and attach deterministic splits."""
    rng = random.Random(seed)

    # True edges include both directions so a negative can never accidentally
    # be a valid inverse relation.
    true_edges: set[tuple[str, str, str]] = set()
    for anchor in anchors:
        true_edges.add((anchor.src.sid, anchor.relation, anchor.dst.sid))
        true_edges.add(
            (anchor.dst.sid, INVERSE_RELATION[anchor.relation], anchor.src.sid)
        )
    sampler = NegativeSampler(synsets, true_edges, rng)

    # Cap per relation deterministically but with a seeded shuffle so a capped
    # corpus still covers the whole graph.
    by_relation: dict[str, list[Anchor]] = defaultdict(list)
    for anchor in anchors:
        by_relation[anchor.relation].append(anchor)
    selected: list[Anchor] = []
    for relation in RELATIONS:
        values = by_relation.get(relation, [])
        if max_anchors_per_relation and len(values) > max_anchors_per_relation:
            rng.shuffle(values)
            values = sorted(values[:max_anchors_per_relation], key=lambda a: (a.src.sid, a.dst.sid))
        selected.extend(values)
    selected.sort(key=lambda a: (a.relation, a.src.sid, a.dst.sid))

    rows: list[Row] = []
    seen: set[tuple[str, str, str, str]] = set()
    stats: Counter[str] = Counter()

    def row_split_for(subject: Synset, obj: Synset) -> str | None:
        """Assign a split from the unordered pair, not from the anchor.

        Pair mode guarantees that no unordered synset pair appears in two
        splits, even when one direction is a positive and the other direction
        is a hard/random/self negative. Synset mode is stricter: a row is kept
        only when both endpoint synsets belong to the same synset split.
        """
        if split_by == "pair":
            return split_for_pair(subject.sid, obj.sid)
        subject_split = split_for_synset(subject.sid)
        if split_for_synset(obj.sid) != subject_split:
            return None
        return subject_split

    def emit(row: Row) -> None:
        # Recompute the split from the actual row endpoints. This prevents a
        # negative row for a pair from leaking into a different split than a
        # positive row for the same pair.
        row_split = row_split_for(row.subject, row.object)
        if row_split is None:
            stats["dropped_synset_split"] += 1
            return
        row.split = row_split
        # Deduplicate by the row itself, not by split: the same
        # subject/relation/object row must never appear in two splits, even if
        # it was discovered from two different anchors.
        key = (row.relation, row.label, row.subject.sid, row.object.sid)
        if key in seen:
            stats["duplicate_row"] += 1
            return
        seen.add(key)
        row.readable_provenance = readable_provenance(row)
        rows.append(row)
        stats[f"label:{row.label}"] += 1
        stats[f"relation:{row.relation}"] += 1
        stats[f"split:{row.split}"] += 1
        stats[f"pair:{row.relation}:{row.label}"] += 1

    def direction_rows(
        *,
        anchor: Anchor,
        subject: Synset,
        relation: str,
        obj: Synset,
        label: str,
        split: str,
        pointer: str,
        confidence: int,
        extra: str,
    ) -> None:
        # The row is derived from the canonical forward anchor.  Use the
        # source line where the pointer was found for every direction, so
        # positive and inverse rows share one provenance root.  For symmetric
        # relations the pointer may live on the anchor's dst; source_sid records
        # that synset explicitly.
        source_sha = anchor.source_sha256
        emit(
            make_row(
                split=split,
                relation=relation,
                label=label,
                confidence=confidence,
                subject=subject,
                obj=obj,
                source_sha256=source_sha,
                provenance=row_provenance(
                    subject=subject,
                    obj=obj,
                    relation=relation,
                    label=label,
                    pointer=pointer,
                    source_file=anchor.source_file,
                    source_line=anchor.source_line, source_sid=anchor.source_sid,
                    extra=extra,
                ),
            )
        )
        # Hard negative: a lexically close synset that is not a true edge.
        hard = sampler.hard_candidate(subject, relation, obj)
        if hard is not None:
            cand, sim, method = hard
            emit(
                make_row(
                    split=split,
                    relation=relation,
                    label="hard_negative",
                    confidence=HARD_NEGATIVE_CONFIDENCE,
                    subject=subject,
                    obj=cand,
                    source_sha256=source_sha,
                    provenance=row_provenance(
                        subject=subject,
                        obj=cand,
                        relation=relation,
                        label="hard_negative",
                        pointer=pointer,
                        source_file=anchor.source_file,
                        source_line=anchor.source_line, source_sid=anchor.source_sid,
                        extra=(
                            f"anchor_object={obj.sid}|similarity={sim:.6f}"
                            f"|method={method}|fallback=0"
                        ),
                    ),
                )
            )
        else:
            fallback = sampler.random_candidate(subject, relation, obj)
            if fallback is not None:
                cand, method = fallback
                emit(
                    make_row(
                        split=split,
                        relation=relation,
                        label="hard_negative",
                        confidence=HARD_NEGATIVE_FALLBACK_CONFIDENCE,
                        subject=subject,
                        obj=cand,
                        source_sha256=source_sha,
                        provenance=row_provenance(
                            subject=subject,
                            obj=cand,
                            relation=relation,
                            label="hard_negative",
                            pointer=pointer,
                            source_file=anchor.source_file,
                            source_line=anchor.source_line, source_sid=anchor.source_sid,
                            extra=(
                                f"anchor_object={obj.sid}|similarity=0"
                                f"|method={method}|fallback=1"
                            ),
                        ),
                    )
                )
        # Uniform random negative.
        random_candidate = sampler.random_candidate(subject, relation, obj)
        if random_candidate is not None:
            cand, method = random_candidate
            emit(
                make_row(
                    split=split,
                    relation=relation,
                    label="negative",
                    confidence=RANDOM_NEGATIVE_CONFIDENCE,
                    subject=subject,
                    obj=cand,
                    source_sha256=source_sha,
                    provenance=row_provenance(
                        subject=subject,
                        obj=cand,
                        relation=relation,
                        label="negative",
                        pointer=pointer,
                        source_file=anchor.source_file,
                        source_line=anchor.source_line, source_sid=anchor.source_sid,
                        extra=f"anchor_object={obj.sid}|method={method}|seed={seed}",
                    ),
                )
            )
        # Self negative: the same synset in both roles.
        emit(
            make_row(
                split=split,
                relation=relation,
                label="self_negative",
                confidence=SELF_NEGATIVE_CONFIDENCE,
                subject=subject,
                obj=subject,
                source_sha256=source_sha,
                provenance=row_provenance(
                    subject=subject,
                    obj=subject,
                    relation=relation,
                    label="self_negative",
                    pointer=pointer,
                    source_file=anchor.source_file,
                    source_line=anchor.source_line, source_sid=anchor.source_sid,
                    extra=f"anchor_object={obj.sid}|method=identity",
                ),
            )
        )

    for anchor in selected:
        split = (
            split_for_pair(anchor.src.sid, anchor.dst.sid)
            if split_by == "pair"
            else split_for_synset(anchor.src.sid)
        )
        if split_by == "synset" and split_for_synset(anchor.dst.sid) != split:
            stats["dropped_synset_split"] += 1
            continue
        anchor.split = split
        confidence = POINTER_CONFIDENCE.get(anchor.pointer, 50000)
        direction_rows(
            anchor=anchor,
            subject=anchor.src,
            relation=anchor.relation,
            obj=anchor.dst,
            label="positive",
            split=split,
            pointer=anchor.pointer,
            confidence=confidence,
            extra=f"anchor=forward|split_by={split_by}",
        )
        inverse_relation = INVERSE_RELATION[anchor.relation]
        direction_rows(
            anchor=anchor,
            subject=anchor.dst,
            relation=inverse_relation,
            obj=anchor.src,
            label="inverse",
            split=split,
            pointer=anchor.pointer,
            confidence=INVERSE_CONFIDENCE[inverse_relation],
            extra=f"anchor=inverse|source_relation={anchor.relation}|split_by={split_by}",
        )

    rows.sort(key=lambda r: (r.split, r.relation, r.label, r.subject.sid, r.object.sid))
    return rows, {
        "true_edges": len(true_edges),
        "anchors_total": len(anchors),
        "anchors_selected": len(selected),
        "stats": dict(stats),
    }


def write_corpus(
    rows: Sequence[Row],
    *,
    tri_path: Path,
    readable_path: Path,
    manifest_path: Path,
    manifest: dict[str, object],
) -> None:
    tri_path.parent.mkdir(parents=True, exist_ok=True)
    readable_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    tri_hash = hashlib.sha256()
    readable_hash = hashlib.sha256()
    with tri_path.open("w", encoding="utf-8", newline="\n") as tri, readable_path.open(
        "w", encoding="utf-8", newline="\n"
    ) as readable:
        tri.write(SCHEMA + "\n")
        tri_hash.update((SCHEMA + "\n").encode("utf-8"))
        readable.write(
            "split\trelation\tlabel\tconfidence\tsubject\tpredicate\tobject\t"
            "subject_id\tobject_id\tsource_sha256\tprovenance\n"
        )
        readable_hash.update(
            (
                "split\trelation\tlabel\tconfidence\tsubject\tpredicate\tobject\t"
                "subject_id\tobject_id\tsource_sha256\tprovenance\n"
            ).encode("utf-8")
        )
        for row in rows:
            line = "\t".join(
                (
                    row.split,
                    row.relation,
                    row.label,
                    str(row.confidence),
                    hex_text(row.subject.role_text),
                    hex_text(row.predicate),
                    hex_text(row.object.role_text),
                    row.source_sha256,
                    row.provenance,
                )
            ) + "\n"
            tri.write(line)
            tri_hash.update(line.encode("utf-8"))
            rline = "\t".join(
                (
                    row.split,
                    row.relation,
                    row.label,
                    str(row.confidence),
                    row.subject.role_text,
                    row.predicate,
                    row.object.role_text,
                    row.subject.sid,
                    row.object.sid,
                    row.source_sha256,
                    row.readable_provenance,
                )
            ) + "\n"
            readable.write(rline)
            readable_hash.update(rline.encode("utf-8"))
    manifest["tri_sha256"] = tri_hash.hexdigest()
    manifest["readable_sha256"] = readable_hash.hexdigest()
    manifest["tri_bytes"] = tri_path.stat().st_size
    manifest["readable_bytes"] = readable_path.stat().st_size
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def histogram(values: Iterable[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def build_manifest(
    *,
    archive: Path,
    archive_sha256: str,
    file_digests: dict[str, str],
    synset_count: int,
    pointer_edges: int,
    rows: Sequence[Row],
    anchors_total: int,
    anchors_selected: int,
    row_stats: dict[str, object],
    skipped: Counter[str],
    options: dict[str, object],
) -> dict[str, object]:
    label_counts = Counter(row.label for row in rows)
    relation_counts = Counter(row.relation for row in rows)
    split_counts = Counter(row.split for row in rows)
    relation_label = Counter((row.relation, row.label) for row in rows)
    split_relation = Counter((row.split, row.relation) for row in rows)
    # Anchor-pair split audit: positive and inverse rows are the provenance-
    # bound relation rows.  A pair must never appear in two splits.
    anchor_pair_splits: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        if row.label in POSITIVE_LABELS:
            lo, hi = sorted((row.subject.sid, row.object.sid))
            anchor_pair_splits[f"{lo}|{hi}"].add(row.split)
    cross_split_anchor_pairs = sum(
        1 for values in anchor_pair_splits.values() if len(values) > 1
    )
    # All rows (including negatives) can reuse a pair; report it separately so
    # the audit does not hide a negative-row collision.
    row_pair_splits: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        lo, hi = sorted((row.subject.sid, row.object.sid))
        row_pair_splits[f"{lo}|{hi}"].add(row.split)
    cross_split_row_pairs = sum(
        1 for values in row_pair_splits.values() if len(values) > 1
    )
    synset_splits: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        synset_splits[row.subject.sid].add(row.split)
        synset_splits[row.object.sid].add(row.split)
    cross_split_synsets = sum(1 for values in synset_splits.values() if len(values) > 1)
    return {
        "schema": MANIFEST_SCHEMA,
        "tri_schema": SCHEMA,
        "archive": str(archive),
        "archive_sha256": archive_sha256,
        "files": dict(sorted(file_digests.items())),
        "synsets": synset_count,
        "pointer_edges": pointer_edges,
        "anchors_total": anchors_total,
        "anchors_selected": anchors_selected,
        "rows": len(rows),
        "labels": histogram(row.label for row in rows),
        "relations": histogram(row.relation for row in rows),
        "splits": histogram(row.split for row in rows),
        "relation_label": {
            f"{relation}/{label}": count
            for (relation, label), count in sorted(relation_label.items())
        },
        "split_relation": {
            f"{split}/{relation}": count
            for (split, relation), count in sorted(split_relation.items())
        },
        "anchor_pairs": len(anchor_pair_splits),
        "cross_split_anchor_pairs": cross_split_anchor_pairs,
        "row_pairs": len(row_pair_splits),
        "cross_split_row_pairs": cross_split_row_pairs,
        "cross_split_synsets": cross_split_synsets,
        "row_stats": row_stats,
        "skipped_pointers": dict(sorted(skipped.items())),
        "options": options,
        "label_definitions": {
            "positive": "direct WordNet pointer in the canonical forward direction",
            "inverse": "valid relation obtained by swapping subject/object and using the inverse relation",
            "hard_negative": "lexically close object that is not a true relation for the subject",
            "negative": "uniform same-POS object that is not a true relation for the subject",
            "self_negative": "subject used as its own object",
        },
        "confidence_note": (
            "confidence is a source prior in 0..65535, not a calibrated probability; "
            "the calibration script fits probabilities on the valid split"
        ),
        "split_note": (
            "pair split hashes the unordered synset pair; every row's split is "
            "derived from its own endpoints, so no unordered pair crosses splits. "
            "Negatives for an anchor can be in a different split than the anchor's "
            "positive/inverse rows. Use --split-by synset for a stricter "
            "synset-disjoint corpus (rows whose endpoints hash to different splits "
            "are dropped)."
        ),
        "predicate_note": (
            "predicate_hex encodes the canonical relation name; the trainer phase-encodes "
            "the role text in the raw guest. Subject/object role text is the first lemma."
        ),
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--archive",
        type=Path,
        default=Path("/storage/emulated/0/Download/NaNLMind/wn3.1.dict.zip"),
        help="WordNet 3.1 dict zip",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("state/relation_triangle/tri.tsv"),
        help="N16TRI/1 machine TSV",
    )
    ap.add_argument(
        "--readable",
        type=Path,
        default=Path("state/relation_triangle/tri.readable.tsv"),
        help="human-readable audit TSV",
    )
    ap.add_argument(
        "--manifest",
        type=Path,
        default=Path("state/relation_triangle/manifest.json"),
        help="manifest JSON",
    )
    ap.add_argument("--seed", type=int, default=20261110, help="deterministic sampling seed")
    ap.add_argument(
        "--max-anchors-per-relation",
        type=int,
        default=0,
        help="cap anchors per relation (0 = all)",
    )
    ap.add_argument(
        "--split-by",
        choices=("pair", "synset"),
        default="pair",
        help="split unit; pair is the default, synset is stricter",
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="run a tiny in-memory parser/label test and exit",
    )
    return ap.parse_args(argv)


def self_test() -> int:
    """A small deterministic test of the parser, labels and split function."""
    noun = (
        b"00000001 03 n 01 alpha 0 001 @ 00000002 n 0000 | first test synset\n"
        b"00000002 03 n 01 beta 0 001 ~ 00000001 n 0000 | second test synset\n"
        b"00000003 03 n 01 gamma 0 001 @ 00000002 n 0000 | third test synset\n"
    )
    synsets_list = parse_synsets(noun, "data.noun")
    assert len(synsets_list) == 3, synsets_list
    synsets = {(s.pos, s.offset): s for s in synsets_list}
    anchors, skipped = build_anchors(synsets)
    assert len(anchors) == 2, anchors
    rows, stats = build_rows(synsets, anchors, seed=7)
    assert rows, stats
    labels = {row.label for row in rows}
    assert labels == set(LABELS), labels
    assert all(row.split in SPLITS for row in rows)
    assert all(row.subject.sid != row.object.sid for row in rows if row.label != "self_negative")
    assert all(row.subject.sid == row.object.sid for row in rows if row.label == "self_negative")
    # The same anchor pair must never appear in two splits.  Negative rows can
    # reuse a pair, so restrict this audit to the provenance-bound positive and
    # inverse relation rows.
    pair_split: dict[tuple[str, str], str] = {}
    for row in rows:
        if row.label not in POSITIVE_LABELS:
            continue
        key = tuple(sorted((row.subject.sid, row.object.sid)))
        assert pair_split.setdefault(key, row.split) == row.split, key
    print(
        f"self-test PASS synsets={len(synsets)} anchors={len(anchors)} "
        f"rows={len(rows)} labels={sorted(labels)} skipped={dict(skipped)}"
    )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    archive = args.archive
    if not archive.is_file():
        print(f"archive not found: {archive}", file=sys.stderr)
        return 2
    archive_sha = sha256_hex(archive.read_bytes())
    synsets, digests = load_archive(archive)
    anchors, skipped = build_anchors(synsets)
    rows, stats = build_rows(
        synsets,
        anchors,
        seed=args.seed,
        split_by=args.split_by,
        max_anchors_per_relation=args.max_anchors_per_relation,
    )
    if not rows:
        print("no rows generated", file=sys.stderr)
        return 3
    manifest = build_manifest(
        archive=archive,
        archive_sha256=archive_sha,
        file_digests=digests,
        synset_count=len(synsets),
        pointer_edges=sum(len(s.pointers) for s in synsets.values()),
        rows=rows,
        anchors_total=int(stats["anchors_total"]),
        anchors_selected=int(stats["anchors_selected"]),
        row_stats=dict(stats["stats"]),
        skipped=skipped,
        options={
            "seed": args.seed,
            "split_by": args.split_by,
            "max_anchors_per_relation": args.max_anchors_per_relation,
            "archive": str(archive),
        },
    )
    write_corpus(
        rows,
        tri_path=args.out,
        readable_path=args.readable,
        manifest_path=args.manifest,
        manifest=manifest,
    )
    print(
        f"N16TRI/1 rows={len(rows)} anchors={stats['anchors_selected']}/"
        f"{stats['anchors_total']} synsets={len(synsets)} "
        f"splits={manifest['splits']} out={args.out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
