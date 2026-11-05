#include "nanlm/tape_checkpoint.hpp"

namespace nanlm {

TapeCheckpoint TapeCheckpointManager::make(const TuringTape& tape) {
    TapeCheckpoint cp;
    cp.root = tape.digest();
    cp.page_keys = tape.page_keys();
    cp.page_hashes = tape.page_hashes();
    cp.pages = cp.page_keys.size();
    return cp;
}

bool TapeCheckpointManager::commit(GlobalTopology& topology,
                                   const TapeCheckpoint& checkpoint,
                                   std::uint32_t shard, std::uint64_t epoch) {
    topology.commit_shard(shard, epoch, 0, checkpoint.root, checkpoint.root);
    std::string error;
    return topology.journals().verify(&error);
}

} // namespace nanlm
