// A learned Boolean head used as a 32-lane relation gate.
#pragma once

#include "nanlm/head.hpp"

#include <cstdint>
#include <vector>

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

class HeadGateBank {
public:
    HeadGateBank(HeadArray& heads, std::uint8_t target, std::uint8_t first_head,
                 std::uint8_t replicas = 4);
    void train(int repetitions = 100);
    void observe(std::uint32_t a, std::uint32_t b, std::uint32_t expected);
    std::uint32_t apply(std::uint32_t a, std::uint32_t b) const;
    std::uint8_t selected() const { return selected_; }
    std::uint8_t size() const { return static_cast<std::uint8_t>(gates_.size()); }
    std::uint8_t target() const { return target_; }

private:
    std::uint8_t target_;
    std::uint8_t selected_ = 0;
    std::vector<HeadGate> gates_;
    std::vector<std::uint64_t> score_;
};

} // namespace nanlm
