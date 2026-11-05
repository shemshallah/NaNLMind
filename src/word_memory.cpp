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
    tokens_bin_ = store_->create(n, n);
    if (tokens_bin_ == kInvalidBin) return false;
    for (std::uint16_t i = 0; i < n; ++i) {
        std::vector<std::int16_t> one_hot(n, 0);
        one_hot[i] = 1;
        if (!store_->write(tokens_bin_, i, one_hot)) return false;
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
    std::vector<std::int16_t> q(token_names_.size(), 0);
    for (const auto& token : query) {
        const auto slot = slot_for(token);
        if (!slot) return std::nullopt;
        q[*slot] = 1;
    }
    const auto hits = memory_.recall(q, 32);
    for (const auto& hit : hits) {
        const AssocEntry* entry = memory_.get(hit.id);
        if (!entry || entry->label != static_cast<std::uint64_t>(relation)) continue;
        if (hit.score < static_cast<std::int64_t>(entry->keys.size())) continue;
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

bool WordMemory::answer_yes(const std::string& entity,
                            const std::string& ability) const {
    const auto kind = kind_of(entity);
    if (!kind) return false;
    const auto can = can_of(*kind);
    if (!can || *can != ability) return false;
    const auto cannot = cannot_of(entity);
    return !(cannot && *cannot == ability);
}

} // namespace nanlm
