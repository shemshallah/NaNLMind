#include "nanlm/volume_address.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    const auto bs = bs0_volume_address();
    const auto mc = mc0_volume_address();
    const auto sc = sc0_volume_address();
    const auto gm = gm0_volume_address();

    CHECK(bs.valid());
    CHECK(mc.valid());
    CHECK(sc.valid());
    CHECK(gm.valid());

    // One NaN type at both ends: +sNaN / +sNaN. The raw word stores
    // the far head in BE byte order and the near head in LE byte order.
    CHECK_EQ(bs.word.far_head(), 0x7FF1u);
    CHECK_EQ(bs.word.near_head(), 0x7FF1u);
    CHECK_EQ(bs.word.far_class(), 0u);
    CHECK_EQ(bs.word.near_class(), 0u);

    CHECK_EQ(bs.word.raw, 0x7FF14E1100E8F17FULL);
    CHECK_EQ(mc.word.raw, 0x7FF14E1200D7F17FULL);
    CHECK_EQ(sc.word.raw, 0x7FF14E1300C2F17FULL);
    CHECK_EQ(gm.word.raw, 0x7FF14E1400A9F17FULL);

    CHECK_EQ(bs.path(), std::string("/0x7FF14E1100E8F17F"));
    CHECK_EQ(mc.path(), std::string("/0x7FF14E1200D7F17F"));
    CHECK_EQ(sc.path(), std::string("/0x7FF14E1300C2F17F"));
    CHECK_EQ(gm.path(), std::string("/0x7FF14E1400A9F17F"));

    CHECK_EQ(VolumeAddress::parse(bs.path())->word.raw, bs.word.raw);
    CHECK_EQ(VolumeAddress::parse(mc.path())->word.raw, mc.word.raw);
    CHECK_EQ(VolumeAddress::parse(sc.path())->word.raw, sc.word.raw);
    CHECK_EQ(VolumeAddress::parse(gm.path())->word.raw, gm.word.raw);

    // Shards extend the stable logical namespace without changing its tier.
    const auto mc1 = mc0_volume_address(1);
    const auto mc2 = mc0_volume_address(2);
    CHECK(mc1.valid());
    CHECK(mc2.valid());
    CHECK(mc1.word.raw != mc2.word.raw);
    CHECK_EQ(mc1.tier(), VolumeTier::MC0);
    CHECK_EQ(mc1.shard(), 1u);

    // Reject wrong type, bad magic, unsupported format, bad tier and CRC.
    CHECK(!VolumeAddress{NanWord::make(NanType::QuietPositive,
                                       NanType::QuietPositive, bs.payload())}.valid());
    CHECK(!VolumeAddress{NanWord(bs.word.raw ^ 0x0000000000000100ULL)}.valid());
    CHECK(!VolumeAddress::parse("/0x7FF14E1100E9F17F").has_value());
    CHECK(!VolumeAddress::parse("/0x7FF14E1100E8F17").has_value());
    CHECK(!VolumeAddress::parse("0x7FF14E1100E8F17F").has_value());

    // The volume address is data, not an instruction to execute. Its
    // same-type class nibble is 0 by design.
    CHECK_EQ(bs.word.opcode(), 0u);
    CHECK_EQ(mc.word.opcode(), 0u);
    return test_done("64-bit NaN16 volume identities");
}
