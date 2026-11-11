#!/usr/bin/env python3
"""Read-only three-step autoregressive future-word rollout of the ORIGINAL 48M.

This is a sequencing/receipt adapter, NOT a replacement model or trainer.
Every word probability is calculated by the original frozen R25 Emitter via
decoder48m_candidate.FiniteCandidateDistribution. The native NaN16 guest owns
head/trihead/Hodge/MC0/curl credit and only emits finite log-weight candidates.
The scheduler must remeasure native feedback at each newly GENERATED context
before using its candidate deltas; it never conditions on ground-truth future.

Candidate vocabulary is supplied by the user/corpus and is a BOUNDED
shortlist. This is not exact global argmax over infinite OOV spellings.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
from collections.abc import Callable, Mapping, Sequence
from decoder48m_candidate import FiniteCandidateDistribution, frozen_r25_emitter

def future_three_rollout(
    emitter,
    observed_context: str,
    candidate_words: Sequence[str],
    *,
    native_remeasure: Callable[[str,int,tuple[str,...]],Mapping[str,float]]|None=None,
) -> dict:
    """Choose t+1, t+2, t+3 conditional on OBSERVED + GENERATED words only.

    native_remeasure is an external verified native-guest callback for the
    CURRENT generated prefix. We NEVER reuse stale first-step logits on a
    different context. No gold targets are an argument to this function.
    """
    if not isinstance(observed_context,str) or not observed_context.strip():
        raise ValueError("nonempty observed context required")
    if not (1<=len(candidate_words)<=4096):
        raise ValueError("bounded 1..4096 vocabulary required")
    if any(not isinstance(w,str) or not w or w!=w.lower() or
           not w.isalpha() for w in candidate_words):
        raise ValueError("words must be canonical lowercase alphabetic")
    if len(set(candidate_words))!=len(candidate_words):
        raise ValueError("duplicate candidate word")
    prefix=observed_context.strip()
    emitted: list[str]=[]
    steps=[]
    for horizon in (1,2,3):
        weights=(native_remeasure(prefix,horizon,tuple(emitted))
                 if native_remeasure is not None else {})
        if not isinstance(weights,Mapping):
            raise ValueError("native callback must supply a mapping")
        distribution=FiniteCandidateDistribution(emitter,prefix,weights)
        best=None
        maxprob=-1.0
        for word in sorted(candidate_words):
            probability=float(distribution.score(word)["probability"])
            if not math.isfinite(probability) or probability<0 or probability>1:
                raise ValueError("invalid frozen 48M candidate probability")
            if probability>maxprob:
                best=word
                maxprob=probability
        assert best is not None
        steps.append({
            "horizon":horizon,
            "observed_plus_generated_context":prefix,
            "predicted_word":best,
            "conditional_probability":maxprob,
            "candidate_word_count":len(candidate_words),
            "native_candidate_words":sorted(weights),
        })
        emitted.append(best)
        # The ONLY new observation at horizon h+1 is our own prediction at h.
        prefix=f"{prefix} {best}"
    return {
        "schema":"nanlm.frozen48m-future3-shortlist/1",
        "predicted_future_words":emitted,
        "steps":steps,
        "uses_ground_truth_future_as_context":False,
        "native_renormalization_per_generated_context":True,
        "full_vocabulary_argmax":False,
        "exact_conditional_probability_for_each_selected_word":True,
        "frozen_48m_untouched":True,
        "candidate_tensor_promotion":False,
        "requires_precommitted_disjoint_evaluation":True,
    }

def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root",type=Path,required=True)
    parser.add_argument("--context",required=True,help="Observed prefix, no future gold")
    parser.add_argument("--wordlist",type=Path,required=True)
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    words=[x.strip() for x in args.wordlist.read_text().splitlines() if x.strip()]
    result=future_three_rollout(frozen_r25_emitter(args.archive_root),
                                args.context,words)
    result["shortlist_sha256"]=hashlib.sha256(args.wordlist.read_bytes()).hexdigest()
    encoded=json.dumps(result,indent=2)
    if args.output:
        args.output.write_text(encoded+"\n")
    print(encoded)

if __name__=="__main__":
    main()
