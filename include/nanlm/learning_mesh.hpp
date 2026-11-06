// Two-rate learning mesh: bootstrap learns fast token/slot associations;
// overbootstrap learns slower head-reliability meta-state and feeds bounded
// routing bias back into bootstrap. The two layers use different math.
#pragma once

#include "nanlm/bootstrap_router.hpp"
#include "nanlm/endpoint_evidence.hpp"

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
    EndpointIngestResult observe_endpoint(const EndpointObservation& observation);
    EndpointEvidenceStats endpoint_stats(EndpointId endpoint) const;
    std::array<std::int16_t, 256> feedback() const;
    std::int32_t evidence(std::uint8_t head) const;
    std::uint64_t traces() const { return traces_; }
    Hash256 digest() const;

private:
    std::array<std::int32_t, 256> evidence_{};
    std::array<std::uint64_t, 256> correct_{};
    std::array<std::uint64_t, 256> wrong_{};
    std::uint64_t traces_ = 0;
    EndpointEvidenceFold endpoint_evidence_;
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

// Simple order-1 count expert used as a routing alternative to Hopfield.
class ByteBigram {
public:
    void train(const std::vector<std::uint8_t>& data, std::size_t begin, std::size_t end);
    std::uint8_t predict(std::uint8_t previous) const;
    Hash256 digest() const;

private:
    std::array<std::array<std::uint32_t, 256>, 256> counts_{};
};

// Overbootstrap chooses among lower-level experts from evidence, not from a
// hard-coded preference.
class ExpertRouter {
public:
    void observe(std::uint8_t expert, bool correct);
    std::uint8_t choose() const;
    std::uint64_t total(std::uint8_t expert) const;
    Hash256 digest() const;

private:
    std::array<std::uint64_t, 2> success_{};
    std::array<std::uint64_t, 2> total_{};
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
