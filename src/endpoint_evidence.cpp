#include "nanlm/endpoint_evidence.hpp"

#include <algorithm>
#include <limits>
#include <vector>

namespace nanlm {
namespace {

bool valid_event_id(const std::string& value) {
    if (value.size() != 64) return false;
    return std::all_of(value.begin(), value.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}

bool valid_endpoint(EndpointId endpoint) {
    return static_cast<std::size_t>(endpoint) <
           static_cast<std::size_t>(EndpointId::Count);
}

void hash_u64(Sha256& hash, std::uint64_t value) {
    std::uint8_t bytes[8];
    for (unsigned i = 0; i < 8; ++i)
        bytes[i] = static_cast<std::uint8_t>((value >> (i * 8)) & 0xffu);
    hash.update(bytes, sizeof(bytes));
}

void hash_u32(Sha256& hash, std::uint32_t value) {
    std::uint8_t bytes[4];
    for (unsigned i = 0; i < 4; ++i)
        bytes[i] = static_cast<std::uint8_t>((value >> (i * 8)) & 0xffu);
    hash.update(bytes, sizeof(bytes));
}

} // namespace

EndpointIngestResult EndpointEvidenceFold::observe(
    const EndpointObservation& observation) {
    if (!valid_endpoint(observation.endpoint) || !valid_event_id(observation.event_id))
        return EndpointIngestResult::Invalid;

    if (event_ids_.find(observation.event_id) != event_ids_.end())
        return EndpointIngestResult::Duplicate;

    if (observation.base_generation != generation_)
        return EndpointIngestResult::StaleGeneration;

    const auto index = static_cast<std::size_t>(observation.endpoint);
    auto& source = stats_[index];
    ++source.observations;
    event_ids_.insert(observation.event_id);

    if (!observation.outcome_verified) {
        ++source.evidence_only;
        return EndpointIngestResult::Accepted;
    }

    ++source.verified;
    if (observation.correct) ++source.correct;
    else ++source.wrong;

    // A head contributes at most once per event. Unverified observations never
    // change head reliability or produce policy feedback.
    std::array<bool, 256> seen{};
    for (std::uint8_t head : observation.active_heads) {
        if (seen[head]) continue;
        seen[head] = true;
        head_evidence_[head] = std::clamp(
            head_evidence_[head] + (observation.correct ? 1 : -1), -1024, 1024);
    }
    return EndpointIngestResult::Accepted;
}

bool EndpointEvidenceFold::advance_generation(std::uint64_t next_generation) {
    if (generation_ == std::numeric_limits<std::uint64_t>::max() ||
        next_generation != generation_ + 1) return false;
    generation_ = next_generation;
    return true;
}

EndpointEvidenceStats EndpointEvidenceFold::stats(EndpointId endpoint) const {
    if (!valid_endpoint(endpoint)) return {};
    return stats_[static_cast<std::size_t>(endpoint)];
}

std::array<std::int16_t, 256> EndpointEvidenceFold::feedback() const {
    std::array<std::int16_t, 256> result{};
    for (std::size_t head = 0; head < result.size(); ++head) {
        result[head] = static_cast<std::int16_t>(
            std::clamp(head_evidence_[head] / 8, -8, 8));
    }
    return result;
}

Hash256 EndpointEvidenceFold::digest() const {
    // Canonical little-endian encoding; never hash C++ structs or padding.
    Sha256 hash;
    const std::uint8_t tag[8] = {'N', 'L', 'E', 'P', 'F', 'O', 'L', 'D'};
    hash.update(tag, sizeof(tag));
    hash_u64(hash, generation_);
    for (const auto& endpoint : stats_) {
        hash_u64(hash, endpoint.observations);
        hash_u64(hash, endpoint.verified);
        hash_u64(hash, endpoint.correct);
        hash_u64(hash, endpoint.wrong);
        hash_u64(hash, endpoint.evidence_only);
    }
    for (std::int32_t value : head_evidence_)
        hash_u32(hash, static_cast<std::uint32_t>(value));

    std::vector<std::string> ids(event_ids_.begin(), event_ids_.end());
    std::sort(ids.begin(), ids.end());
    hash_u64(hash, static_cast<std::uint64_t>(ids.size()));
    for (const auto& id : ids) hash.update(id.data(), id.size());
    return hash.final();
}

} // namespace nanlm
