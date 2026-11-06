#include "nanlm/tape_checkpoint.hpp"
#include "nanlm/sha256.hpp"

#include <algorithm>
#include <cstring>

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
        Hash256 key_payload{};
        std::memcpy(key_payload.data(), &key, sizeof(key));
        topology.commit_shard(shard, epoch, kPageKind, checkpoint.page_hashes[i],
                              key_payload, root.hash);
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

std::optional<TapePageIndex> TapeCheckpointManager::load_index(
    const GlobalTopology& topology, const TapeCheckpoint& checkpoint) {
    const auto records = topology.journals().ordered();
    Hash256 journal_root{};
    bool found_root = false;
    for (const auto& record : records) {
        if (record.kind == kRootKind && record.subject == checkpoint.root) {
            journal_root = record.hash;
            found_root = true;
            break;
        }
    }
    if (!found_root) return std::nullopt;
    TapePageIndex index;
    index.root = checkpoint.root;
    for (const auto& record : records) {
        if (record.kind != kPageKind || !(record.causal_parent == journal_root)) continue;
        std::int64_t key = 0;
        std::memcpy(&key, record.payload.data(), sizeof(key));
        if (!index.pages.emplace(key, record.subject).second) return std::nullopt;
    }
    if (index.pages.size() != checkpoint.page_keys.size()) return std::nullopt;
    for (const auto& [key, hash] : index.pages) {
        const auto it = std::find(checkpoint.page_keys.begin(), checkpoint.page_keys.end(), key);
        if (it == checkpoint.page_keys.end()) return std::nullopt;
        const std::size_t pos = static_cast<std::size_t>(it - checkpoint.page_keys.begin());
        if (!(checkpoint.page_hashes[pos] == hash)) return std::nullopt;
    }
    return index;
}

} // namespace nanlm
