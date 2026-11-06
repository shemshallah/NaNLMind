#pragma once

#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

enum class EndpointId : std::uint8_t {
    Bootstrap = 0,
    MyAndroid = 1,
    HermesDemo = 2,
    ClockedDemo = 3,
    Count = 4
};

enum class EndpointIngestResult : std::uint8_t {
    Accepted,
    Duplicate,
    StaleGeneration,
    Invalid
};

struct EndpointObservation {
    EndpointId endpoint = EndpointId::Bootstrap;
    std::uint64_t base_generation = 0;
    std::string event_id; // lowercase SHA-256 hex; stable across retries
    std::vector<std::uint8_t> active_heads;
    bool outcome_verified = false;
    bool correct = false;
};

struct EndpointEvidenceStats {
    std::uint64_t observations = 0;
    std::uint64_t verified = 0;
    std::uint64_t correct = 0;
    std::uint64_t wrong = 0;
    std::uint64_t evidence_only = 0;
};

// Overbootstrap's cross-endpoint evidence fold. It stores summaries, not
// endpoint model state. Only independently verified outcomes affect head
// reliability; unverified observations remain evidence-only.
class EndpointEvidenceFold {
public:
    EndpointIngestResult observe(const EndpointObservation& observation);
    bool advance_generation(std::uint64_t next_generation);

    std::uint64_t generation() const { return generation_; }
    EndpointEvidenceStats stats(EndpointId endpoint) const;
    std::array<std::int16_t, 256> feedback() const;
    std::uint64_t unique_events() const { return event_ids_.size(); }
    Hash256 digest() const;

private:
    static constexpr std::size_t kEndpointCount =
        static_cast<std::size_t>(EndpointId::Count);

    std::uint64_t generation_ = 0;
    std::array<EndpointEvidenceStats, kEndpointCount> stats_{};
    std::array<std::int32_t, 256> head_evidence_{};
    std::vector<std::string> event_ids_;
};

} // namespace nanlm
