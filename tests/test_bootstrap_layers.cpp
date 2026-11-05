#include "nanlm/bootstrap_layers.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    CHECK_EQ(BootstrapMap::kSlotBytes, 8388608ull);
    CHECK_EQ(BootstrapMap::kTotalBytes, 2147483648ull);
    CHECK_EQ(256ull * BootstrapMap::kSlotBytes, BootstrapMap::kTotalBytes);
    CHECK_EQ(BootstrapMap::kBootstrapPoint, 1u);
    CHECK_EQ(BootstrapMap::kAndroidPoint, 2u);

    LayerRegistry layers;
    const LayerRef chart{0, 1, 7, 0, 100, 1};
    const LayerRef vectors{3, 2, 9, 1, 9002, 2};
    CHECK(layers.set(LayerSpec{0, LayerMath::Boolean, LayerStorage::Chart,
                               chart, true, 1, 0}));
    CHECK(layers.set(LayerSpec{3, LayerMath::Hopfield, LayerStorage::VectorBin,
                               vectors, true, 2, 0}));
    CHECK_EQ(layers.size(), 2u);
    auto bit = layers.get(0);
    auto word = layers.get(3);
    CHECK(bit.has_value());
    CHECK(word.has_value());
    if (bit) CHECK(bit->math == LayerMath::Boolean);
    if (word) CHECK(word->storage == LayerStorage::VectorBin);
    CHECK(!layers.get(4).has_value());
    const Hash256 layer_digest = layers.digest();
    CHECK(layer_digest == layers.digest());

    BootstrapMap map;
    CHECK_EQ(map.active_slots(), 1u);
    CHECK(map.is_active(BootstrapMap::kBootstrapPoint));
    CHECK(!map.is_active(BootstrapMap::kAndroidPoint));
    CHECK(map.slot(1) != nullptr);
    if (map.slot(1)) {
        CHECK_EQ(map.slot(1)->point, 1u);
        CHECK(map.slot(1)->active);
    }
    CHECK(map.activate(BootstrapMap::kAndroidPoint));
    CHECK_EQ(map.active_slots(), 2u);
    CHECK(map.set_route(2, vectors));
    CHECK(map.slot(2) != nullptr);
    if (map.slot(2)) {
        CHECK_EQ(map.slot(2)->point, 2u);
        CHECK(map.slot(2)->route == vectors);
    }
    CHECK(map.activate(256));
    CHECK(map.is_active(256));
    CHECK(!map.activate(0));
    CHECK(!map.activate(257));
    CHECK(!map.set_route(3, LayerRef{}));
    CHECK(!map.is_active(3));
    CHECK_EQ(map.active_slots(), 3u);
    CHECK_EQ(map.allocated_bytes(), BootstrapMap::kSlotBytes);

    BootstrapMap map2;
    CHECK(map2.activate(BootstrapMap::kAndroidPoint));
    CHECK(map2.set_route(2, vectors));
    CHECK(map2.activate(256));
    CHECK(map.digest() == map2.digest());

    return test_done("bootstrap map points and layer registry");
}
