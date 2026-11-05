// Byte-level bigram memory stored in the universe's pair cells.
//
// For bytes a,b, pair_cell(a,b).s_plus().payload() is the transition count
// a -> b. Prediction is the argmax count. This is a correctness/equivalence
// gate: the topology must reproduce a host bigram exactly, not beat it.
#pragma once

#include "nanlm/universe.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

struct ByteEval {
    std::size_t bytes = 0;
    std::size_t correct = 0;
    double accuracy = 0.0;
    double bits_per_byte = 0.0;
};

class ByteModel {
public:
    explicit ByteModel(Universe& universe) : universe_(&universe) {}

    void clear();
    void observe(std::uint8_t a, std::uint8_t b, std::uint32_t count = 1);
    std::uint32_t count(std::uint8_t a, std::uint8_t b) const;
    std::uint32_t total(std::uint8_t a) const;
    std::uint8_t predict(std::uint8_t a) const;

    void train(const std::vector<std::uint8_t>& data);
    ByteEval evaluate(const std::vector<std::uint8_t>& data, std::size_t start,
                      std::size_t end) const;

    // Independent host reference with the same counts/predictions.
    static ByteEval reference(const std::vector<std::uint8_t>& train,
                              const std::vector<std::uint8_t>& test);
    static ByteEval order0_reference(const std::vector<std::uint8_t>& train,
                                     const std::vector<std::uint8_t>& test);

private:
    Universe* universe_;
};

} // namespace nanlm
