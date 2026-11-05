#include "nanlm/bootstrap_layers.hpp"

namespace nanlm {

bool LayerRegistry::set(const LayerSpec& spec) {
    layers_[spec.layer] = spec;
    return true;
}

bool LayerRegistry::remove(std::uint8_t layer) {
    layers_[layer] = LayerSpec{};
    return true;
}

std::optional<LayerSpec> LayerRegistry::get(std::uint8_t layer) const {
    if (!layers_[layer].active) return std::nullopt;
    return layers_[layer];
}

std::size_t LayerRegistry::size() const {
    std::size_t n = 0;
    for (const auto& l : layers_) if (l.active) ++n;
    return n;
}

Hash256 LayerRegistry::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'L', 'A', 'Y', 'E', 'R', '1'};
    h.update(tag, sizeof(tag));
    for (const auto& l : layers_) {
        if (!l.active) continue;
        h.update(&l, sizeof(l));
    }
    return h.final();
}

BootstrapMap::BootstrapMap() {
    for (std::uint16_t p = 1; p <= kSlotCount; ++p) {
        SystemSlot& s = slots_[index_of(p)];
        s.point = p;
    }
    activate(kBootstrapPoint);
}

std::size_t BootstrapMap::index_of(std::uint16_t point) {
    if (point < 1 || point > kSlotCount) return kSlotCount;
    return static_cast<std::size_t>(point - 1);
}

bool BootstrapMap::activate(std::uint16_t point, std::uint8_t flags) {
    const std::size_t i = index_of(point);
    if (i >= kSlotCount) return false;
    slots_[i].active = true;
    slots_[i].flags = flags;
    return true;
}

bool BootstrapMap::deactivate(std::uint16_t point) {
    const std::size_t i = index_of(point);
    if (i >= kSlotCount) return false;
    slots_[i].active = false;
    return true;
}

bool BootstrapMap::bump_generation(std::uint16_t point, std::uint64_t epoch) {
    const std::size_t i = index_of(point);
    if (i >= kSlotCount || !slots_[i].active) return false;
    ++slots_[i].generation;
    slots_[i].epoch = epoch;
    return true;
}

bool BootstrapMap::is_active(std::uint16_t point) const {
    const std::size_t i = index_of(point);
    return i < kSlotCount && slots_[i].active;
}

bool BootstrapMap::set_route(std::uint16_t point, LayerRef route) {
    const std::size_t i = index_of(point);
    if (i >= kSlotCount || !slots_[i].active || !route.valid()) return false;
    slots_[i].route = route;
    ++slots_[i].generation;
    return true;
}

const SystemSlot* BootstrapMap::slot(std::uint16_t point) const {
    const std::size_t i = index_of(point);
    if (i >= kSlotCount) return nullptr;
    return &slots_[i];
}

std::size_t BootstrapMap::active_slots() const {
    std::size_t n = 0;
    for (const auto& s : slots_) if (s.active) ++n;
    return n;
}

bool HeadStore::write_head(std::uint16_t head,
                           const HopfieldRouter::Vector& vector) {
    if (!map_ || !runner_ || head >= kOverbootstrapHeadCount) return false;
    if (!runner_->write_head(*map_, head, 0,
                             reinterpret_cast<const std::uint8_t*>(vector.data()),
                             sizeof(HopfieldRouter::Vector))) {
        return false;
    }
    ++mapped_heads_;
    return true;
}

bool HeadStore::read_head(std::uint16_t head,
                          HopfieldRouter::Vector& vector) const {
    if (!map_ || !runner_ || head >= kOverbootstrapHeadCount) return false;
    return runner_->read_head(*map_, head, 0,
                              reinterpret_cast<std::uint8_t*>(vector.data()),
                              sizeof(HopfieldRouter::Vector));
}

bool HeadStore::write_slots(std::uint16_t head, const HopfieldRouter& router) {
    if (!map_ || !runner_ || head >= kOverbootstrapHeadCount) return false;
    std::vector<StoredSlot> slots;
    for (std::uint32_t p = 0; p < kMirrorPairCount; ++p) {
        const auto [a, b] = pair_heads(p);
        if (a != head && b != head) continue;
        const auto& s = router.slot(p);
        if (!s.used) continue;
        if (slots.size() >= kMaxStoredSlots) return false;
        StoredSlot out;
        for (std::size_t i = 0; i < HopfieldRouter::kDim; ++i) out.key[i] = s.key[i];
        out.value = s.value;
        out.strength = s.strength;
        out.used = 1;
        out.epoch = s.epoch;
        slots.push_back(out);
    }
    const std::uint16_t count = static_cast<std::uint16_t>(slots.size());
    if (!runner_->write_head(*map_, head, sizeof(HopfieldRouter::Vector),
                             reinterpret_cast<const std::uint8_t*>(&count),
                             sizeof(count))) {
        return false;
    }
    for (std::size_t i = 0; i < slots.size(); ++i) {
        const std::uint32_t offset = kSlotOffset +
            static_cast<std::uint32_t>(i) * sizeof(StoredSlot);
        if (!runner_->write_head(*map_, head, offset,
                                 reinterpret_cast<const std::uint8_t*>(&slots[i]),
                                 sizeof(StoredSlot))) {
            return false;
        }
    }
    mapped_slots_ += slots.size();
    return true;
}

bool HeadStore::read_slots(std::uint16_t head, const OverbootstrapMap& map,
                           std::vector<StoredSlot>& slots) const {
    if (!runner_ || head >= kOverbootstrapHeadCount) return false;
    std::uint16_t count = 0;
    if (!runner_->read_head(map, head, sizeof(HopfieldRouter::Vector),
                            reinterpret_cast<std::uint8_t*>(&count),
                            sizeof(count))) {
        return false;
    }
    if (count > kMaxStoredSlots) return false;
    slots.assign(count, StoredSlot{});
    for (std::uint16_t i = 0; i < count; ++i) {
        const std::uint32_t offset = kSlotOffset +
            static_cast<std::uint32_t>(i) * sizeof(StoredSlot);
        if (!runner_->read_head(map, head, offset,
                                reinterpret_cast<std::uint8_t*>(&slots[i]),
                                sizeof(StoredSlot))) {
            return false;
        }
    }
    return true;
}

bool HeadStore::write_all(const HopfieldRouter& router) {
    for (std::uint16_t h = 0; h < kOverbootstrapHeadCount; ++h) {
        if (!write_head(h, router.head(static_cast<std::uint8_t>(h)))) return false;
        if (!write_slots(h, router)) return false;
    }
    return true;
}

bool LayerPayloadStore::allocate(std::uint8_t layer, std::uint32_t bytes) {
    if (!map_ || !map_->valid() || bytes == 0) return false;
    if (regions_[layer].valid()) return false;
    const std::uint32_t pages =
        (bytes + kOverbootstrapPageBytes - 1) / kOverbootstrapPageBytes;
    if (next_page_ + pages > kOverbootstrapPages) return false;
    const RegionRef r{next_page_, 0, bytes};
    if (!map_->zero(r)) return false;
    regions_[layer] = r;
    next_page_ += pages;
    ++allocated_;
    return true;
}

bool LayerPayloadStore::write(std::uint8_t layer, std::uint32_t offset,
                              const std::uint8_t* data, std::size_t bytes) {
    if (!map_ || !regions_[layer].valid()) return false;
    return map_->write(regions_[layer], offset, data, bytes);
}

bool LayerPayloadStore::read(std::uint8_t layer, std::uint32_t offset,
                             std::uint8_t* out, std::size_t bytes) const {
    if (!map_ || !regions_[layer].valid()) return false;
    return map_->read(regions_[layer], offset, out, bytes);
}

std::optional<RegionRef> LayerPayloadStore::region(std::uint8_t layer) const {
    if (!regions_[layer].valid()) return std::nullopt;
    return regions_[layer];
}

bool RouteMerger::apply(BootstrapMap& map, PointRouter& router,
                        const RouteDiff& diff, std::string* error) {
    const SystemSlot* slot = map.slot(diff.node);
    if (!slot || !slot->active) {
        if (error) *error = "node inactive";
        return false;
    }
    if (slot->generation != diff.base_generation) {
        if (error) *error = "stale base generation";
        return false;
    }
    for (const RouteDelta& d : diff.entries) {
        if (d.ref.node != diff.node || !d.ref.valid()) {
            if (error) *error = "invalid route node/ref";
            return false;
        }
        if (!router.bind(d.head, d.ref)) {
            if (error) *error = "route bind failed";
            return false;
        }
    }
    if (!map.bump_generation(diff.node, diff.logical_tick)) {
        if (error) *error = "generation bump failed";
        return false;
    }
    return true;
}

Hash256 BootstrapMap::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'B', 'M', 'A', 'P', '0', '1'};
    h.update(tag, sizeof(tag));
    const std::uint64_t total = kTotalBytes;
    h.update(&total, sizeof(total));
    for (const auto& s : slots_) h.update(&s, sizeof(s));
    return h.final();
}

} // namespace nanlm
