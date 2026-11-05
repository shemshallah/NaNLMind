// Word-level relational memory on top of addressable vector bins.
//
// This is the bridge between the vector bank and the fixed logic challenge:
//
//   token -> one-hot vector -> macro key -> association -> value token
//
// The relation extraction is intentionally explicit. This layer proves that the
// bins can carry a word-level memory and answer a held-out entity query; it does
// not claim that the byte model learned the rules.
#pragma once

#include "nanlm/vector_store.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

enum class WordRelation : std::uint64_t {
    Isa = 1,
    Can = 2,
    Cannot = 3,
};

class WordMemory {
public:
    explicit WordMemory(BinStore& store) : store_(&store), memory_(store) {}

    bool build(const std::string& corpus);
    bool answer_yes(const std::string& entity, const std::string& ability) const;
    // Definite answer only when the entity/kind chain has a usable can/cannot
    // relation; nullopt means the word memory does not know.
    std::optional<bool> answer(const std::string& entity, const std::string& ability) const;

    std::size_t vocab() const { return token_names_.size(); }
    std::uint16_t vector_dim() const { return vector_dim_; }
    std::size_t associations() const { return memory_.size(); }
    std::uint32_t bin_id() const { return tokens_bin_; }

    std::optional<std::string> kind_of(const std::string& entity) const;
    std::optional<std::string> can_of(const std::string& kind) const;
    std::optional<std::string> cannot_of(const std::string& entity) const;

private:
    std::optional<std::string> lookup(WordRelation relation,
                                      const std::vector<std::string>& query) const;
    std::optional<std::uint16_t> slot_for(const std::string& token) const;
    bool add_relation(WordRelation relation, const std::vector<std::string>& keys,
                      const std::string& value);

    BinStore* store_;
    BinId tokens_bin_ = kInvalidBin;
    std::uint16_t vector_dim_ = 0;
    std::vector<std::string> token_names_;
    std::unordered_map<std::string, std::uint16_t> token_slots_;
    AssocMemory memory_;
};

} // namespace nanlm
