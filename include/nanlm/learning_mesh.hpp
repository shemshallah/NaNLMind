// Two-rate learning mesh: bootstrap learns fast token/slot associations;
// overbootstrap learns slower head-reliability meta-state and feeds bounded
// routing bias back into bootstrap. The two layers use different math.
#pragma once

#include "nanlm/bootstrap_router.hpp"

#include <array>
#include <cstdint>
#include <vector>

namespace nanlm {

struct BootstrapTrace {
    std::uint32_t target = 0;
    bool correct = false;
    std::vector<std::uint8_t> active;
};

class OverbootstrapLearner {
public:
    void observe(const BootstrapTrace& trace);
    std::array<std::int16_t, 256> feedback() const;
    std::int32_t evidence(std::uint8_t head) const;
    std::uint64_t traces() const { return traces_; }
    Hash256 digest() const;

private:
    std::array<std::int32_t, 256> evidence_{};
    std::array<std::uint64_t, 256> correct_{};
    std::array<std::uint64_t, 256> wrong_{};
    std::uint64_t traces_ = 0;
};

// L1 hyperparameter learner: a small integer bandit over top-k candidates.
// This is deliberately not Hopfield and not a gradient step.
class HyperparameterLearner {
public:
    static constexpr std::array<std::uint8_t, 5> kCandidates{{1, 2, 4, 8, 16}};

    void observe(std::uint8_t used_top_k, bool correct);
    std::uint8_t best_top_k() const;
    std::int16_t bias_limit() const;
    std::uint64_t samples() const { return samples_; }
    Hash256 digest() const;

private:
    std::array<std::uint64_t, 17> success_{};
    std::array<std::uint64_t, 17> total_{};
    std::uint64_t samples_ = 0;
};

class BootstrapMesh {
public:
    BootstrapMesh(HopfieldConfig config, std::uint8_t top_k_active = 8)
        : bootstrap_(config), top_k_active_(top_k_active) {}

    bool step(const HopfieldRouter::Vector& query, std::uint32_t target);
    HopfieldRouter& bootstrap() { return bootstrap_; }
    const HopfieldRouter& bootstrap() const { return bootstrap_; }
    OverbootstrapLearner& mind() { return mind_; }
    const OverbootstrapLearner& mind() const { return mind_; }

private:
    HopfieldRouter bootstrap_;
    OverbootstrapLearner mind_;
    std::uint8_t top_k_active_;
};

} // namespace nanlm
