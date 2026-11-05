// Word-level vector expert: co-occurrence-augmented word bins plus a macro
// association from context word to next-word one-hot value.
#pragma once

#include "nanlm/vector_store.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

class WordVectorLayer {
public:
    static constexpr std::uint16_t kDim = 1024;
    using Vector = std::array<std::int16_t, kDim>;

    explicit WordVectorLayer(BinStore& store) : store_(&store), memory_(store) {}

    bool train(const std::vector<std::string>& tokens);
    std::string predict(const std::string& previous) const;
    std::size_t vocab() const { return names_.size(); }
    std::size_t associations() const { return memory_.size(); }
    Hash256 digest() const;

private:
    std::uint16_t id_for(const std::string& word) const;
    const Vector& word_vector(std::uint16_t id) const;

    BinStore* store_;
    AssocMemory memory_;
    BinId word_bin_ = kInvalidBin;
    BinId value_bin_ = kInvalidBin;
    std::vector<std::string> names_;
    std::unordered_map<std::string, std::uint16_t> ids_;
    std::string fallback_;
    std::vector<Vector> vectors_;
};

} // namespace nanlm
