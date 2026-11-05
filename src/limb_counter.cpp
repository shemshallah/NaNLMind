#include "nanlm/limb_counter.hpp"

#include <algorithm>

namespace nanlm {

std::uint16_t ChartLimbStore::get(std::size_t index) const {
    if (index >= limbs_) return 0;
    return static_cast<std::uint16_t>(
        universe_->address_reg(static_cast<std::uint16_t>(base_ + index)).meta & 0xFFFFu);
}

void ChartLimbStore::set(std::size_t index, std::uint16_t value) {
    if (index >= capacity_) return;
    if (index >= limbs_) limbs_ = index + 1;
    universe_->address_reg(static_cast<std::uint16_t>(base_ + index)).meta = value;
}

bool ChartLimbStore::grow(std::size_t limbs) {
    if (limbs > capacity_) return false;
    const std::size_t old = limbs_;
    if (limbs > limbs_) limbs_ = limbs;
    for (std::size_t i = old; i < limbs_; ++i) {
        universe_->address_reg(static_cast<std::uint16_t>(base_ + i)).meta = 0;
    }
    return true;
}

Atlas::Atlas() {
    pages_.push_back(std::make_unique<Universe>(0x41544C41u));
}

Universe& Atlas::page(std::size_t index) { return *pages_.at(index); }
const Universe& Atlas::page(std::size_t index) const { return *pages_.at(index); }

std::size_t Atlas::allocate_page() {
    pages_.push_back(std::make_unique<Universe>(0x41544C41u + pages_.size()));
    return pages_.size() - 1;
}

std::uint16_t AtlasLimbStore::get(std::size_t index) const {
    if (index >= limbs_) return 0;
    const std::size_t page = index / per_page_;
    const std::size_t offset = index % per_page_;
    if (page >= atlas_->page_count()) return 0;
    return static_cast<std::uint16_t>(
        atlas_->page(page).address_reg(static_cast<std::uint16_t>(base_ + offset)).meta & 0xFFFFu);
}

void AtlasLimbStore::set(std::size_t index, std::uint16_t value) {
    const std::size_t page = index / per_page_;
    if (page >= atlas_->page_count()) return;
    const std::size_t offset = index % per_page_;
    if (index >= limbs_) limbs_ = index + 1;
    atlas_->page(page).address_reg(static_cast<std::uint16_t>(base_ + offset)).meta = value;
}

bool AtlasLimbStore::grow(std::size_t limbs) {
    const std::size_t pages = (limbs + per_page_ - 1) / per_page_;
    while (atlas_->page_count() < pages) atlas_->allocate_page();
    const std::size_t old = limbs_;
    if (limbs > limbs_) limbs_ = limbs;
    for (std::size_t i = old; i < limbs_; ++i) {
        atlas_->page(i / per_page_)
            .address_reg(static_cast<std::uint16_t>(base_ + (i % per_page_))).meta = 0;
    }
    return true;
}

void LimbCounter::clear() {
    if (store_->limbs() == 0) store_->grow(1);
    for (std::size_t i = 0; i < store_->limbs(); ++i) store_->set(i, 0);
}

void LimbCounter::set_low(std::uint16_t value) {
    if (store_->limbs() == 0) store_->grow(1);
    store_->set(0, value);
}

bool LimbCounter::increment() {
    if (store_->limbs() == 0 && !store_->grow(1)) return false;
    std::size_t i = 0;
    std::uint32_t carry = 1;
    while (carry != 0) {
        if (i >= store_->limbs()) {
            if (!store_->grow(i + 1)) return false;
        }
        const std::uint32_t value = store_->get(i) + carry;
        store_->set(i, static_cast<std::uint16_t>(value & 0xFFFFu));
        carry = value >> 16;
        ++i;
    }
    return true;
}

bool LimbCounter::decrement() {
    if (is_zero()) return false;
    std::size_t i = 0;
    std::int32_t borrow = 1;
    while (borrow != 0 && i < store_->limbs()) {
        const std::int32_t value = static_cast<std::int32_t>(store_->get(i)) - borrow;
        if (value < 0) {
            store_->set(i, 0xFFFFu);
            borrow = 1;
        } else {
            store_->set(i, static_cast<std::uint16_t>(value));
            borrow = 0;
        }
        ++i;
    }
    return true;
}

bool LimbCounter::is_zero() const {
    for (std::size_t i = 0; i < store_->limbs(); ++i) {
        if (store_->get(i) != 0) return false;
    }
    return true;
}

std::uint64_t LimbCounter::low64() const {
    std::uint64_t value = 0;
    const std::size_t n = std::min<std::size_t>(4, store_->limbs());
    for (std::size_t i = 0; i < n; ++i) {
        value |= static_cast<std::uint64_t>(store_->get(i)) << (16 * i);
    }
    return value;
}

} // namespace nanlm
