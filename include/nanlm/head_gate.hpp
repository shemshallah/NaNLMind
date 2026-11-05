// A learned Boolean head used as a 32-lane relation gate.
#pragma once

#include "nanlm/head.hpp"

#include <cstdint>

namespace nanlm {

class HeadGate {
public:
    HeadGate(HeadArray& heads, std::uint8_t index) : head_(heads.at(index)) {}

    // Learn one of the 16 Boolean functions from all four input pairs.
    void train(std::uint8_t target, int repetitions = 100);
    std::uint8_t rule() const { return head_.boolean_rule(); }
    std::uint32_t apply(std::uint32_t a, std::uint32_t b) const {
        return NanWord::eval_bool(rule(), a, b);
    }
    bool patch(std::uint16_t mask) { return head_.self_modify_boolean(mask); }
    std::uint16_t mask() const { return head_.boolean_mask(); }

private:
    HeadView head_;
};

} // namespace nanlm
