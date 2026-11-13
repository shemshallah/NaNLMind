#include "nanlm/word_vector.hpp"

#include <algorithm>
#include <cctype>

namespace nanlm {
namespace {
std::uint64_t hash_word(const std::string& word, std::uint64_t salt = 0) {
    std::uint64_t h = 1469598103934665603ull ^ salt;
    for (unsigned char c : word) {
        h ^= c;
        h *= 1099511628211ull;
    }
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdull;
    h ^= h >> 33;
    return h;
}

void add_cooc_tail(std::array<std::int32_t, WordVectorLayer::kDim>& out,
                   const std::string& word, std::size_t base) {
    if (base >= WordVectorLayer::kDim) return;
    const std::uint64_t h = hash_word(word);
    const std::size_t index = base + h % (WordVectorLayer::kDim - base);
    out[index] += 1;
}
} // namespace

std::uint16_t WordVectorLayer::id_for(const std::string& word) const {
    const auto it = ids_.find(word);
    return it == ids_.end() ? 0xFFFFu : it->second;
}

const WordVectorLayer::Vector& WordVectorLayer::word_vector(std::uint16_t id) const {
    return vectors_[id];
}

bool WordVectorLayer::train(const std::vector<std::string>& tokens) {
    if (tokens.size() < 2) return false;
    names_.clear();
    ids_.clear();
    for (const auto& t : tokens) {
        if (ids_.find(t) == ids_.end()) {
            ids_[t] = static_cast<std::uint16_t>(names_.size());
            names_.push_back(t);
        }
    }
    if (names_.empty() || names_.size() >= 65535u) return false;

    std::unordered_map<std::string, std::uint32_t> word_counts;
    for (const auto& t : tokens) ++word_counts[t];
    std::uint32_t best_count = 0;
    for (const auto& kv : word_counts) {
        if (kv.second > best_count || (kv.second == best_count && kv.first < fallback_)) {
            best_count = kv.second;
            fallback_ = kv.first;
        }
    }

    vectors_.assign(names_.size(), Vector{});
    std::vector<std::array<std::int32_t, kDim>> raw(names_.size());
    for (auto& v : raw) v.fill(0);
    for (std::size_t i = 0; i < names_.size(); ++i) {
        // Preserve the exact diagonal identity for vocabularies that fit the
        // vector dimension. Larger vocabularies hash the identity component so
        // the word layer can still rank a full training vocabulary without
        // growing the vector dimension.
        const std::size_t diagonal = i < kDim ? i : hash_word(names_[i]) % kDim;
        raw[i][diagonal] += 512;
    }
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        const auto id = ids_.at(tokens[i]);
        for (std::size_t d = 1; d <= 2; ++d) {
            if (i >= d) add_cooc_tail(raw[id], tokens[i - d], names_.size());
            if (i + d < tokens.size()) add_cooc_tail(raw[id], tokens[i + d], names_.size());
        }
    }
    for (std::size_t i = 0; i < names_.size(); ++i) {
        for (std::size_t k = 0; k < kDim; ++k) {
            raw[i][k] = std::clamp(raw[i][k], -32768, 32767);
            vectors_[i][k] = static_cast<std::int16_t>(raw[i][k]);
        }
    }

    word_bin_ = store_->create(kDim, static_cast<std::uint16_t>(names_.size()));
    value_bin_ = store_->create(static_cast<std::uint16_t>(names_.size()),
                                static_cast<std::uint16_t>(names_.size()));
    if (word_bin_ == kInvalidBin || value_bin_ == kInvalidBin) return false;
    for (std::uint16_t i = 0; i < names_.size(); ++i) {
        if (!store_->write(word_bin_, i, std::vector<std::int16_t>(
                vectors_[i].begin(), vectors_[i].end()))) return false;
        std::vector<std::int16_t> one_hot(names_.size(), 0);
        one_hot[i] = 1;
        if (!store_->write(value_bin_, i, one_hot)) return false;
    }

    std::unordered_map<std::uint64_t, std::uint32_t> counts;
    for (std::size_t i = 1; i < tokens.size(); ++i) {
        const std::uint32_t a = ids_.at(tokens[i - 1]);
        const std::uint32_t b = ids_.at(tokens[i]);
        ++counts[(static_cast<std::uint64_t>(a) << 32) | b];
    }
    for (const auto& kv : counts) {
        const std::uint16_t a = static_cast<std::uint16_t>(kv.first >> 32);
        const std::uint16_t b = static_cast<std::uint16_t>(kv.first & 0xFFFFFFFFu);
        const std::uint32_t weight = std::max<std::uint32_t>(1, std::min<std::uint32_t>(
            kv.second, 65535));
        if (memory_.bind({BinRef{word_bin_, a}}, {BinRef{value_bin_, b}}, weight) == 0) {
            return false;
        }
    }
    return true;
}

std::string WordVectorLayer::predict(const std::string& previous) const {
    const auto ranked = predict_topk(previous, 1);
    return ranked.empty() ? fallback_ : ranked.front();
}

std::vector<std::string> WordVectorLayer::predict_topk(
    const std::string& previous, std::size_t k) const {
    std::vector<std::string> out;
    if (k == 0) return out;
    const std::uint16_t id = id_for(previous);
    if (id == 0xFFFFu) {
        if (!fallback_.empty()) out.push_back(fallback_);
        return out;
    }
    // Rank the entire association table, not just a shortlist. This makes the
    // returned top-k a full learned-vocabulary ranking of the system's own
    // integer scores.
    const auto hits = memory_.recall(
        std::vector<std::int16_t>(vectors_[id].begin(), vectors_[id].end()),
        memory_.size());
    for (const auto& hit : hits) {
        if (hit.values.empty()) continue;
        const BinRef ref = hit.values.front();
        std::vector<std::int16_t> value;
        if (!store_->read(ref.bin, ref.slot, value)) continue;
        const auto it = std::max_element(value.begin(), value.end());
        if (it == value.end()) continue;
        const std::size_t index = static_cast<std::size_t>(it - value.begin());
        if (index >= names_.size()) continue;
        const std::string& candidate = names_[index];
        if (std::find(out.begin(), out.end(), candidate) != out.end()) continue;
        out.push_back(candidate);
        if (out.size() >= k) break;
    }
    if (out.empty() && !fallback_.empty()) out.push_back(fallback_);
    return out;
}

Hash256 WordVectorLayer::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'W', 'V', 'E', 'C', '0', '1'};
    h.update(tag, sizeof(tag));
    h.update(&word_bin_, sizeof(word_bin_));
    h.update(&value_bin_, sizeof(value_bin_));
    for (const auto& n : names_) {
        h.update(n.data(), n.size());
        const char nul = 0;
        h.update(&nul, 1);
    }
    const Hash256 m = memory_.digest();
    h.update(m.data(), m.size());
    return h.final();
}

} // namespace nanlm
