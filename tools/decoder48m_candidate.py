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
    args=p.parse_args()
    request=json.loads(args.candidate.read_text())
    if(request.get("base_sha256")!=EXPECTED_BASE or
       request.get("overlay_sha256")!=EXPECTED_OVERLAY):
        raise ValueError("candidate must be bound to frozen 48M pair")
    emitter=frozen_r25_emitter(args.archive_root)
    candidate=FiniteCandidateDistribution(emitter,request["context"],
                                           request["native_log_weights"])
    result={"checkpoint_training_events":48000000,"new_checkpoint_training_events":0,
            "candidate_only":True,"active_tensor_modified":False,
            "base_sha256":EXPECTED_BASE,"overlay_sha256":EXPECTED_OVERLAY,
            "normalizer":candidate.Z,
            "scores":{w:candidate.score(w) for w in request["query_words"]}}
    encoded=json.dumps(result,indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(encoded+"\n")
    print(encoded)
if __name__=="__main__":main()
