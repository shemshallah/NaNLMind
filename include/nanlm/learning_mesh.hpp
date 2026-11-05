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
