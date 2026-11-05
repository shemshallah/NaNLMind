#include "nanlm/hypervector.hpp"
#include "test_util.hpp"

#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::string entity(std::uint32_t e) { return "entity" + std::to_string(e); }
std::string kind(std::uint32_t k) { return "kind" + std::to_string(k); }
std::uint32_t hash_subject(const std::string& s) {
    std::uint32_t h = 2166136261u;
    for (unsigned char c : s) { h ^= c; h *= 16777619u; }
    return h;
}
} // namespace

int main() {
    constexpr std::uint32_t kEntities = 20000;
    constexpr std::uint32_t kKinds = 256;
    constexpr std::uint32_t kShards = 1024;
    HyperTripleStore global;
    std::vector<HyperTripleStore> shards(kShards);

    for (std::uint32_t k = 0; k < kKinds; ++k) {
        global.add(kind(k), "can", "ability0");
    }
    std::uint32_t exceptions = 0;
    for (std::uint32_t e = 0; e < kEntities; ++e) {
        const std::string s = entity(e);
        const std::string k = kind((e * 37u + 11u) % kKinds);
        global.add(s, "isa", k);
        auto& shard = shards[hash_subject(s) % kShards];
        shard.register_item(k);
        shard.register_item("ability0");
        shard.add(s, "isa", k);
        if (e % 7 == 0) {
            global.add(s, "cannot", "ability0");
            shards[hash_subject(s) % kShards].add(s, "cannot", "ability0");
            ++exceptions;
        }
    }

    std::uint32_t shard_correct = 0, shard_total = 0;
    for (std::uint32_t q = 0; q < 2000; ++q) {
        const std::uint32_t e = (q * 97u + 3u) % kEntities;
        const std::string s = entity(e);
        const std::string expected = kind((e * 37u + 11u) % kKinds);
        const auto& store = shards[hash_subject(s) % kShards];
        if (store.query(s, "isa") == expected) ++shard_correct;
        ++shard_total;
    }

    std::uint32_t global_correct = 0, global_total = 0;
    for (std::uint32_t q = 0; q < 100; ++q) {
        const std::uint32_t e = (q * 97u + 3u) % kEntities;
        const std::string s = entity(e);
        const std::string expected = kind((e * 37u + 11u) % kKinds);
        if (global.query(s, "isa") == expected) ++global_correct;
        ++global_total;
    }

    const double shard_acc = static_cast<double>(shard_correct) / shard_total;
    const double global_acc = static_cast<double>(global_correct) / global_total;
    std::cout << "hyper-scale entities=" << kEntities
              << " exceptions=" << exceptions
              << " shards=" << kShards
              << " shard_top1=" << shard_acc
              << " global_top1=" << global_acc << "\n";
    CHECK_EQ(shard_total, 2000u);
    CHECK(shard_acc >= 0.80);
    return test_done("hypervector 20k split");
}
