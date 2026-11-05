#include "nanlm/bootstrap_router.hpp"

#include <algorithm>
#include <unordered_map>

namespace nanlm {

PointRouter::PointRouter(std::uint16_t point) : point_(point) {}

bool PointRouter::bind(std::uint8_t head, LayerRef ref) {
    if (!ref.valid()) return false;
    routes_[head] = ref;
    return true;
}

bool PointRouter::unbind(std::uint8_t head) {
    routes_[head] = LayerRef{};
    return true;
}

std::optional<LayerRef> PointRouter::resolve(std::uint8_t head) const {
    if (!routes_[head].valid()) return std::nullopt;
    return routes_[head];
}

std::size_t PointRouter::bindings() const {
    std::size_t n = 0;
    for (const auto& r : routes_) if (r.valid()) ++n;
    return n;
}

Hash256 PointRouter::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'R', 'O', 'U', 'T', 'E', '1'};
    h.update(tag, sizeof(tag));
    h.update(&point_, sizeof(point_));
    for (const auto& r : routes_) h.update(&r, sizeof(r));
    return h.final();
}

HopfieldRouter::HopfieldRouter(HopfieldConfig config) : config_(config) {
    if (config_.top_k == 0) config_.top_k = 1;
    if (config_.max_strength <= 0) config_.max_strength = 1;
    slots_.resize(kMirrorPairCount);
}

void HopfieldRouter::set_head(std::uint8_t head, const Vector& vector) {
    heads_[head] = vector;
}

const HopfieldRouter::Vector& HopfieldRouter::head(std::uint8_t head) const {
    return heads_[head];
}

const HopfieldRouter::Slot& HopfieldRouter::slot(std::uint32_t pair) const {
    if (pair >= slots_.size()) return slots_[0];
    return slots_[pair];
}

std::int64_t HopfieldRouter::dot(const Vector& a, const Vector& b) const {
    std::int64_t total = 0;
    for (std::size_t i = 0; i < kDim; ++i) {
        total += static_cast<std::int64_t>(a[i]) * b[i];
    }
    return total;
}

std::vector<std::uint8_t> HopfieldRouter::active_heads(const Vector& query) const {
    std::vector<std::pair<std::int64_t, std::uint8_t>> scored;
    scored.reserve(256);
    for (std::uint32_t h = 0; h < 256; ++h) {
        scored.emplace_back(dot(query, heads_[h]), static_cast<std::uint8_t>(h));
    }
    std::sort(scored.begin(), scored.end(), [](const auto& a, const auto& b) {
        if (a.first != b.first) return a.first > b.first;
        return a.second < b.second;
    });
    const std::size_t k = std::min<std::size_t>(config_.top_k, scored.size());
    std::vector<std::uint8_t> active;
    active.reserve(k);
    for (std::size_t i = 0; i < k; ++i) active.push_back(scored[i].second);
    return active;
}

std::vector<std::uint32_t> HopfieldRouter::active_pairs(
    const std::vector<std::uint8_t>& active) const {
    std::vector<std::uint8_t> seen(kMirrorPairCount, 0);
    std::vector<std::uint32_t> pairs;
    for (std::uint8_t a : active) {
        for (std::uint32_t b = 0; b < 256; ++b) {
            if (b == a) continue;
            const std::uint32_t p = pair_index(a, static_cast<std::uint8_t>(b));
            if (p >= kMirrorPairCount || seen[p]) continue;
            seen[p] = 1;
            pairs.push_back(p);
        }
    }
    return pairs;
}

std::uint32_t HopfieldRouter::new_pair(
    const std::vector<std::uint8_t>& active) const {
    if (active.empty()) return kMirrorPairCount;
    if (active.size() >= 2) return pair_index(active[0], active[1]);
    const std::uint8_t other = static_cast<std::uint8_t>((active[0] + 1u) & 0xFFu);
    return pair_index(active[0], other);
}

std::int16_t HopfieldRouter::clamp_strength(std::int64_t value) const {
    if (value > config_.max_strength) return config_.max_strength;
    if (value < -config_.max_strength) return static_cast<std::int16_t>(-config_.max_strength);
    return static_cast<std::int16_t>(value);
}

HopfieldPrediction HopfieldRouter::predict(const Vector& query) const {
    HopfieldPrediction result;
    result.active = active_heads(query);
    const auto pairs = active_pairs(result.active);
    std::unordered_map<std::uint32_t, std::int64_t> votes;
    for (std::uint32_t p : pairs) {
        const Slot& s = slots_[p];
        if (!s.used) continue;
        const std::int64_t score = dot(query, s.key) * s.strength;
        votes[s.value] += score;
    }
    if (votes.empty()) return result;
    std::uint32_t best_token = 0;
    std::int64_t best_score = 0;
    bool have = false;
    for (const auto& kv : votes) {
        if (!have || kv.second > best_score ||
            (kv.second == best_score && kv.first < best_token)) {
            best_token = kv.first;
            best_score = kv.second;
            have = true;
        }
    }
    if (!have || best_score <= 0) return result;
    result.abstain = false;
    result.token = best_token;
    result.score = best_score;
    return result;
}

bool HopfieldRouter::learn(const Vector& query, std::uint32_t target) {
    const HopfieldPrediction old = predict(query);
    const auto active = active_heads(query);
    if (active.empty()) return false;
    const auto pairs = active_pairs(active);
    ++epoch_;

    if (!old.abstain && old.token == target) {
        // Strengthen the best matching target slot among the active pairs.
        std::uint32_t best_pair = kMirrorPairCount;
        std::int64_t best_dot = 0;
        for (std::uint32_t p : pairs) {
            if (!slots_[p].used || slots_[p].value != target) continue;
            const std::int64_t d = dot(query, slots_[p].key);
            if (best_pair == kMirrorPairCount || d > best_dot ||
                (d == best_dot && p < best_pair)) {
                best_pair = p;
                best_dot = d;
            }
        }
        if (best_pair == kMirrorPairCount) return false;
        Slot& s = slots_[best_pair];
        s.strength = clamp_strength(static_cast<std::int64_t>(s.strength) + 1);
        for (std::size_t i = 0; i < kDim; ++i) {
            const std::int32_t next =
                (static_cast<std::int32_t>(s.key[i]) * 99 + query[i]) / 100;
            s.key[i] = static_cast<std::int16_t>(std::max(-32768, std::min(32767, next)));
        }
        s.epoch = epoch_;
        return true;
    }

    // Wrong or abstain: decay active evidence, then overwrite the weakest slot.
    std::uint32_t weakest = kMirrorPairCount;
    for (std::uint32_t p : pairs) {
        Slot& s = slots_[p];
        if (!s.used) continue;
        s.strength = clamp_strength(static_cast<std::int64_t>(s.strength) - 1);
        if (weakest == kMirrorPairCount ||
            s.strength < slots_[weakest].strength ||
            (s.strength == slots_[weakest].strength &&
             s.epoch < slots_[weakest].epoch) ||
            (s.strength == slots_[weakest].strength &&
             s.epoch == slots_[weakest].epoch && p < weakest)) {
            weakest = p;
        }
    }

    if (weakest == kMirrorPairCount) {
        weakest = new_pair(active);
        if (weakest >= kMirrorPairCount) return false;
    }
    Slot& s = slots_[weakest];
    if (!s.used) ++used_slots_;
    s.used = true;
    s.key = query;
    s.value = target;
    s.strength = 1;
    s.epoch = epoch_;
    return true;
}

Hash256 HopfieldRouter::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'H', 'O', 'P', 'F', '1', ' '};
    h.update(tag, sizeof(tag));
    h.update(&config_, sizeof(config_));
    h.update(heads_.data(), heads_.size() * sizeof(Vector));
    for (const Slot& s : slots_) {
        if (!s.used) continue;
        h.update(&s, sizeof(s));
    }
    return h.final();
}

} // namespace nanlm
