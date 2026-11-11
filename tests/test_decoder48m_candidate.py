import importlib.util
import pathlib
import unittest

SOURCE=pathlib.Path(__file__).parents[1]/"tools/decoder48m_candidate.py"
spec=importlib.util.spec_from_file_location("decoder48m_candidate",SOURCE)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Frozen48MFixture:
    def __init__(self):
        self.probs={"a":.45,"b":.30,"outofvocab":.15,"other":.10}
    def score(self,context,word):
        return {"probability":self.probs[word],"known":word!="outofvocab"}

class TestCandidate(unittest.TestCase):
    def test_known_oov_exact_normalization(self):
        old=Frozen48MFixture()
        d=m.FiniteCandidateDistribution(old,"context",{"b":1.0,"outofvocab":-.7})
        self.assertAlmostEqual(sum(d.score(w)["probability"] for w in old.probs),1.)
        self.assertEqual(d.score("a",activated=False)["probability"],.45)
        self.assertGreater(d.score("b")["probability"],d.score("b")["baseline_probability"])
        self.assertLess(d.score("outofvocab")["probability"],.15)
    def test_empty_preserves_frozen_48m(self):
        old=Frozen48MFixture()
        d=m.FiniteCandidateDistribution(old,"",{})
        self.assertEqual(d.Z,1.)
        for w,p in old.probs.items():self.assertEqual(d.score(w)["probability"],p)
    def test_nonfinite_native_weights_rejected(self):
        for v in (float("nan"),float("inf"),-9.,9.):
            with self.assertRaises(ValueError):
                m.FiniteCandidateDistribution(Frozen48MFixture(),"",{"a":v})
    def test_invalid_candidate_mass_rejected(self):
        class Bad:
            def score(self,context,word):return {"probability":.8}
        with self.assertRaises(ValueError):
            m.FiniteCandidateDistribution(Bad(),"",{"a":1.,"b":1.})
    def test_native_receipt_requires_guest_meta_and_committed_past(self):
        req={"schema":"nanlm.48m-native-feedback/1",
             "base_sha256":m.EXPECTED_BASE,"overlay_sha256":m.EXPECTED_OVERLAY,
             "native_evidence":{"meta_available":True,"candidate_staged":True,
                 "automatic_promotion":False,"committed_history_slots":1,
                 "native_observed_contexts":4,"accepted_triads":1,
                 "proposer":3,"h":7,"a":2,"b":3}}
        self.assertTrue(m.validate_native_receipt(req))
        req["native_evidence"]["committed_history_slots"]=0
        with self.assertRaises(ValueError):m.validate_native_receipt(req)
        req["native_evidence"]["committed_history_slots"]=1
        req["native_evidence"]["h"]=255
        with self.assertRaises(ValueError):m.validate_native_receipt(req)
        req["native_evidence"]["h"]=7
        req["native_evidence"]["automatic_promotion"]=True
        with self.assertRaises(ValueError):m.validate_native_receipt(req)
    def test_panel_exact_nll_never_promotes(self):
        old=Frozen48MFixture()
        rows=[{"context":"x","target":"b","native_log_weights":{"b":.5}},
              {"context":"y","target":"outofvocab","native_log_weights":{}}]
        result=m.evaluate_candidate_panel(old,rows)
        self.assertEqual(result["positions"],2)
        self.assertGreater(result["nll_improvement"],0)
        self.assertFalse(result["tensor_promotion_allowed"])
        rows[1]["native_log_weights"]={"a":2.0}
        worse=m.evaluate_candidate_panel(old,rows)
        self.assertLess(worse["nll_improvement"],result["nll_improvement"])
if __name__=="__main__":unittest.main()
