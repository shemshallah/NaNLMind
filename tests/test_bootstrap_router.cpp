#include "nanlm/bootstrap_router.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

int main() {
    // Point 1 is a non-head control portal; 256 is the alternate mapping.
    CHECK(!is_palindrome16(PointRouter::kDefaultPoint));
    CHECK(!is_palindrome16(PointRouter::kAlternatePoint));
    PointRouter point1(PointRouter::kDefaultPoint);
    CHECK_EQ(point1.point(), 1u);
    CHECK_EQ(point1.bindings(), 0u);
    const LayerRef ref{3, 1, 7, 2, 9001, 4};
    CHECK(point1.bind(7, ref));
    CHECK_EQ(point1.bindings(), 1u);
    auto resolved = point1.resolve(7);
    CHECK(resolved.has_value());
    if (resolved) CHECK(*resolved == ref);
    CHECK(!point1.bind(8, LayerRef{}));
    CHECK(point1.unbind(7));
    CHECK(!point1.resolve(7).has_value());

    PointRouter point256(PointRouter::kAlternatePoint);
    CHECK_EQ(point256.point(), 256u);
    CHECK(point256.bind(7, ref));
    CHECK(point1.digest() != point256.digest());

    HopfieldConfig cfg;
    cfg.top_k = 2;
    cfg.max_strength = 8;
    HopfieldRouter hop(cfg);
    HopfieldRouter::Vector a{};
    HopfieldRouter::Vector b{};
    a[0] = 10;
    b[1] = 10;
    hop.set_head(0, a);
    hop.set_head(1, b);
    hop.set_head(2, a);
    hop.set_head(3, b);

    auto pa = hop.predict(a);
    CHECK(pa.abstain);
    CHECK_EQ(pa.active.size(), 2u);
    if (pa.active.size() == 2u) {
        CHECK_EQ(pa.active[0], 0u);
        CHECK_EQ(pa.active[1], 2u);
    }
    auto pb = hop.predict(b);
    CHECK(pb.abstain);
    if (pb.active.size() == 2u) {
        CHECK_EQ(pb.active[0], 1u);
        CHECK_EQ(pb.active[1], 3u);
    }

    CHECK(hop.learn(a, 42));
    auto after_a = hop.predict(a);
    CHECK(!after_a.abstain);
    CHECK_EQ(after_a.token, 42u);
    CHECK(hop.learn(a, 42));
    auto stronger = hop.predict(a);
    CHECK_EQ(stronger.token, 42u);
    CHECK(stronger.score > after_a.score);
    CHECK_EQ(hop.used_slots(), 1u);

    CHECK(hop.learn(b, 7));
    auto after_b = hop.predict(b);
    CHECK(!after_b.abstain);
    CHECK_EQ(after_b.token, 7u);
    CHECK_EQ(hop.used_slots(), 2u);

    // A wrong target evicts/overwrites the weakest active association.
    CHECK(hop.learn(a, 7));
    auto overwritten = hop.predict(a);
    CHECK(!overwritten.abstain);
    CHECK_EQ(overwritten.token, 7u);

    // Restore the original target; another wrong target may overwrite again.
    CHECK(hop.learn(a, 42));
    auto restored = hop.predict(a);
    CHECK_EQ(restored.token, 42u);

    // The active-pair budget is at most the sparse-scan bound.
    CHECK(pa.active.size() * 255u <= 2040u);

    const Hash256 d1 = hop.digest();
    HopfieldRouter hop2(cfg);
    hop2.set_head(0, a);
    hop2.set_head(1, b);
    hop2.set_head(2, a);
    hop2.set_head(3, b);
    CHECK(hop2.learn(a, 42));
    CHECK(hop2.learn(a, 42));
    CHECK(hop2.learn(b, 7));
    CHECK(hop2.learn(a, 7));
    CHECK(hop2.learn(a, 42));
    CHECK(d1 == hop2.digest());

    return test_done("point-1 router and sparse Hopfield layer");
}
