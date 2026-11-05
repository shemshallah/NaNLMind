// Multi-limb counters in chart address registers, with an atlas backend for
// growing beyond one chart. No host integer is the counter.
#pragma once

#include "nanlm/universe.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace nanlm {

class LimbStore {
public:
    virtual ~LimbStore() = default;
    virtual std::uint16_t get(std::size_t index) const = 0;
    virtual void set(std::size_t index, std::uint16_t value) = 0;
    virtual bool grow(std::size_t limbs) = 0;
    virtual std::size_t limbs() const = 0;
};

class ChartLimbStore : public LimbStore {
public:
    ChartLimbStore(Universe& universe, std::uint16_t base, std::size_t capacity)
        : universe_(&universe), base_(base), capacity_(capacity) {}

    std::uint16_t get(std::size_t index) const override;
    void set(std::size_t index, std::uint16_t value) override;
    bool grow(std::size_t limbs) override;
    std::size_t limbs() const override { return limbs_; }

private:
    Universe* universe_;
    std::uint16_t base_;
    std::size_t capacity_;
    std::size_t limbs_ = 0;
};

class Atlas {
public:
    Atlas();
    Universe& page(std::size_t index);
    const Universe& page(std::size_t index) const;
    std::size_t allocate_page();
    std::size_t page_count() const { return pages_.size(); }

private:
    std::vector<std::unique_ptr<Universe>> pages_;
};

class AtlasLimbStore : public LimbStore {
public:
    AtlasLimbStore(Atlas& atlas, std::uint16_t base, std::size_t per_page)
        : atlas_(&atlas), base_(base), per_page_(per_page) {}

    std::uint16_t get(std::size_t index) const override;
    void set(std::size_t index, std::uint16_t value) override;
    bool grow(std::size_t limbs) override;
    std::size_t limbs() const override { return limbs_; }

private:
    Atlas* atlas_;
    std::uint16_t base_;
    std::size_t per_page_;
    std::size_t limbs_ = 0;
};

class LimbCounter {
public:
    explicit LimbCounter(LimbStore& store) : store_(&store) {}

    void clear();
    void set_low(std::uint16_t value);
    bool increment();
    bool decrement();
    bool is_zero() const;
    std::uint64_t low64() const;
    std::size_t limbs() const { return store_->limbs(); }
    const LimbStore& store() const { return *store_; }

private:
    LimbStore* store_;
};

} // namespace nanlm
