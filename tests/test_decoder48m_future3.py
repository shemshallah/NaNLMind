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
