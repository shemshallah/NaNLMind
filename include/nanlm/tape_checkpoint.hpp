// Ledger link for a Turing tape: page hashes + a tape root committed to the
// sharded journal. This does not yet register pages in the atlas allocator.
#pragma once

#include "nanlm/global.hpp"
#include "nanlm/turing_machine.hpp"

#include <cstdint>
#include <vector>

namespace nanlm {

struct TapeCheckpoint {
    Hash256 root{};
    std::vector<std::int64_t> page_keys;
    std::vector<Hash256> page_hashes;
    std::size_t pages = 0;
};

class TapeCheckpointManager {
public:
    static TapeCheckpoint make(const TuringTape& tape);
    static bool commit(GlobalTopology& topology, const TapeCheckpoint& checkpoint,
                       std::uint32_t shard, std::uint64_t epoch);
};

} // namespace nanlm
