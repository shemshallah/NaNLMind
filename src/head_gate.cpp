#include "nanlm/head_gate.hpp"

namespace nanlm {

HeadGateBank::HeadGateBank(HeadArray& heads, std::uint8_t target,
                           std::uint8_t first_head, std::uint8_t replicas)
    : target_(target) {
    if (replicas == 0) replicas = 1;
    for (std::uint8_t i = 0; i < replicas; ++i) {
        gates_.emplace_back(heads, static_cast<std::uint8_t>(first_head + i));
        score_.push_back(0);
    }
}

void HeadGateBank::train(int repetitions) {
    for (auto& g : gates_) g.train(target_, repetitions);
}

void HeadGateBank::observe(std::uint32_t a, std::uint32_t b,
                           std::uint32_t expected) {
    for (std::size_t i = 0; i < gates_.size(); ++i) {
        if (gates_[i].apply(a, b) == expected) ++score_[i];
    }
    std::uint64_t best = 0;
    for (std::size_t i = 1; i < score_.size(); ++i) {
        if (score_[i] > score_[best]) best = i;
    }
    selected_ = static_cast<std::uint8_t>(best);
}

std::uint32_t HeadGateBank::apply(std::uint32_t a, std::uint32_t b) const {
    if (gates_.empty()) return 0;
    return gates_[selected_].apply(a, b);
}

void HeadGate::train(std::uint8_t target, int repetitions) {
    head_.reset_boolean_learner();
    for (int rep = 0; rep < repetitions; ++rep) {
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                const bool truth = ((target >> (2u * a + b)) & 1u) != 0;
                head_.train_boolean(a, b, truth);
            }
        }
    }
}

} // namespace nanlm
