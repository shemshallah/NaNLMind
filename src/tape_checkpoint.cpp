#include "nanlm/tape_checkpoint.hpp"
#include "nanlm/sha256.hpp"

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
    const JournalRecord root = topology.commit_shard(
        shard, epoch, kRootKind, checkpoint.root, checkpoint.root);
    for (std::size_t i = 0; i < checkpoint.page_keys.size(); ++i) {
        const std::int64_t key = checkpoint.page_keys[i];
        const Hash256 key_hash = Sha256::hash(
            reinterpret_cast<const std::uint8_t*>(&key), sizeof(key));
        topology.commit_shard(shard, epoch, kPageKind, checkpoint.page_hashes[i],
                              key_hash, root.hash);
    }
    std::string error;
    return topology.journals().verify(&error);
}

std::size_t TapeCheckpointManager::page_records(
    const GlobalTopology& topology, const TapeCheckpoint& checkpoint) {
    (void)checkpoint;
    std::size_t count = 0;
    for (const auto& record : topology.journals().ordered()) {
        if (record.kind == kPageKind) ++count;
    }
    return count;
}

} // namespace nanlm
