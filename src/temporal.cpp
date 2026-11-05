#include "nanlm/temporal.hpp"

#include <algorithm>
#include <set>

namespace nanlm {

std::uint32_t BidirectionalMemory::link(const Ref& past, const Ref& future,
                                        std::uint64_t epoch, std::uint16_t flags,
                                        std::uint32_t weight) {
    if (past == future) return 0;
    TemporalLink l;
    l.id = next_id_++;
    l.past = past;
    l.future = future;
    l.epoch = epoch;
    l.flags = flags;
    l.weight = weight == 0 ? 65536 : weight;
    forward_index_[past].push_back(l.id);
    backward_index_[future].push_back(l.id);
    links_.emplace(l.id, std::move(l));
    return next_id_ - 1;
}

bool BidirectionalMemory::remove(std::uint32_t id) {
    auto it = links_.find(id);
    if (it == links_.end()) return false;
    auto erase_from = [&](auto& index, const Ref& key) {
        auto jt = index.find(key);
        if (jt == index.end()) return;
        auto& v = jt->second;
        v.erase(std::remove(v.begin(), v.end(), id), v.end());
        if (v.empty()) index.erase(jt);
    };
    erase_from(forward_index_, it->second.past);
    erase_from(backward_index_, it->second.future);
    links_.erase(it);
    return true;
}

bool BidirectionalMemory::forward(const Ref& past, Ref& future,
                                  std::uint64_t at_epoch) const {
    auto it = forward_index_.find(past);
    if (it == forward_index_.end() || it->second.empty()) return false;
    std::uint32_t best = 0;
    std::uint64_t best_epoch = 0;
    for (std::uint32_t id : it->second) {
        auto lit = links_.find(id);
        if (lit == links_.end()) continue;
        if (at_epoch != UINT64_MAX && lit->second.epoch > at_epoch) continue;
        if (best == 0 || lit->second.epoch >= best_epoch) {
            best = id;
            best_epoch = lit->second.epoch;
        }
    }
    if (best == 0) return false;
    future = links_.at(best).future;
    return true;
}

bool BidirectionalMemory::backward(const Ref& future, Ref& past,
                                   std::uint64_t at_epoch) const {
    auto it = backward_index_.find(future);
    if (it == backward_index_.end() || it->second.empty()) return false;
    std::uint32_t best = 0;
    std::uint64_t best_epoch = 0;
    for (std::uint32_t id : it->second) {
        auto lit = links_.find(id);
        if (lit == links_.end()) continue;
        if (at_epoch != UINT64_MAX && lit->second.epoch > at_epoch) continue;
        if (best == 0 || lit->second.epoch >= best_epoch) {
            best = id;
            best_epoch = lit->second.epoch;
        }
    }
    if (best == 0) return false;
    past = links_.at(best).past;
    return true;
}

std::vector<Ref> BidirectionalMemory::futures(const Ref& past) const {
    std::vector<Ref> out;
    std::set<std::string> seen;
    auto it = forward_index_.find(past);
    if (it == forward_index_.end()) return out;
    for (std::uint32_t id : it->second) {
        auto lit = links_.find(id);
        if (lit == links_.end()) continue;
        if (seen.insert(lit->second.future.to_string()).second) out.push_back(lit->second.future);
    }
    return out;
}

std::vector<Ref> BidirectionalMemory::pasts(const Ref& future) const {
    std::vector<Ref> out;
    std::set<std::string> seen;
    auto it = backward_index_.find(future);
    if (it == backward_index_.end()) return out;
    for (std::uint32_t id : it->second) {
        auto lit = links_.find(id);
        if (lit == links_.end()) continue;
        if (seen.insert(lit->second.past.to_string()).second) out.push_back(lit->second.past);
    }
    return out;
}

std::vector<TemporalLink> BidirectionalMemory::links() const {
    std::vector<TemporalLink> out;
    out.reserve(links_.size());
    for (const auto& kv : links_) out.push_back(kv.second);
    std::sort(out.begin(), out.end(), [](const TemporalLink& a, const TemporalLink& b) {
        if (a.epoch != b.epoch) return a.epoch < b.epoch;
        return a.id < b.id;
    });
    return out;
}

std::vector<TemporalLink> BidirectionalMemory::at_epoch(std::uint64_t epoch) const {
    std::vector<TemporalLink> out;
    for (const auto& l : links()) {
        if (l.epoch == epoch) out.push_back(l);
    }
    return out;
}

std::vector<TemporalLink> BidirectionalMemory::between(std::uint64_t begin,
                                                       std::uint64_t end) const {
    std::vector<TemporalLink> out;
    for (const auto& l : links()) {
        if (l.epoch >= begin && l.epoch < end) out.push_back(l);
    }
    return out;
}

Hash256 BidirectionalMemory::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'T', 'I', 'M', 'E', '1'};
    h.update(tag, sizeof(tag));
    for (const auto& l : links()) {
        h.update(&l.id, sizeof(l.id));
        h.update(&l.epoch, sizeof(l.epoch));
        h.update(&l.flags, sizeof(l.flags));
        h.update(&l.weight, sizeof(l.weight));
        for (const Ref* r : {&l.past, &l.future}) {
            const std::uint8_t kind = static_cast<std::uint8_t>(r->kind);
            h.update(&kind, sizeof(kind));
            h.update(&r->flags, sizeof(r->flags));
            h.update(&r->offset, sizeof(r->offset));
            h.update(&r->page.depth, sizeof(r->page.depth));
            h.update(r->page.path.data(), r->page.path.size());
        }
    }
    return h.final();
}

} // namespace nanlm
