#pragma once
#include "nanlm/sha256.hpp"
#include <cstdint>
#include <map>
#include <string>
#include <vector>
namespace nanlm {
struct JournalRecord {
    std::uint32_t shard=0;
    std::uint64_t sequence=0, epoch=0;
    std::uint8_t kind=0;
    Hash256 subject{}, payload{}, causal_parent{}, parent{}, hash{};
};
class JournalForest {
public:
    JournalRecord append(std::uint32_t shard,std::uint64_t epoch,std::uint8_t kind,
                         Hash256 subject,Hash256 payload,Hash256 causal_parent={});
    bool verify(std::string* error=nullptr) const;
    Hash256 root() const;
    std::size_t size() const;
    std::vector<JournalRecord> ordered() const;
    std::vector<std::uint8_t> serialize() const;
    static JournalForest from_bytes(const std::uint8_t* data,std::size_t len);
private:
    std::map<std::uint32_t,std::vector<JournalRecord>> shards_;
};
}
