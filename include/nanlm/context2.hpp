// Context-2 logical layout: 256 child charts, one per previous byte.
//
// Each child chart is a 256x256 count matrix:
//   row    = second context byte
//   column = next byte
//
// The compact implementation below is the logical layout. The topology mapping
// replaces each Slab with one child Universe in the router chart; the math is
// identical.
#pragma once

#include <array>
#include <cstdint>
#include <memory>
#include <vector>

namespace nanlm {

struct Context2Eval {
    std::size_t bytes = 0;
    std::size_t correct = 0;
    double accuracy = 0.0;
    double bits_per_byte = 0.0;
};

class Context2Model {
public:
    Context2Model();

    void train(const std::vector<std::uint8_t>& data);
    void observe(std::uint8_t a, std::uint8_t b, std::uint8_t c, std::uint32_t n = 1);
    std::uint32_t count(std::uint8_t a, std::uint8_t b, std::uint8_t c) const;
    std::uint8_t predict(std::uint8_t a, std::uint8_t b) const;
    double probability(std::uint8_t a, std::uint8_t b, std::uint8_t c) const;
    Context2Eval evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                          std::size_t end) const;

    std::size_t slabs() const;

private:
    struct Slab {
        std::array<std::array<std::uint32_t, 256>, 256> counts{};
        std::array<std::uint32_t, 256> row_total{};
        std::uint64_t total = 0;
    };
    std::array<std::unique_ptr<Slab>, 256> slabs_{};
    std::array<std::array<std::uint32_t, 256>, 256> bigram_{};
    std::array<std::uint32_t, 256> unigram_{};
};

} // namespace nanlm
