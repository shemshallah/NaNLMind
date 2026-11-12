// NLHE2 storage adapter over the canonical 256^3 dual tensor arena.
//
// The arena owns the scalar tensor and the typed-leaf map.  This adapter is
// deliberately thin: it encodes/validates a structural hyperedge and attaches
// it at its declared home point.  Exact replay is a no-op; same-generation
// conflicts and quota failures are reported as statuses, not mutations.
#pragma once
#include "nanlm/dual_tensor_arena.hpp"
#include "nanlm/nlhe2.hpp"

#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {

enum class Nlhe2AttachStatus : std::uint8_t {
    Attached, Superseded, Replayed, Conflict, Stale, Quota, Invalid,
    Unauthorized, NoCandidate, VoidCoordinate
};

struct Nlhe2AttachResult {
    Nlhe2AttachStatus status = Nlhe2AttachStatus::Invalid;
    std::uint64_t generation = 0;
    std::size_t entries_at_point = 0;
};

struct Nlhe2View {
    Nlhe2Record record{};
    std::uint64_t source_generation = 0;
    std::string source_sha256;
};

inline Nlhe2AttachResult attach_nlhe2_candidate(
    DualTensor256Arena& arena, unsigned proposer,
    const Nlhe2Record& record, const std::string& source_sha256) {
    Nlhe2AttachResult result{};
    result.generation = arena.generation();
    if (!record.home.valid()) {
        result.status = Nlhe2AttachStatus::VoidCoordinate;
        return result;
    }
    if (!arena.candidate_open()) {
        result.status = Nlhe2AttachStatus::NoCandidate;
        return result;
    }
    if (!arena.candidate_writer_allowed(record.home.h()) ||
        proposer >= 255u || !arena.candidate_writer_allowed(proposer)) {
        result.status = Nlhe2AttachStatus::Unauthorized;
        return result;
    }
    if (!valid_tensor_leaf_sha256(source_sha256) ||
        validate_nlhe2(record) != Nlhe2Error::None) {
        result.status = Nlhe2AttachStatus::Invalid;
        return result;
    }
    TensorDataLeaf leaf{};
    leaf.kind = TensorLeafKind::HyperedgeRecordV2;
    leaf.logical_leaf_id = record.logical_edge_id;
    leaf.source_generation = arena.generation();
    leaf.source_sha256 = source_sha256;
    try {
        leaf.payload = encode_nlhe2(record);
        const bool inserted = arena.attach_candidate_leaf(
            proposer, record.home.h(), record.home.a(), record.home.b(), leaf);
        result.status = inserted ? Nlhe2AttachStatus::Attached
                                 : Nlhe2AttachStatus::Replayed;
    } catch (const std::length_error&) {
        result.status = Nlhe2AttachStatus::Quota;
    } catch (const std::invalid_argument&) {
        result.status = Nlhe2AttachStatus::Invalid;
    } catch (const std::logic_error& e) {
        const std::string what = e.what();
        if (what.find("conflicting") != std::string::npos)
            result.status = Nlhe2AttachStatus::Conflict;
        else if (what.find("stale") != std::string::npos)
            result.status = Nlhe2AttachStatus::Stale;
        else if (what.find("not authorized") != std::string::npos)
            result.status = Nlhe2AttachStatus::Unauthorized;
        else if (what.find("open") != std::string::npos)
            result.status = Nlhe2AttachStatus::NoCandidate;
        else
            result.status = Nlhe2AttachStatus::Invalid;
    }
    result.generation = arena.generation();
    result.entries_at_point =
        arena.candidate_leaves(record.home.h(), record.home.a(),
                               record.home.b()).size();
    return result;
}

// Newest live NLHE2 revision at a home point.  Candidate and active banks are
// both inspected; an equal-generation payload conflict returns nullopt.
inline std::optional<Nlhe2View> newest_nlhe2(
    const DualTensor256Arena& arena, TensorPointRef home,
    std::uint64_t logical_edge_id) {
    if (!home.valid()) return std::nullopt;
    std::optional<Nlhe2View> best;
    bool ambiguous = false;
    auto consider = [&](const std::vector<TensorDataLeaf>& leaves) {
        for (const auto& leaf : leaves) {
            if (leaf.kind != TensorLeafKind::HyperedgeRecordV2 ||
                leaf.logical_leaf_id != logical_edge_id)
                continue;
            const auto decoded = decode_nlhe2(leaf.payload);
            if (!decoded) continue;
            if (!best || leaf.source_generation > best->source_generation) {
                best = Nlhe2View{decoded.record, leaf.source_generation,
                                 leaf.source_sha256};
                ambiguous = false;
            } else if (leaf.source_generation == best->source_generation &&
                       !(decoded.record == best->record)) {
                ambiguous = true;
            }
        }
    };
    consider(arena.active_leaves(home.h(), home.a(), home.b()));
    if (arena.candidate_open())
        consider(arena.candidate_leaves(home.h(), home.a(), home.b()));
    if (ambiguous) return std::nullopt;
    return best;
}

} // namespace nanlm
