import unittest
import numpy as np

from m3.r4 import Alphabet, Memory, Metrics, addr, bpe_encode, bpe_vocab, head, mirror, pair_rank, predict, train_bpe, triangle_rank


class M3Tests(unittest.TestCase):
    def test_all_addresses_and_pairs(self):
        pair_ids = set()
        for a in range(256):
            for b in range(256):
                self.assertEqual(mirror(addr(a,b)), addr(b,a))
                self.assertEqual(mirror(mirror(addr(a,b))), addr(a,b))
                if a < b:
                    pair_ids.add(pair_rank(a,b))
        self.assertEqual(pair_ids,set(range(32640)))
        self.assertEqual(triangle_rank(0,1,2), 0)
        self.assertEqual(triangle_rank(253,254,255), 2763519)

    def test_two_banks_and_signed_rails(self):
        memory = Memory(recent=2,older=3)
        for value in [1,2,1,3,2,4,1,5]:
            memory.observe(0,value)
        self.assertEqual(sum(map(len,memory.queues[0])),5)
        self.assertEqual(int(memory.counts[0].sum()),5)
        for bank in range(2):
            for a in range(8):
                for b in range(8):
                    s,d = memory.rails(0,bank,a,b)
                    self.assertEqual(s+d,memory.counts[0,bank,a,b])
                    self.assertEqual(s-d,memory.counts[0,bank,b,a])

    def test_prefix_future_independence(self):
        alpha = Alphabet(0, {i:1 for i in range(256)})
        a,b = Memory(recent=2,older=3),Memory(recent=2,older=3)
        for x in (10,11,12,10,11,12,10,11):
            a.observe(0,x)
            b.observe(0,x)
        before_a = predict(a,0,alpha,"triangle")
        before_b = predict(b,0,alpha,"triangle")
        np.testing.assert_array_equal(before_a,before_b)
        np.testing.assert_array_equal(before_a,predict(a,0,alpha,"plain_trigram"))
        a.observe(0,55)
        self.assertEqual(b.last[0],11)
        self.assertNotEqual(a.last[0],b.last[0])
        np.testing.assert_array_equal(before_b,predict(b,0,alpha,"triangle"))
        self.assertFalse(np.array_equal(predict(b,0,alpha,"same"),predict(b,0,alpha,"crossed")))

    def test_reversible_train_only_bpe(self):
        inputs=[b"banana bandana",b"bananananana",bytes(range(256))]
        merges=train_bpe(inputs,12)
        vocabulary=bpe_vocab(merges)
        for original in inputs:
            ids,offsets=bpe_encode(original,merges)
            self.assertEqual(b"".join(vocabulary[i] for i in ids),original)
            self.assertEqual(offsets,sorted(offsets))

    def test_unknown_words_never_count_exact(self):
        m=Metrics()
        m.add(np.array([.05,.05,.90]),2,4,is_unk=True)
        self.assertEqual(m.output()["top1"],0)
        self.assertEqual(m.output()["closed_class_top1_including_unknown"],1)


if __name__=="__main__":
    unittest.main()
