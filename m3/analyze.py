#!/usr/bin/env python3
"""Predeclared descriptive paired-book diagnostics for fixed M3 R4 arms.

No arm or hyperparameter is selected using the previously exposed TEST books.
"""
import argparse
import json
from pathlib import Path
import numpy as np

COMPARISONS = (("triangle", "same"), ("triangle", "prior"),
               ("triangle", "plain_trigram"),
               ("same", "wrong_book"), ("crossed", "same"))


def summarize(data):
    rng = np.random.default_rng(1604)
    result = {}
    for split in ("dev", "test_previously_exposed"):
        if split not in data:
            continue
        result[split] = {}
        for level in ("byte", "bpe", "word", "sentence_class"):
            rows = [value[level]["modes"] for value in data[split]["books"].values()
                    if isinstance(value.get(level), dict)]
            level_result = {}
            for newer, older in COMPARISONS:
                # Positive values indicate that the first arm needs fewer bits.
                paired = np.array([r[older]["bits_per_unit"]-r[newer]["bits_per_unit"]
                                   for r in rows], dtype=np.float64)
                resampled = np.mean(rng.choice(paired,size=(10000,len(paired)),replace=True),axis=1)
                level_result[f"{newer}_versus_{older}"] = {
                    "books":len(paired),
                    "mean_bits_per_unit_saved":round(float(paired.mean()),6),
                    "books_improved":int((paired > 0).sum()),
                    "descriptive_whole_book_bootstrap_95_interval":
                        [round(float(x),6) for x in np.quantile(resampled,[.025,.975])]
                }
            result[split][level] = level_result
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input",type=Path,default=Path("m3/results.json"))
    p.add_argument("--output",type=Path,default=Path("m3/book_bootstrap.json"))
    a=p.parse_args()
    result=summarize(json.loads(a.input.read_text()))
    a.output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2))


if __name__ == "__main__":
    main()
