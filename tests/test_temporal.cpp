#include "nanlm/temporal.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    const Ref a = Ref::from_bit({PageId::root(), matrix_addr(0, 1), 0, 0});
    const Ref b = Ref::from_bit({PageId::root(), matrix_addr(1, 2), 0, 0});
    const Ref c = Ref::from_bit({PageId::root(), matrix_addr(2, 3), 0, 0});
    const Ref d = Ref::from_bit({PageId::child(PageId::root(), 4), matrix_addr(4, 5), 0, 0});

    BidirectionalMemory m;
    CHECK_EQ(m.size(), 0u);
    const std::uint32_t ab = m.link(a, b, 1, kTemporalReversible);
    const std::uint32_t bc = m.link(b, c, 2);
    const std::uint32_t ad = m.link(a, d, 3, kTemporalBranch);
    CHECK(ab && bc && ad);
    CHECK_EQ(m.size(), 3u);

    Ref out;
    CHECK(m.forward(a, out, 1));
    CHECK(out == b);
    CHECK(m.forward(a, out, 3));
    CHECK(out == d);
    CHECK(m.backward(c, out, 2));
    CHECK(out == b);
    CHECK(m.backward(d, out, 3));
    CHECK(out == a);

    CHECK_EQ(m.futures(a).size(), 2u);
    CHECK_EQ(m.pasts(c).size(), 1u);
    CHECK_EQ(m.at_epoch(1).size(), 1u);
    CHECK_EQ(m.between(1, 3).size(), 2u);

    // Repeated linking is allowed (a branch), and forward() picks the latest
    // epoch at or before the requested time.
    const std::uint32_t ab2 = m.link(a, c, 4);
    CHECK(ab2 != 0);
    CHECK_EQ(m.futures(a).size(), 3u);
    CHECK(m.forward(a, out, 4));
    CHECK(out == c);

    // Digest is deterministic and changes when a link is added.
    BidirectionalMemory m2;
    m2.link(a, b, 1, kTemporalReversible);
    m2.link(b, c, 2);
    m2.link(a, d, 3, kTemporalBranch);
    m2.link(a, c, 4);
    CHECK(m.digest() == m2.digest());

    const Hash256 before = m.digest();
    m.link(c, d, 5);
    CHECK(!(m.digest() == before));

    // Reversible mirror link.
    const Ref ab_fwd = Ref::from_bit({PageId::root(), matrix_addr(7, 11), 0, 0});
    const Ref ab_rev = Ref::from_bit({PageId::root(), matrix_addr(11, 7), 0, 0});
    const std::uint32_t mirror = m.link(ab_fwd, ab_rev, 6, kTemporalMirror | kTemporalReversible);
    CHECK(mirror != 0);
    CHECK(m.forward(ab_fwd, out, 6));
    CHECK(out == ab_rev);
    CHECK(m.backward(ab_rev, out, 6));
    CHECK(out == ab_fwd);

    // Remove a link.
    CHECK(m.remove(ab));
    CHECK(!m.remove(ab));
    CHECK(!m.forward(a, out, 1));
    CHECK(m.forward(a, out, 4));

    const auto wire = m.serialize();
    auto restored = BidirectionalMemory::from_bytes(wire.data(), wire.size());
    CHECK_EQ(restored.size(), m.size());
    CHECK(restored.digest() == m.digest());
    auto truncated = wire; truncated.pop_back();
    CHECK_EQ(BidirectionalMemory::from_bytes(truncated.data(), truncated.size()).size(), 0u);

    return test_done("bidirectional temporal memory");
}
