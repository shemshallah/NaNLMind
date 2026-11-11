import importlib.util
import pathlib
import sys
import unittest

TOOLS=pathlib.Path(__file__).parents[1]/"tools"
sys.path.insert(0,str(TOOLS))
import decoder48m_future3 as future3

class ConditionalFrozen48M:
    """Small interface fixture, not an independent model or checkpoint."""
    def __init__(self):
        self.seen=[]
    def score(self,context,word):
        self.seen.append((context,word))
        ctx=context.split()
        if ctx==["the","river"]:
            table={"alpha":.6,"beta":.2,"gamma":.1}
        elif ctx==["the","river","alpha"]:
            table={"alpha":.1,"beta":.8,"gamma":.05}
        elif ctx==["the","river","alpha","beta"]:
            table={"alpha":.1,"beta":.1,"gamma":.75}
        else:
            raise AssertionError("never condition on unseen gold future")
        return {"probability":table[word]}

class TestThreeFutureWords(unittest.TestCase):
    def test_autoregressive_without_gold(self):
        original=ConditionalFrozen48M()
        seen=[]
        def native(context,horizon,predicted):
            seen.append((context,horizon,predicted))
            return {"beta":0.5} if horizon==2 else {}
        out=future3.future_three_rollout(
            original,"the river",["alpha","beta","gamma"],
            native_remeasure=native)
        self.assertEqual(out["predicted_future_words"],["alpha","beta","gamma"])
        self.assertEqual([x[0] for x in seen],[
            "the river","the river alpha","the river alpha beta"])
        self.assertEqual([x[2] for x in seen],[
            (),("alpha",),("alpha","beta")])
        self.assertEqual([x["horizon"] for x in out["steps"]],[1,2,3])
        self.assertTrue(out["native_renormalization_per_generated_context"])
        self.assertFalse(out["uses_ground_truth_future_as_context"])
        self.assertFalse(out["full_vocabulary_argmax"])
        self.assertFalse(out["candidate_tensor_promotion"])
    def test_callback_not_used_without_native_guest(self):
        original=ConditionalFrozen48M()
        out=future3.future_three_rollout(
            original,"the river",["gamma","alpha","beta"])
        self.assertEqual(out["predicted_future_words"],["alpha","beta","gamma"])
        self.assertTrue(all(not x["native_candidate_words"] for x in out["steps"]))
    def test_native_guest_remeasures_every_generated_horizon(self):
        import json
        from types import SimpleNamespace
        from unittest.mock import patch
        original=ConditionalFrozen48M()
        receipts=[]
        calls=[]
        def fake_guest(args,check,capture_output,text):
            self.assertTrue(check and capture_output and text)
            exe,observed,predicted,gcount=args
            self.assertEqual(exe,"/tmp/fixture-native-observer")
            self.assertEqual(observed,"the river")
            n=int(gcount)
            self.assertEqual(predicted,["-","alpha","alpha beta"][n])
            calls.append(args)
            record={
                "schema":"nanlm.native-future3-measure/1",
                "horizon":n+1,"generated_word_count":n,
                "guest_measured":True,"source_future_read":False,
                "candidate_delta_available":False,
                "has_admitted_hodge_faces":False,"tensor_promoted":False,
                "now_void_head":255,"past_mask":7,
                "poincare_x":0.1,"poincare_y":-0.2,
                "poincare_radius":0.25,"poincare_depth":0.5,
            }
            return SimpleNamespace(stdout=json.dumps(record))
        native=future3.native_guest_remeasure(
            pathlib.Path("/tmp/fixture-native-observer"),"the river",receipts)
        with patch.object(future3.subprocess,"run",side_effect=fake_guest):
            result=future3.future_three_rollout(
                original,"the river",["alpha","beta","gamma"],
                native_remeasure=native)
        self.assertEqual(result["predicted_future_words"],["alpha","beta","gamma"])
        self.assertEqual(len(receipts),3)
        self.assertEqual(len(calls),3)
        self.assertTrue(result["frozen_48m_untouched"])
        self.assertFalse(result["candidate_tensor_promotion"])

    def test_native_guest_rejects_fabricated_promotion_evidence(self):
        import json
        from types import SimpleNamespace
        from unittest.mock import patch
        records=[]
        native=future3.native_guest_remeasure(
            pathlib.Path("/tmp/native"),"the river",records)
        forged={
            "schema":"nanlm.native-future3-measure/1",
            "horizon":1,"generated_word_count":0,
            "guest_measured":True,"source_future_read":False,
            "candidate_delta_available":True,
            "has_admitted_hodge_faces":False,"tensor_promoted":False,
            "now_void_head":255,"past_mask":7,
            "poincare_x":0,"poincare_y":0,
            "poincare_radius":0.2,"poincare_depth":0.4,
        }
        with patch.object(future3.subprocess,"run",return_value=SimpleNamespace(
                stdout=json.dumps(forged))):
            with self.assertRaises(ValueError):
                native("the river",1,())
        self.assertEqual(records,[])

    def test_boundaries(self):
        emit=ConditionalFrozen48M()
        for ctx,words in (("",["alpha"]),("ok",[]),("ok",["a","a"]),
                          ("ok",["UPPER"]),("ok",["two words"]),
                          ("ok",["x"]*4097)):
            with self.subTest(ctx=ctx,words=words[:2]):
                with self.assertRaises(ValueError):
                    future3.future_three_rollout(emit,ctx,words)
        with self.assertRaises(ValueError):
            future3.future_three_rollout(
                emit,"the river",["alpha"],native_remeasure=lambda *args:None)

if __name__=="__main__":
    unittest.main()
