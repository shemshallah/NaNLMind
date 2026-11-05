// Growth and consolidation.
//
// Growth: a head materializes a child chart when its self-model error stays
// high for a configured streak, or when its scratchpad high-water mark exceeds
// a threshold.
//
// Consolidation: replay the community scratch into a COW workspace, verify the
// R17 base hash, commit exactly one ledger event, and flip the manifest only
// after the page replacement succeeds. A stale workspace is rejected. A
// duplicate journal id is an idempotent no-op.
#pragma once

#include "nanlm/ledger.hpp"
#include "nanlm/pager.hpp"
#include "nanlm/universe.hpp"

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace nanlm {

inline constexpr std::uint8_t kEventChart = 2;
inline constexpr std::uint8_t kEventGrowth = 4;
inline constexpr std::uint8_t kEventConsolidate = 5;

struct Manifest {
    std::uint64_t generation = 0;
    PageId page{};
    Hash256 base{};
    Hash256 root{};
    std::uint64_t epoch = 0;
    std::vector<PageId> pages;

    Hash256 digest() const;
};

class ManifestStore {
public:
    void reset(const PageId& root_page, const Hash256& root_hash);
    bool restore(const Manifest& manifest);
    Manifest snapshot() const;
    bool publish(Manifest next, std::uint64_t expected_generation);
    std::uint64_t generation() const;

private:
    mutable std::mutex mutex_;
    Manifest current_{};
};

enum class ScratchKind : std::uint8_t {
    Chart = 0,
    HeadLocal = 1,
    HeadWork = 2,
};

struct ScratchOp {
    ScratchKind kind = ScratchKind::Chart;
    std::uint8_t head = 0;
    std::uint16_t offset = 0;
    std::vector<std::uint8_t> bytes;
};

struct ScratchJournal {
    std::uint64_t id = 0;
    std::uint64_t epoch = 0; // logical clock tick for the ledger event
    PageId page{};
    Hash256 base{};
    std::vector<ScratchOp> ops;

    Hash256 digest() const;
};

struct ConsolidationResult {
    bool ok = false;
    bool duplicate = false;
    std::string error;
    Hash256 before{};
    Hash256 after{};
    std::uint64_t generation = 0;
};

class ConsolidationEngine {
public:
    ConsolidationEngine(PageTable& pages, Ledger& ledger, ManifestStore& manifests)
        : pages_(&pages), ledger_(&ledger), manifests_(&manifests) {}

    ConsolidationResult consolidate(const ScratchJournal& journal, std::uint8_t actor);

private:
    static bool apply_op(Universe& workspace, const ScratchOp& op, std::string& error);

    PageTable* pages_;
    Ledger* ledger_;
    ManifestStore* manifests_;
    std::unordered_set<std::uint64_t> applied_;
    std::mutex mutex_;
};

struct GrowthPolicy {
    std::uint16_t self_error_threshold = 32768; // 0.5 in Q16.16
    std::uint8_t error_streak_required = 3;
    std::uint16_t scratch_threshold = 768;      // work area high-water mark
    std::uint8_t max_depth = 4;
};

struct GrowthDecision {
    bool grow = false;
    std::uint8_t head = 0;
    PageId chart{};
    PageId child{};
    std::string reason;
};

} // namespace nanlm
