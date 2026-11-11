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
import tempfile
import subprocess
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

def native_guest_remeasure(guest_executable: Path, observed_context: str,
                           receipts: list[dict]):
    """Call the SAME NaN16 guest at each frozen-decoder causal horizon.

    The observer computes actual native trig/MC0/Poincare geometry, but has
    no sourced Hodge faces or loss-trained proposal; it must return ZERO
    candidate logit deltas. Never disguise untrained geometry as a learned
    decoder adjustment. All original 48M word probabilities remain exact.
    """
    observed=observed_context.strip()
    if not observed:
        raise ValueError("original observed context must be nonempty")

    def observe(context: str, horizon: int, previously_generated: tuple[str,...]):
        if horizon!=len(previously_generated)+1 or horizon not in (1,2,3):
            raise ValueError("native guest horizon/source mismatch")
        expected=" ".join((observed,*previously_generated))
        if context!=expected:
            raise ValueError("future native observer received altered context")
        command=[str(guest_executable),observed,
                 " ".join(previously_generated) if previously_generated else "-",
                 str(len(previously_generated))]
        completed=subprocess.run(command,check=True,capture_output=True,text=True)
        receipt=json.loads(completed.stdout)
        if (receipt.get("schema")!="nanlm.native-future3-measure/1" or
            receipt.get("horizon")!=horizon or
            receipt.get("generated_word_count")!=len(previously_generated) or
            receipt.get("guest_measured") is not True or
            receipt.get("source_future_read") is not False or
            receipt.get("candidate_delta_available") is not False or
            receipt.get("has_admitted_hodge_faces") is not False or
            receipt.get("tensor_promoted") is not False or
            receipt.get("now_void_head")!=255 or
            receipt.get("past_mask",0)<1 or receipt.get("past_mask",0)>7):
            raise ValueError("native guest reported invalid causal evidence")
        for key in ("poincare_x","poincare_y","poincare_radius","poincare_depth"):
            if not math.isfinite(float(receipt[key])):
                raise ValueError("nonfinite native geometry receipt")
        if not (0<=receipt["poincare_radius"]<1 and receipt["poincare_depth"]>=0):
            raise ValueError("invalid native Poincare ball")
        receipts.append(receipt)
        return {} # No unvalidated word-logit modifications!
    return observe

def native_batch_remeasure(
    batch_binary: Path,
    candidate_words: Sequence[str],
    timeout: int=180,
) -> Callable[[str,int,tuple[str,...]],Mapping[str,float]]:
    """One native opcode112 batch proposal for the entire shortlist.

    This is the production path: the guest evaluates every candidate through
    six-slot CORDIC attention and Poincare geometry in one ABI call.  The host
    only transports text/IDs and parses the typed receipt.
    """
    batch_binary=batch_binary.resolve()
    if not batch_binary.is_file():
        raise FileNotFoundError(f"native batch emitter missing: {batch_binary}")
    def callback(prefix: str, horizon: int,
                 generated: tuple[str,...]) -> Mapping[str,float]:
        words=prefix.split()
        if not words:
            raise ValueError("native batch requires nonempty context")
        current=words[-1]
        previous=words[-2] if len(words)>=2 else current
        if len(previous.encode())>64 or len(current.encode())>64:
            raise ValueError("native batch windows must be 1..64 bytes")
        with tempfile.TemporaryDirectory(prefix="nanlm-native-batch-loop-") as tmp:
            tmp_path=Path(tmp)
            (tmp_path/"previous.txt").write_text(previous,encoding="utf-8")
            (tmp_path/"current.txt").write_text(current,encoding="utf-8")
            (tmp_path/"words.txt").write_text(
                "\n".join(candidate_words)+"\n",encoding="utf-8")
            out=tmp_path/"batch.json"
            proc=subprocess.run(
                [str(batch_binary),str(tmp_path/"previous.txt"),
                 str(tmp_path/"current.txt"),prefix,
                 str(tmp_path/"words.txt"),str(out)],
                cwd=batch_binary.parents[1],text=True,capture_output=True,
                timeout=timeout)
            if proc.returncode!=0:
                raise RuntimeError(
                    "native batch failed: "+
                    (proc.stderr.strip() or proc.stdout.strip()))
            receipt=json.loads(out.read_text())
            if receipt.get("context")!=prefix:
                raise RuntimeError("native batch context mismatch")
            native=receipt.get("native_log_weights")
            if not isinstance(native,dict) or set(native)!=set(candidate_words):
                raise RuntimeError("native batch returned a mismatched shortlist")
            return {word:float(native[word]) for word in candidate_words}
    return callback


def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root",type=Path,required=True)
    parser.add_argument("--context",required=True,help="Observed prefix, no future gold")
    parser.add_argument("--wordlist",type=Path,required=True)
    parser.add_argument("--native-guest",type=Path,
                        help="existing NaN16 opcode112 observer (measure only)")
    parser.add_argument("--native-batch",type=Path,
                        help="native opcode118 shortlist candidate batch (candidate-only)")
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    words=[x.strip() for x in args.wordlist.read_text().splitlines() if x.strip()]
    native_receipts: list[dict]=[]
    if args.native_batch is not None:
        observer=native_batch_remeasure(args.native_batch,words)
    else:
        observer=(native_guest_remeasure(args.native_guest,args.context,native_receipts)
                  if args.native_guest is not None else None)
    result=future_three_rollout(frozen_r25_emitter(args.archive_root),
                                args.context,words,native_remeasure=observer)
    result["native_batch_abi"]=("opcode118" if args.native_batch is not None
                                else "disabled")
    if args.native_guest is not None:
        if len(native_receipts)!=3:
            raise RuntimeError("NaN16 observer omitted a future-word horizon")
        result["native_future3_receipts"]=native_receipts
        result["native_math_origin"]="NaN16 opcode112 CORDIC/MC0/Poincare"
        result["untrained_native_deltas_applied"]=False
    result["shortlist_sha256"]=hashlib.sha256(args.wordlist.read_bytes()).hexdigest()
    encoded=json.dumps(result,indent=2)
    if args.output:
        args.output.write_text(encoded+"\n")
    print(encoded)

if __name__=="__main__":
    main()
