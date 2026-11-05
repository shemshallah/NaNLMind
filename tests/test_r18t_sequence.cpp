#include "nanlm/universe.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    Universe u(0x1234);
    const std::uint8_t seq[] = {3, 7, 11, 19, 31};
    const int n = 5;

    // Asymmetric storage: s+ carries forward order, s- reverse order.
    for (int i = 0; i < n; ++i) {
        const std::uint8_t a = seq[i];
        const std::uint8_t b = seq[(i + 1) % n];
        auto& c = u.pair_cell(a, b);
        c.s_plus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive,
                                   static_cast<std::uint32_t>(b));
        c.s_minus() = NanWord::make(NanType::QuietNegative, NanType::QuietNegative,
                                    static_cast<std::uint32_t>(a));
    }

    // Forward and reverse replay both reconstruct the cyclic order.
    for (int i = 0; i < n; ++i) {
        const std::uint8_t a = seq[i];
        const std::uint8_t b = seq[(i + 1) % n];
        CHECK_EQ(u.pair_cell(a, b).s_plus().payload(), static_cast<std::uint32_t>(b));
        CHECK_EQ(u.pair_cell(a, b).s_minus().payload(), static_cast<std::uint32_t>(a));
        // The mirror address is the same shared pair cell; direction lives in
        // the rail, not in a second cell.
        CHECK(u.pair_cell(b, a).s_plus().raw == u.pair_cell(a, b).s_plus().raw);
    }

    // Symmetric control: copy forward into both rails. Reverse order is lost.
    Universe sym(0x1234);
    for (int i = 0; i < n; ++i) {
        const std::uint8_t a = seq[i];
        const std::uint8_t b = seq[(i + 1) % n];
        auto& c = sym.pair_cell(a, b);
        c.s_plus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, b);
        c.s_minus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, b);
    }
    int reverse_matches = 0;
    for (int i = 0; i < n; ++i) {
        const std::uint8_t a = seq[i];
        const std::uint8_t b = seq[(i + 1) % n];
        if (sym.pair_cell(b, a).s_minus().payload() == static_cast<std::uint32_t>(a)) {
            ++reverse_matches;
        }
    }
    CHECK(reverse_matches < n); // symmetric storage cannot replay reverse order

    return test_done("R18T bidirectional sequence storage");
}
