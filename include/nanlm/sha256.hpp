// Small, self-contained SHA-256 used for page hashes, ledger links, and
// deterministic snapshots. No external dependency; integer-only.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace nanlm {

using Hash256 = std::array<std::uint8_t, 32>;

class Sha256 {
public:
    Sha256();

    void update(const void* data, std::size_t len);
    Hash256 final();

    static Hash256 hash(const void* data, std::size_t len);

private:
    void compress(const std::uint8_t block[64]);

    std::uint32_t h_[8];
    std::uint8_t buffer_[64];
    std::size_t buffer_len_ = 0;
    std::uint64_t total_len_ = 0;
    bool finalized_ = false;
};

std::string hex(const Hash256& h);
bool operator==(const Hash256& a, const Hash256& b);

} // namespace nanlm
