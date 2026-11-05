#include "nanlm/word_memory.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>

namespace nanlm {

namespace {

std::vector<std::string> tokenize(const std::string& text) {
    std::vector<std::string> out;
    std::string word;
    for (char ch : text) {
        const unsigned char u = static_cast<unsigned char>(ch);
        if (std::isalnum(u) || ch == '\'') {
            word.push_back(static_cast<char>(std::tolower(u)));
        } else if (!word.empty()) {
            out.push_back(word);
            word.clear();
        }
    }
    if (!word.empty()) out.push_back(word);
    return out;
}

std::uint32_t fnv1a(const std::string& text) {
    std::uint32_t h = 2166136261u;
    for (unsigned char c : text) {
        h ^= c;
        h *= 16777619u;
    }
    return h;
}

void add_cooc(std::vector<std::int32_t>& v, const std::string& token,
              std::size_t base, std::size_t dim, std::int32_t weight) {
    if (dim <= base) return;
    const std::uint32_t h = fnv1a(token);
    const std::size_t index = base + h % (dim - base);
    const std::int32_t sign = (h & 0x80000000u) ? -1 : 1;
    v[index] += sign * weight;
}

std::vector<std::vector<std::string>> sentences(const std::string& text) {
    std::vector<std::vector<std::string>> out;
    std::string current;
    for (char ch : text) {
        if (ch == '.' || ch == '?' || ch == '!' || ch == '\n') {
            const auto tokens = tokenize(current);
            if (!tokens.empty()) out.push_back(tokens);
            current.clear();
        } else {
            current.push_back(ch);
        }
    }
    const auto tokens = tokenize(current);
    if (!tokens.empty()) out.push_back(tokens);
    return out;
}

} // namespace

bool WordMemory::build(const std::string& corpus) {
    memory_ = AssocMemory(*store_);
    token_names_.clear();
    token_slots_.clear();

    const auto lines = sentences(corpus);
    for (const auto& tokens : lines) {
        for (const auto& token : tokens) {
            if (token_slots_.find(token) == token_slots_.end()) {
                const auto slot = static_cast<std::uint16_t>(token_names_.size());
                token_slots_[token] = slot;
                token_names_.push_back(token);
            }
        }
    }
    if (token_names_.empty() || token_names_.size() > 65535u) return false;

    const auto n = static_cast<std::uint16_t>(token_names_.size());
    if (n >= 65535u) return false;
    vector_dim_ = static_cast<std::uint16_t>(std::max<std::size_t>(64, n + 32));
    tokens_bin_ = store_->create(vector_dim_, n);
    if (tokens_bin_ == kInvalidBin) return false;

    // One unique anchor coordinate per token keeps exact identity; the tail
    // coordinates hold small co-occurrence/random-index contributions from a
    // two-word window. Same token => same anchor; neighbours => distributed
    // context.
    for (std::uint16_t i = 0; i < n; ++i) {
        std::vector<std::int32_t> v(vector_dim_, 0);
        v[i] += 4096;
        for (const auto& tokens : lines) {
            for (std::size_t p = 0; p < tokens.size(); ++p) {
                if (tokens[p] != token_names_[i]) continue;
                for (std::size_t d = 1; d <= 2; ++d) {
                    if (p >= d) add_cooc(v, tokens[p - d], n, vector_dim_, 1);
                    if (p + d < tokens.size()) add_cooc(v, tokens[p + d], n, vector_dim_, 1);
                }
            }
        }
        std::vector<std::int16_t> out(vector_dim_, 0);
        for (std::size_t k = 0; k < vector_dim_; ++k) {
            if (v[k] > 32767) v[k] = 32767;
            if (v[k] < -32768) v[k] = -32768;
            out[k] = static_cast<std::int16_t>(v[k]);
        }
        if (!store_->write(tokens_bin_, i, out)) return false;
    }

    for (const auto& t : lines) {
        if (t.size() >= 4 && t[1] == "is" && (t[2] == "a" || t[2] == "an")) {
            if (!add_relation(WordRelation::Isa, {t[0], "is", t[2]}, t[3])) return false;
        } else if (t.size() >= 3 && t[1] == "can") {
            if (!add_relation(WordRelation::Can, {t[0], "can"}, t[2])) return false;
        } else if (t.size() >= 3 && t[1] == "cannot") {
            if (!add_relation(WordRelation::Cannot, {t[0], "cannot"}, t[2])) return false;
        }
    }
    return true;
}

std::optional<std::uint16_t> WordMemory::slot_for(const std::string& token) const {
    const auto it = token_slots_.find(token);
    if (it == token_slots_.end()) return std::nullopt;
    return it->second;
}

bool WordMemory::add_relation(WordRelation relation,
                              const std::vector<std::string>& keys,
                              const std::string& value) {
    const auto value_slot = slot_for(value);
    if (!value_slot) return false;
    std::vector<BinRef> key_refs;
    key_refs.reserve(keys.size());
    for (const auto& key : keys) {
        const auto slot = slot_for(key);
        if (!slot) return false;
        key_refs.push_back(BinRef{tokens_bin_, *slot});
    }
    const BinRef value_ref{tokens_bin_, *value_slot};
    return memory_.bind(key_refs, {value_ref}, 65536,
                        static_cast<std::uint64_t>(relation)) != 0;
}

std::optional<std::string> WordMemory::lookup(
    WordRelation relation, const std::vector<std::string>& query) const {
    std::vector<std::int32_t> q32(vector_dim_, 0);
    for (const auto& token : query) {
        const auto slot = slot_for(token);
        if (!slot) return std::nullopt;
        std::vector<std::int16_t> v;
        if (!store_->read(tokens_bin_, *slot, v)) return std::nullopt;
        for (std::size_t i = 0; i < vector_dim_ && i < v.size(); ++i) {
            q32[i] += v[i];
        }
    }
    std::vector<std::int16_t> q(vector_dim_, 0);
    for (std::size_t i = 0; i < vector_dim_; ++i) {
        if (q32[i] > 32767) q32[i] = 32767;
        if (q32[i] < -32768) q32[i] = -32768;
        q[i] = static_cast<std::int16_t>(q32[i]);
    }
    const auto hits = memory_.recall(q, 32);
    for (const auto& hit : hits) {
        const AssocEntry* entry = memory_.get(hit.id);
        if (!entry || entry->label != static_cast<std::uint64_t>(relation)) continue;
        if (hit.score < static_cast<std::int64_t>(entry->keys.size()) * 12000000) continue;
        if (entry->values.empty()) continue;
        const auto slot = entry->values.front().slot;
        if (slot >= token_names_.size()) continue;
        return token_names_[slot];
    }
    return std::nullopt;
}

std::optional<std::string> WordMemory::kind_of(const std::string& entity) const {
    return lookup(WordRelation::Isa, {entity, "is", "a"});
}

std::optional<std::string> WordMemory::can_of(const std::string& kind) const {
    return lookup(WordRelation::Can, {kind, "can"});
}

std::optional<std::string> WordMemory::cannot_of(const std::string& entity) const {
    return lookup(WordRelation::Cannot, {entity, "cannot"});
}

std::optional<bool> WordMemory::answer(const std::string& entity,
                                      const std::string& ability) const {
    // Follow the kind chain (entity -> kind -> superkind...) and let the
    // nearest/any explicit exception win. This handles nested exceptions such
    // as emperor -> penguin -> bird with "penguin cannot fly".
    std::vector<std::string> chain;
    std::string current = entity;
    for (int depth = 0; depth < 8; ++depth) {
        const auto kind = kind_of(current);
        if (!kind) break;
        bool seen = false;
        for (const auto& c : chain) if (c == *kind) { seen = true; break; }
        if (seen) break;
        chain.push_back(*kind);
        current = *kind;
    }

    bool can = false;
    bool known = false;
    for (const auto& node : chain) {
        if (cannot_of(node) && *cannot_of(node) == ability) return false;
        if (can_of(node) && *can_of(node) == ability) {
            can = true;
            known = true;
        }
    }
    if (cannot_of(entity) && *cannot_of(entity) == ability) return false;
    if (can_of(entity) && *can_of(entity) == ability) {
        can = true;
        known = true;
    }
    if (!known) return std::nullopt;
    return can;
}

bool WordMemory::answer_yes(const std::string& entity,
                            const std::string& ability) const {
    return answer(entity, ability).value_or(false);
}

} // namespace nanlm
