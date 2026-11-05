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
