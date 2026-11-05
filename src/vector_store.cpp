#include "nanlm/vector_store.hpp"

#include <algorithm>
#include <cstring>

namespace nanlm {

BinId BinStore::create(std::uint16_t dim, std::uint16_t count, std::int16_t fill) {
    if (dim == 0 || count == 0) return kInvalidBin;
    Bin bin;
    bin.header.dim = dim;
    bin.header.count = count;
    bin.header.generation = static_cast<std::uint32_t>(bins_.size());
    bin.header.payload_bytes =
        static_cast<std::uint64_t>(dim) * count * sizeof(std::int16_t);
    bin.values.assign(static_cast<std::size_t>(dim) * count, fill);
    bins_.push_back(std::move(bin));
    return static_cast<BinId>(bins_.size() - 1);
}

const BinHeader* BinStore::header(BinId bin) const {
    if (bin == kInvalidBin || bin >= bins_.size()) return nullptr;
    return &bins_[bin].header;
}

const std::int16_t* BinStore::vector(BinId bin, std::uint16_t slot) const {
    const BinHeader* h = header(bin);
    if (!h || slot >= h->count) return nullptr;
    return bins_[bin].values.data() + static_cast<std::size_t>(slot) * h->dim;
}

bool BinStore::write(BinId bin, std::uint16_t slot,
                     const std::vector<std::int16_t>& values) {
    const BinHeader* h = header(bin);
    if (!h || slot >= h->count || values.size() != h->dim) return false;
    auto* dst = bins_[bin].values.data() + static_cast<std::size_t>(slot) * h->dim;
    std::copy(values.begin(), values.end(), dst);
    return true;
}

bool BinStore::read(BinId bin, std::uint16_t slot,
                    std::vector<std::int16_t>& out) const {
    const BinHeader* h = header(bin);
    const std::int16_t* src = vector(bin, slot);
    if (!h || !src) return false;
    out.assign(src, src + h->dim);
    return true;
}

Hash256 BinStore::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'V', 'E', 'C', 'T', '0', '1'};
    h.update(tag, sizeof(tag));
    const std::uint64_t n = bins_.empty() ? 0 : bins_.size() - 1;
    h.update(&n, sizeof(n));
    for (std::size_t i = 1; i < bins_.size(); ++i) {
        const Bin& b = bins_[i];
        h.update(&b.header, sizeof(b.header));
        h.update(b.values.data(), b.values.size() * sizeof(std::int16_t));
    }
    return h.final();
}

bool PointBinMap::bind(std::uint16_t point, BinRef ref) {
    if (!ref.valid()) return false;
    map_[point] = ref;
    return true;
}

bool PointBinMap::unbind(std::uint16_t point) {
    map_[point] = BinRef{};
    return true;
}

BinRef PointBinMap::resolve(std::uint16_t point) const {
    return map_[point];
}

std::size_t PointBinMap::bindings() const {
    std::size_t n = 0;
    for (const BinRef& r : map_) if (r.valid()) ++n;
    return n;
}

std::uint32_t AssocMemory::bind(const std::vector<BinRef>& keys,
                                const std::vector<BinRef>& values,
                                std::uint32_t weight, std::uint64_t label,
                                std::uint64_t epoch) {
    if (keys.empty() || values.empty()) return 0;
    for (const BinRef& r : keys) {
        const BinHeader* h = store_->header(r.bin);
        if (!h || r.slot >= h->count) return 0;
    }
    for (const BinRef& r : values) {
        const BinHeader* h = store_->header(r.bin);
        if (!h || r.slot >= h->count) return 0;
    }
    AssocEntry e;
    e.id = next_id_++;
    e.keys = keys;
    e.values = values;
    e.weight = weight;
    e.label = label;
    e.epoch = epoch;
    entries_.push_back(std::move(e));
    return entries_.back().id;
}

bool AssocMemory::remove(std::uint32_t id) {
    for (auto it = entries_.begin(); it != entries_.end(); ++it) {
        if (it->id == id) {
            entries_.erase(it);
            return true;
        }
    }
    return false;
}

const AssocEntry* AssocMemory::get(std::uint32_t id) const {
    for (const auto& e : entries_) if (e.id == id) return &e;
    return nullptr;
}

std::int64_t AssocMemory::score(const AssocEntry& entry,
                                const std::vector<std::int16_t>& query) const {
    std::int64_t total = 0;
    for (const BinRef& key : entry.keys) {
        const BinHeader* h = store_->header(key.bin);
        const std::int16_t* v = store_->vector(key.bin, key.slot);
        if (!h || !v) continue;
        const std::size_t n = std::min<std::size_t>(query.size(), h->dim);
        for (std::size_t i = 0; i < n; ++i) {
            total += static_cast<std::int64_t>(query[i]) * v[i];
        }
    }
    return total * static_cast<std::int64_t>(entry.weight) / 65536;
}

std::vector<AssocMatch> AssocMemory::recall(
    const std::vector<std::int16_t>& query, std::size_t top_k) const {
    std::vector<AssocMatch> out;
    if (query.empty() || top_k == 0) return out;
    for (const AssocEntry& e : entries_) {
        out.push_back(AssocMatch{e.id, score(e, query), e.values});
    }
    std::sort(out.begin(), out.end(), [](const AssocMatch& a, const AssocMatch& b) {
        if (a.score != b.score) return a.score > b.score;
        return a.id < b.id;
    });
    if (out.size() > top_k) out.resize(top_k);
    return out;
}

std::vector<AssocMatch> AssocMemory::recall_from_head(
    const HeadScratch& scratch, std::uint16_t dim, std::size_t top_k) const {
    std::vector<std::int16_t> query(dim);
    if (dim > 0) {
        std::memcpy(query.data(), scratch.work(),
                    static_cast<std::size_t>(dim) * sizeof(std::int16_t));
    }
    return recall(query, top_k);
}

Hash256 AssocMemory::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'A', 'S', 'S', 'O', 'C', '1'};
    h.update(tag, sizeof(tag));
    const std::uint64_t n = entries_.size();
    h.update(&n, sizeof(n));
    for (const auto& e : entries_) {
        h.update(&e.id, sizeof(e.id));
        h.update(&e.weight, sizeof(e.weight));
        h.update(&e.label, sizeof(e.label));
        h.update(&e.epoch, sizeof(e.epoch));
        for (const BinRef& r : e.keys) h.update(&r, sizeof(r));
        for (const BinRef& r : e.values) h.update(&r, sizeof(r));
    }
    return h.final();
}

} // namespace nanlm
