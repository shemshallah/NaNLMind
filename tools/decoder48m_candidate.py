#!/usr/bin/env python3
"""Candidate-only finite-support full-word feedback on the frozen 48M R25 decoder.

Native NaN16 heads/triheads/global/meta supply candidate log weights. This
adapter only calls the ORIGINAL archived decoder and normalizes probabilities.
No checkpoint, model training parameter or trie is created or modified here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Mapping

EXPECTED_BASE = "299a91daf65c8e66fe3489940371d262afef18dd2ef6fef61947ac14c62bb717"
EXPECTED_OVERLAY = "62bf1e5defbb8224d795db16a8e6959cc9aa3d7fed8a63346c4cee205a1bea04"

def sha256(path: Path) -> str:
    digest=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(1<<20),b""): digest.update(block)
    return digest.hexdigest()

def validate_native_receipt(request: dict) -> bool:
    """Validate the native-to-decoder transport envelope; NOT a grant to promote.

    The receipt is created by a trusted local NaN16 process. JSON alone cannot
    cryptographically prove native provenance or replace the external lease.
    """
    if not isinstance(request, dict):
        raise ValueError("candidate must be a JSON object")
    if (request.get("base_sha256") != EXPECTED_BASE or
            request.get("overlay_sha256") != EXPECTED_OVERLAY):
        raise ValueError("candidate must be bound to frozen 48M pair")
    schema = request.get("schema")
    if schema is None:
        return False  # historical standalone candidate file
    if schema != "nanlm.48m-native-feedback/1":
        raise ValueError("unsupported native feedback receipt")
    evidence = request.get("native_evidence")
    if not isinstance(evidence, dict):
        raise ValueError("native feedback evidence required")
    if (evidence.get("meta_available") is not True or
            evidence.get("candidate_staged") is not True or
            evidence.get("automatic_promotion") is not False):
        raise ValueError("native candidate must be staged and nonpromoting")
    past = evidence.get("committed_history_slots")
    triads = evidence.get("accepted_triads")
    contexts = evidence.get("native_observed_contexts")
    if any(type(v) is not int for v in (past, triads, contexts)):
        raise ValueError("native receipt counters must be integers")
    if not (1 <= past <= 16 and 0 <= triads <= 85 and 1 <= contexts <= 4096):
        raise ValueError("native receipt count outside hardware bounds")
    for k in ("proposer", "h", "a", "b"):
        v = evidence.get(k)
        if type(v) is not int or not 0 <= v < 255:
            raise ValueError("native receipt uses invalid or void coordinate")
    return True


def evaluate_candidate_panel(emitter, records: list) -> dict:
    """Exact-word NLL diagnostic on explicitly supplied candidate panel rows.

    Evaluation does NOT update the 48M decoder, create tensor permission,
    set a global/meta gate, or promote any bank.
    """
    if not isinstance(records, list) or not records:
        raise ValueError("candidate panel must have records")
    baseline_nll = candidate_nll = 0.0
    for row in records:
        if not isinstance(row, dict) or not isinstance(row.get("context"), str):
            raise ValueError("candidate panel requires context")
        word = row.get("target")
        if not isinstance(word, str) or not word:
            raise ValueError("candidate panel requires target")
        deltas = row.get("native_log_weights", {})
        if not isinstance(deltas, dict):
            raise ValueError("candidate panel weights must be dictionary")
        dist = FiniteCandidateDistribution(emitter, row["context"], deltas)
        p0 = float(emitter.score(row["context"], word)["probability"])
        p1 = float(dist.score(word)["probability"])
        if not all(math.isfinite(p) and 0 < p <= 1 for p in (p0, p1)):
            raise ValueError("invalid exact-word evaluation probability")
        baseline_nll -= math.log(p0)
        candidate_nll -= math.log(p1)
    baseline_nll /= len(records)
    candidate_nll /= len(records)
    return {
        "positions": len(records),
        "baseline_exact_word_nll": baseline_nll,
        "candidate_exact_word_nll": candidate_nll,
        "nll_improvement": baseline_nll - candidate_nll,
        "candidate_better_on_this_panel": candidate_nll < baseline_nll,
        "tensor_promotion_allowed": False,
        "requires_source_disjoint_precommitted_validation": True,
    }

class FiniteCandidateDistribution:
    """Exact normalizer over all words, including infinite OOV spelling space.

    Z=1+sum_{u in candidates} P_48M(u|context)*(exp(delta(u))-1)
    P_candidate(w)=P_48M(w)*exp(delta(w) if candidate else 0)/Z
    """
    def __init__(self, frozen_emitter, context: str, native_log_weights: Mapping[str,float]):
        self.emitter=frozen_emitter
        self.context=context
        self.native_log_weights={}
        self.base_mass={}
        for word,value in native_log_weights.items():
            if not isinstance(word,str) or word!=word.lower() or not word:
                raise ValueError("native words must be canonical lowercase")
            value=float(value)
            if not math.isfinite(value) or abs(value)>8.0:
                raise ValueError("invalid guest log weight [-8,8]")
            self.native_log_weights[word]=value
            p=float(self.emitter.score(context,word)["probability"])
            if not math.isfinite(p) or not 0.0<=p<=1.0:
                raise ValueError("frozen decoder probability invalid")
            self.base_mass[word]=p
        if sum(self.base_mass.values())>1.0+1e-9:
            raise ValueError("candidate probability mass exceeds one")
        self.Z=1.0+sum(p*math.expm1(self.native_log_weights[word])
                       for word,p in self.base_mass.items())
        if not math.isfinite(self.Z) or self.Z<=0:
            raise ValueError("normalizer invalid")
    def score(self,word:str,activated:bool=True)->dict:
        original=self.emitter.score(self.context,word)
        p=float(original["probability"])
        if not activated:
            return {**original,"baseline_probability":p,"candidate_activated":False}
        delta=self.native_log_weights.get(word,0.0)
        return {**original,"baseline_probability":p,
                "probability":p*math.exp(delta)/self.Z,
                "candidate_activated":True,"normalizer":self.Z,
                "native_log_weight":delta}

def frozen_r25_emitter(root:Path):
    """Load R27's original R25 emitter and exact R20+R22 checkpoint; no new model."""
    root=root.resolve()
    sys.path.insert(0,str(root))
    import hybrid_v25_emit as r25
    base=root/"run_v20_new_prose/state.npz"
    overlay=root/"run_v22_direct_context_char/state_overlay.npz"
    if sha256(base)!=EXPECTED_BASE or sha256(overlay)!=EXPECTED_OVERLAY:
        raise ValueError("checkpoint differs from the frozen 48M R27 archive")
    args=argparse.Namespace(
        base=base,overlay=overlay,
        cache=root/"run_v23_normalized_open_vocab",
        r21_report=root/"run_v21_open_vocab/report.json",
        r22_report=root/"run_v22_direct_context_char/evaluation.json",
        r23_report=root/"run_v23_normalized_open_vocab/evaluation.json",
        r24_report=root/"run_v24_full_context_trie/evaluation.json",
        r25_report=root/"run_v25_pair_context_trie/evaluation.json",
        headcache=root/"run_v24_full_context_trie/known_mass_by_head_v24.json",
        trie=root/"run_v24_full_context_trie/trie_base_transitions.npz")
    return r25.Emitter(args)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--archive-root",type=Path,required=True)
    p.add_argument("--candidate",type=Path,required=True)
    p.add_argument("--output",type=Path)
    p.add_argument("--dev-panel",type=Path,help="External predeclared development panel JSON; diagnostic only")
    args=p.parse_args()
    request=json.loads(args.candidate.read_text())
    native_receipt = validate_native_receipt(request)
    emitter=frozen_r25_emitter(args.archive_root)
    candidate=FiniteCandidateDistribution(emitter,request["context"],
                                           request["native_log_weights"])
    result={"checkpoint_training_events":48000000,"new_checkpoint_training_events":0,
            "candidate_only":True,"active_tensor_modified":False,
            "native_receipt_envelope_valid":native_receipt,
            "promotion_allowed":False,
            "base_sha256":EXPECTED_BASE,"overlay_sha256":EXPECTED_OVERLAY,
            "normalizer":candidate.Z,
            "scores":{w:candidate.score(w) for w in request["query_words"]}}
    if args.dev_panel:
        raw=args.dev_panel.read_bytes()
        panel=json.loads(raw)
        if not isinstance(panel, dict) or not isinstance(panel.get("records"), list):
            raise ValueError("development panel must have records array")
        result["development_panel_sha256"]=hashlib.sha256(raw).hexdigest()
        result["development_diagnostic"]=evaluate_candidate_panel(emitter,panel["records"])
    encoded=json.dumps(result,indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(encoded+"\n")
    print(encoded)
if __name__=="__main__":main()
