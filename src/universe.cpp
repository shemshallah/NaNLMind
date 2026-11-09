#include "nanlm/universe.hpp"

#include <algorithm>
#include <bit>
#include <cstring>
#include <sstream>
#include <stdexcept>

namespace nanlm {
namespace {

constexpr char kMagic[8] = {'N', 'L', 'M', 'U', '0', '0', '0', '1'};

std::uint32_t fnv1a(const void* data, std::size_t len) {
    const auto* p = static_cast<const std::uint8_t*>(data);
    std::uint32_t h = 2166136261u;
    for (std::size_t i = 0; i < len; ++i) {
        h ^= p[i];
        h *= 16777619u;
    }
    return h;
}

} // namespace

Universe::Universe(std::uint64_t genome) : genome_(genome) {
    cells_.resize(kCanonicalCount);
    desc_.resize(kCanonicalCount);
    addr_regs_.resize(kAddressCount);
    addr_dirty_.fill(0);
    for (auto& sc : head_scratch_) sc.clear();
    chart_scratch_.fill(0);
    hypermatrix_.assign(kHypermatrixRows, {});
    build_index();
    build_genesis(genome);
}

bool Universe::bind_point_zero_route(NannetRoute route) {
    if (!point_zero_translator_.bind(route)) return false;
    const std::uint32_t idx = index_[canonical16(matrix_addr(0, 0))];
    NanCell& cell = cells_[idx];
    cell.meta[2] = PointZeroTranslator::kPointIndex;
    cell.meta[3] = PointZeroTranslator::kProtocolVersion;
    const auto raw = PointZeroTranslator::encode_route(route);
    for (std::size_t i = 0; i < raw.size(); ++i) {
        cell.meta[4 + i] = raw[i];
    }
    desc_[idx].checksum = cell_checksum(cell);
    return true;
}

void Universe::build_index() {
    index_.fill(0xFFFFu);
    canon_.fill(0);

    std::uint32_t next = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (a == canonical16(a)) {
            if (next >= kCanonicalCount) throw std::runtime_error("canonical overflow");
            canon_[next] = a;
            index_[a] = static_cast<std::uint16_t>(next);
            ++next;
        }
    }
    if (next != kCanonicalCount) throw std::runtime_error("canonical count mismatch");

    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (index_[a] == 0xFFFFu) {
            index_[a] = index_[canonical16(a)];
        }
    }
}

void Universe::build_genesis(std::uint64_t genome) {
    pair_to_index_.fill(0);
    adjacency_ = {};
    heads_ = {};

    for (std::uint32_t idx = 0; idx < kCanonicalCount; ++idx) {
        const std::uint16_t c = canon_[idx];
        const std::uint8_t row = matrix_row(c);
        const std::uint8_t col = matrix_col(c);
        Descriptor d;
        d.canonical = c;
        d.mirror = reverse16(c);
        d.generation = 0;
        d.epoch = 0;

        NanCell cell{};
        if (row == col) {
            d.pair = kMirrorPairCount;
            d.head_a = row;
            d.head_b = row;
            d.flags = kFlagHead | kFlagDual | kFlagPortal;
            d.rule = static_cast<std::uint8_t>(row & 15u);
            d.owner = row;

            const std::uint32_t payload = mix32(0x48454144u ^
                                                (static_cast<std::uint32_t>(row) * 0x01010101u));
            cell.words[0] = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, payload);
            cell.words[1] = NanWord::make(NanType::QuietNegative, NanType::QuietNegative, ~payload);
            cell.words[2] = NanWord::make(NanType::SignalPositive, NanType::SignalPositive, c);
            cell.words[3] = NanWord::make(NanType::SignalNegative, NanType::SignalNegative, c);
            cell.ops = 0xFFFFu;
            cell.rule = d.rule;
            cell.flags = static_cast<std::uint8_t>(kFlagHead | kFlagDual | kFlagPortal);
            cell.owner = row;

            Head& h = heads_[row];
            h = Head{};
            h.fixed_addr = c;
            h.edge_head = 0xFFFFu;
            h.edge_count = 0;
            h.child = 0;
            h.phase = mix32(static_cast<std::uint32_t>(genome) ^
                            (static_cast<std::uint32_t>(row) * 0x9E3779B9u)) & 0xFFFFu;
            h.energy = 65536u;
            h.load = 0;
            h.flags = 1u;
            h.genome = mix32(static_cast<std::uint32_t>(genome >> 32) ^
                             (static_cast<std::uint32_t>(row) * 0x85EBCA6Bu));
        } else {
            const std::uint8_t a = std::min(row, col);
            const std::uint8_t b = std::max(row, col);
            const std::uint32_t p = pair_index(a, b);
            d.pair = p;
            d.head_a = a;
            d.head_b = b;
            d.flags = kFlagPair | kFlagDual;
            d.rule = static_cast<std::uint8_t>((a ^ b) & 15u);
            d.owner = a;

            const std::uint32_t lo = mix_pair(a, b);
            const std::uint32_t hi = mix_pair(b, a);
            cell.words[0] = NanWord::make(NanType::QuietPositive, NanType::QuietPositive, lo);
            cell.words[1] = NanWord::make(NanType::QuietNegative, NanType::QuietNegative, hi);
            cell.words[2] = NanWord::make(NanType::SignalPositive, NanType::SignalPositive,
                                          matrix_addr(a, b));
            cell.words[3] = NanWord::make(NanType::SignalNegative, NanType::SignalNegative,
                                          matrix_addr(b, a));
            const std::uint8_t hd = hamming8(a, b);
            cell.ops = static_cast<std::uint16_t>(
                (1u << (hd & 15u)) | (1u << (static_cast<unsigned>(a + b) & 15u)));
            cell.rule = d.rule;
            cell.flags = static_cast<std::uint8_t>(kFlagPair | kFlagDual);
            cell.owner = a;

            pair_to_index_[p] = static_cast<std::uint16_t>(idx);
        }

        d.checksum = fnv1a(&cell, sizeof(cell));
        cell.meta[0] = static_cast<std::uint8_t>(idx & 0xFFu);
        cell.meta[1] = static_cast<std::uint8_t>((idx >> 8) & 0xFFu);
        desc_[idx] = d;
        cells_[idx] = cell;
    }

    rebuild_links();

    // Every address, including both mirrors, gets its own 32-byte register.
    // The shared pair payload stays in the canonical NanCell; this table makes
    // the address-specific identity, mirror link, pair link and capabilities
    // individually addressable.
    addr_dirty_.fill(0);
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const std::uint8_t row = matrix_row(a);
        const std::uint8_t col = matrix_col(a);
        AddressReg r;
        r.addr = a;
        r.mirror = reverse16(a);
        r.generation = 0;
        r.epoch = 0;
        r.caps = 0x7;
        r.meta = index_[canonical16(a)];
        if (row == col) {
            r.pair = kMirrorPairCount;
            r.head_a = row;
            r.head_b = row;
            r.flags = static_cast<std::uint8_t>(kAddrFixed | kAddrCanonical |
                                                kAddrUpper | kAddrPortal);
        } else {
            const std::uint8_t lo = std::min(row, col);
            const std::uint8_t hi = std::max(row, col);
            r.pair = static_cast<std::uint16_t>(pair_index(lo, hi));
            r.head_a = lo;
            r.head_b = hi;
            r.flags = static_cast<std::uint8_t>(kAddrPaired |
                                                (a == canonical16(a) ? kAddrCanonical
                                                                     : kAddrUpper));
        }
        r.checksum = address_checksum(r);
        addr_regs_[i] = r;
    }

    for (std::uint32_t idx = 0; idx < kCanonicalCount; ++idx) {
        desc_[idx].checksum = cell_checksum(cells_[idx]);
    }
    if (!bind_point_zero_route(point_zero_translator_.local_route())) {
        throw std::runtime_error("invalid point-zero route at universe genesis");
    }
}

void Universe::rebuild_links() {
    adjacency_ = {};
    std::array<std::uint32_t, kHeadCount> last_a{};
    std::array<std::uint32_t, kHeadCount> last_b{};
    last_a.fill(kNoIndex);
    last_b.fill(kNoIndex);

    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        heads_[i].edge_head = 0xFFFFu;
        heads_[i].edge_count = 0;
    }
    for (auto& d : desc_) {
        d.next_a = kNoIndex;
        d.next_b = kNoIndex;
    }

    for (std::uint32_t p = 0; p < kMirrorPairCount; ++p) {
        const auto [a, b] = pair_heads(p);
        const std::uint16_t idx = pair_to_index_[p];
        if (idx >= kCanonicalCount) continue;
        Descriptor& d = desc_[idx];

        // Row list for head a: pairs (a, b) traversed through next_a.
        if (heads_[a].edge_head == 0xFFFFu) heads_[a].edge_head = static_cast<std::uint16_t>(p);
        if (last_a[a] != kNoIndex) desc_[pair_to_index_[last_a[a]]].next_a = p;
        last_a[a] = p;
        heads_[a].edge_count = static_cast<std::uint8_t>(heads_[a].edge_count + 1u);

        // Column list for head b: pairs (a, b) traversed through next_b.
        if (last_b[b] != kNoIndex) desc_[pair_to_index_[last_b[b]]].next_b = p;
        last_b[b] = p;
        heads_[b].edge_count = static_cast<std::uint8_t>(heads_[b].edge_count + 1u);

        adjacency_[a][b >> 6] |= (1ull << (b & 63u));
        adjacency_[b][a >> 6] |= (1ull << (a & 63u));
        (void)d;
    }
}

NanCell& Universe::at_addr(std::uint16_t addr) {
    return cells_[index_[canonical16(addr)]];
}

const NanCell& Universe::at_addr(std::uint16_t addr) const {
    return cells_[index_[canonical16(addr)]];
}

NanCell& Universe::pair_cell(std::uint8_t a, std::uint8_t b) {
    if (a == b) return head_cell(a);
    const std::uint32_t p = pair_index(a, b);
    return cells_[pair_to_index_[p]];
}

const NanCell& Universe::pair_cell(std::uint8_t a, std::uint8_t b) const {
    if (a == b) return head_cell(a);
    const std::uint32_t p = pair_index(a, b);
    return cells_[pair_to_index_[p]];
}

Descriptor& Universe::descriptor_at_addr(std::uint16_t addr) {
    return desc_[index_[canonical16(addr)]];
}

const Descriptor& Universe::descriptor_at_addr(std::uint16_t addr) const {
    return desc_[index_[canonical16(addr)]];
}

Descriptor& Universe::descriptor_index(std::uint32_t idx) { return desc_[idx]; }
const Descriptor& Universe::descriptor_index(std::uint32_t idx) const { return desc_[idx]; }

Descriptor& Universe::descriptor_pair(std::uint32_t pair) {
    return desc_[pair_to_index_[pair]];
}
const Descriptor& Universe::descriptor_pair(std::uint32_t pair) const {
    return desc_[pair_to_index_[pair]];
}

AddressReg& Universe::address_reg(std::uint16_t addr) { return addr_regs_[addr]; }
const AddressReg& Universe::address_reg(std::uint16_t addr) const { return addr_regs_[addr]; }

bool Universe::address_dirty(std::uint16_t addr) const {
    return (addr_dirty_[addr >> 6] & (1ull << (addr & 63u))) != 0;
}

void Universe::mark_address_dirty(std::uint16_t addr) {
    addr_dirty_[addr >> 6] |= (1ull << (addr & 63u));
}

void Universe::set_address_meta(std::uint16_t addr, std::uint64_t value) {
    AddressReg& reg = addr_regs_[addr];
    reg.flags = static_cast<std::uint8_t>(reg.flags | kAddrReserved);
    reg.meta = value;
    reg.checksum = address_checksum(reg);
    mark_address_dirty(addr);
}

void Universe::clear_address_dirty() { addr_dirty_.fill(0); }

std::size_t Universe::address_dirty_count() const {
    std::size_t n = 0;
    for (std::uint64_t w : addr_dirty_) n += static_cast<std::size_t>(std::popcount(w));
    return n;
}

bool Universe::set_capability(std::uint16_t addr, std::uint8_t caps) {
    AddressReg& r = addr_regs_[addr];
    r.caps = caps;
    r.checksum = address_checksum(r);
    mark_address_dirty(addr);
    return true;
}

std::uint32_t Universe::address_checksum(const AddressReg& reg) {
    const auto* p = reinterpret_cast<const std::uint8_t*>(&reg);
    const std::size_t skip = offsetof(AddressReg, checksum);
    std::uint32_t h = 2166136261u;
    for (std::size_t i = 0; i < sizeof(AddressReg); ++i) {
        if (i >= skip && i < skip + sizeof(reg.checksum)) continue;
        h ^= p[i];
        h *= 16777619u;
    }
    return h;
}

bool Universe::adjacent(std::uint8_t a, std::uint8_t b) const {
    return (adjacency_[a][b >> 6] & (1ull << (b & 63u))) != 0;
}

void Universe::set_adjacent(std::uint8_t a, std::uint8_t b, bool value) {
    if (value) {
        adjacency_[a][b >> 6] |= (1ull << (b & 63u));
        adjacency_[b][a >> 6] |= (1ull << (a & 63u));
    } else {
        adjacency_[a][b >> 6] &= ~(1ull << (b & 63u));
        adjacency_[b][a >> 6] &= ~(1ull << (a & 63u));
    }
}

std::uint32_t Universe::index_of_addr(std::uint16_t addr) const {
    return index_[canonical16(addr)];
}

std::uint32_t Universe::index_of_pair(std::uint32_t pair) const {
    return pair_to_index_[pair];
}

std::uint16_t Universe::canonical_of_index(std::uint32_t idx) const {
    return canon_[idx];
}

std::uint32_t Universe::cell_checksum(const NanCell& cell) {
    return fnv1a(&cell, sizeof(cell));
}

void Universe::refresh_checksums() {
    for (std::uint32_t idx = 0; idx < kCanonicalCount; ++idx) {
        desc_[idx].checksum = cell_checksum(cells_[idx]);
        desc_[idx].generation = cells_[idx].generation;
        desc_[idx].epoch = cells_[idx].epoch;
    }
}

Hash256 Universe::digest() const {
    Sha256 h;
    const std::uint64_t g = genome_;
    h.update(&g, sizeof(g));
    h.update(cells_.data(), cells_.size() * sizeof(NanCell));
    h.update(addr_regs_.data(), addr_regs_.size() * sizeof(AddressReg));
    h.update(addr_dirty_.data(), addr_dirty_.size() * sizeof(addr_dirty_[0]));
    h.update(head_scratch_.data(), head_scratch_.size() * sizeof(HeadScratch));
    h.update(chart_scratch_.data(), chart_scratch_.size());
    h.update(hypermatrix_.data(), hypermatrix_.size() * kHypermatrixRowBytes);
    h.update(desc_.data(), desc_.size() * sizeof(Descriptor));
    h.update(heads_.data(), heads_.size() * sizeof(Head));
    h.update(adjacency_.data(), adjacency_.size() * sizeof(adjacency_[0]));
    h.update(canon_.data(), canon_.size() * sizeof(canon_[0]));
    h.update(pair_to_index_.data(), pair_to_index_.size() * sizeof(pair_to_index_[0]));
    return h.final();
}

std::size_t Universe::hypermatrix_nonzero() const {
    std::size_t count = 0;
    for (const auto& row : hypermatrix_) {
        for (std::uint8_t b : row) {
            count += static_cast<std::size_t>(std::popcount(static_cast<unsigned>(b)));
        }
    }
    return count;
}

std::vector<std::uint8_t> Universe::serialize() const {
    const std::size_t total = sizeof(kMagic) + sizeof(std::uint64_t) + 6 * sizeof(std::uint32_t) +
                              cells_.size() * sizeof(NanCell) +
                              addr_regs_.size() * sizeof(AddressReg) +
                              addr_dirty_.size() * sizeof(addr_dirty_[0]) +
                              head_scratch_.size() * sizeof(HeadScratch) +
                              chart_scratch_.size() +
                              hypermatrix_.size() * kHypermatrixRowBytes +
                              desc_.size() * sizeof(Descriptor) +
                              heads_.size() * sizeof(Head) +
                              adjacency_.size() * sizeof(adjacency_[0]) +
                              canon_.size() * sizeof(canon_[0]) +
                              pair_to_index_.size() * sizeof(pair_to_index_[0]);
    std::vector<std::uint8_t> out(total);
    std::size_t off = 0;
    auto put = [&](const void* p, std::size_t n) {
        std::memcpy(out.data() + off, p, n);
        off += n;
    };
    put(kMagic, sizeof(kMagic));
    put(&genome_, sizeof(genome_));
    const std::uint32_t counts[6] = {
        static_cast<std::uint32_t>(cells_.size()),
        static_cast<std::uint32_t>(addr_regs_.size()),
        static_cast<std::uint32_t>(desc_.size()),
        static_cast<std::uint32_t>(heads_.size()),
        static_cast<std::uint32_t>(canon_.size()),
        static_cast<std::uint32_t>(pair_to_index_.size()),
    };
    put(counts, sizeof(counts));
    put(cells_.data(), cells_.size() * sizeof(NanCell));
    put(addr_regs_.data(), addr_regs_.size() * sizeof(AddressReg));
    put(addr_dirty_.data(), addr_dirty_.size() * sizeof(addr_dirty_[0]));
    put(head_scratch_.data(), head_scratch_.size() * sizeof(HeadScratch));
    put(chart_scratch_.data(), chart_scratch_.size());
    put(hypermatrix_.data(), hypermatrix_.size() * kHypermatrixRowBytes);
    put(desc_.data(), desc_.size() * sizeof(Descriptor));
    put(heads_.data(), heads_.size() * sizeof(Head));
    put(adjacency_.data(), adjacency_.size() * sizeof(adjacency_[0]));
    put(canon_.data(), canon_.size() * sizeof(canon_[0]));
    put(pair_to_index_.data(), pair_to_index_.size() * sizeof(pair_to_index_[0]));
    return out;
}

std::unique_ptr<Universe> Universe::from_bytes(const std::uint8_t* data, std::size_t len) {
    std::size_t off = 0;
    auto take = [&](void* p, std::size_t n) -> bool {
        if (off + n > len) return false;
        std::memcpy(p, data + off, n);
        off += n;
        return true;
    };

    char magic[8];
    if (!take(magic, sizeof(magic)) || std::memcmp(magic, kMagic, sizeof(magic)) != 0) {
        return nullptr;
    }
    std::uint64_t genome = 0;
    std::uint32_t counts[6]{};
    if (!take(&genome, sizeof(genome)) || !take(counts, sizeof(counts))) return nullptr;
    if (counts[0] != kCanonicalCount || counts[1] != kAddressCount ||
        counts[2] != kCanonicalCount || counts[3] != kHeadCount ||
        counts[4] != kCanonicalCount || counts[5] != kMirrorPairCount) {
        return nullptr;
    }

    auto u = std::make_unique<Universe>(genome);
    if (!take(u->cells_.data(), u->cells_.size() * sizeof(NanCell))) return nullptr;
    if (!take(u->addr_regs_.data(), u->addr_regs_.size() * sizeof(AddressReg))) return nullptr;
    if (!take(u->addr_dirty_.data(), u->addr_dirty_.size() * sizeof(u->addr_dirty_[0]))) return nullptr;
    if (!take(u->head_scratch_.data(), u->head_scratch_.size() * sizeof(HeadScratch))) return nullptr;
    if (!take(u->chart_scratch_.data(), u->chart_scratch_.size())) return nullptr;
    if (!take(u->hypermatrix_.data(), u->hypermatrix_.size() * kHypermatrixRowBytes)) return nullptr;
    if (!take(u->desc_.data(), u->desc_.size() * sizeof(Descriptor))) return nullptr;
    if (!take(u->heads_.data(), u->heads_.size() * sizeof(Head))) return nullptr;
    if (!take(u->adjacency_.data(), u->adjacency_.size() * sizeof(u->adjacency_[0]))) return nullptr;
    if (!take(u->canon_.data(), u->canon_.size() * sizeof(u->canon_[0]))) return nullptr;
    if (!take(u->pair_to_index_.data(),
              u->pair_to_index_.size() * sizeof(u->pair_to_index_[0]))) return nullptr;

    const NanCell& point_zero_cell = u->head_cell(PointZeroTranslator::kPointIndex);
    NannetRoute local_route{};
    if (point_zero_cell.meta[2] == 0 && point_zero_cell.meta[3] == 0) {
        // Upgrade pre-PointZero snapshots in memory; the original schema left
        // these reserved metadata bytes zeroed.
        local_route = NannetRoute{};
    } else {
        if (point_zero_cell.meta[2] != PointZeroTranslator::kPointIndex ||
            point_zero_cell.meta[3] != PointZeroTranslator::kProtocolVersion) return nullptr;
        std::array<std::uint8_t, 6> point_route_bytes{};
        for (std::size_t i = 0; i < point_route_bytes.size(); ++i) {
            point_route_bytes[i] = point_zero_cell.meta[4 + i];
        }
        if (!PointZeroTranslator::decode_route(point_route_bytes, local_route)) return nullptr;
    }
    if (!u->bind_point_zero_route(local_route)) return nullptr;

    // Rebuild the address->canonical index from the canonical table.
    u->index_.fill(0xFFFFu);
    for (std::uint32_t i = 0; i < kCanonicalCount; ++i) {
        u->index_[u->canon_[i]] = static_cast<std::uint16_t>(i);
    }
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (u->index_[a] == 0xFFFFu) u->index_[a] = u->index_[canonical16(a)];
    }
    return u;
}

bool Universe::verify(std::string* error) const {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };

    if (cells_.size() != kCanonicalCount) return fail("cell count");
    if (desc_.size() != kCanonicalCount) return fail("descriptor count");
    if (hypermatrix_.size() != kHypermatrixRows) return fail("hypermatrix count");
    const NanCell& point_zero_cell = head_cell(PointZeroTranslator::kPointIndex);
    if (!point_zero_cell.is_portal()) return fail("point-zero portal cell");
    if (point_zero_cell.meta[2] != PointZeroTranslator::kPointIndex ||
        point_zero_cell.meta[3] != PointZeroTranslator::kProtocolVersion)
        return fail("point-zero translator descriptor");
    const auto point_route = point_zero_translator_.local_route().bytes();
    for (std::size_t i = 0; i < point_route.size(); ++i) {
        if (point_zero_cell.meta[4 + i] != point_route[i])
            return fail("point-zero route binding");
    }

    std::uint32_t heads = 0;
    std::uint32_t pairs = 0;
    for (std::uint32_t idx = 0; idx < kCanonicalCount; ++idx) {
        const std::uint16_t c = canon_[idx];
        const Descriptor& d = desc_[idx];
        if (d.canonical != c) return fail("descriptor canonical");
        if (d.mirror != reverse16(c)) return fail("descriptor mirror");
        if (index_[c] != idx) return fail("index canonical");
        if (index_[reverse16(c)] != idx) return fail("index mirror");

        const std::uint8_t row = matrix_row(c);
        const std::uint8_t col = matrix_col(c);
        if (row == col) {
            ++heads;
            if (!d.is_head()) return fail("head flag");
            if (d.pair != kMirrorPairCount) return fail("head pair sentinel");
            if (!cells_[idx].is_head()) return fail("cell head flag");
        } else {
            ++pairs;
            const std::uint8_t a = std::min(row, col);
            const std::uint8_t b = std::max(row, col);
            if (!d.is_pair()) return fail("pair flag");
            if (d.pair != pair_index(a, b)) return fail("pair index");
            if (pair_to_index_[d.pair] != idx) return fail("pair lookup");
            if (!adjacent(a, b)) return fail("adjacency");
            if (d.head_a != a || d.head_b != b) return fail("pair heads");
        }
        if (d.checksum != cell_checksum(cells_[idx])) return fail("cell checksum");
    }
    if (heads != kFixedPointCount) return fail("fixed point count");
    if (pairs != kMirrorPairCount) return fail("mirror pair count");

    for (std::uint32_t p = 0; p < kMirrorPairCount; ++p) {
        const auto [a, b] = pair_heads(p);
        if (pair_index(a, b) != p) return fail("pair index roundtrip");
        const std::uint16_t idx = pair_to_index_[p];
        if (idx >= kCanonicalCount) return fail("pair to index");
        const Descriptor& d = desc_[idx];
        if (d.pair != p || d.head_a != a || d.head_b != b) return fail("pair descriptor");
    }

    for (std::uint32_t h = 0; h < kHeadCount; ++h) {
        const Head& hd = heads_[h];
        if (hd.fixed_addr != matrix_addr(static_cast<std::uint8_t>(h),
                                         static_cast<std::uint8_t>(h))) {
            return fail("head fixed address");
        }
        if (hd.edge_count != 255) return fail("head edge count");
        std::uint32_t seen = 0;
        // Row list: pairs (h, b), linked through next_a.
        std::uint32_t p = hd.edge_head;
        while (p != kNoIndex && p != 0xFFFFu && seen < 300) {
            const auto [a, b] = pair_heads(p);
            if (a != h) return fail("head row membership");
            const Descriptor& d = desc_[pair_to_index_[p]];
            p = d.next_a;
            ++seen;
        }
        // Column list: pairs (a, h), linked through next_b. The first such
        // pair is (0, h), whose dense index is h - 1.
        if (h > 0) {
            p = h - 1;
            while (p != kNoIndex && p != 0xFFFFu && seen < 300) {
                const auto [a, b] = pair_heads(p);
                if (b != h) return fail("head column membership");
                const Descriptor& d = desc_[pair_to_index_[p]];
                p = d.next_b;
                ++seen;
            }
        }
        if (seen != 255) return fail("head list length");
    }

    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        if (index_[a] != index_[canonical16(a)]) return fail("alias index");
    }

    if (addr_regs_.size() != kAddressCount) return fail("address register count");
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const AddressReg& r = addr_regs_[i];
        if (r.addr != a) return fail("address register address");
        if (r.mirror != reverse16(a)) return fail("address register mirror");
        if (addr_regs_[r.mirror].mirror != a) return fail("mirror reciprocity");
        if (r.checksum != address_checksum(r)) return fail("address register checksum");
        if ((r.flags & kAddrReserved) == 0 && r.meta != index_[canonical16(a)])
            return fail("address register meta");
        const std::uint8_t row = matrix_row(a);
        const std::uint8_t col = matrix_col(a);
        if (row == col) {
            if (!r.is_fixed()) return fail("address fixed flag");
            if (r.pair != kMirrorPairCount) return fail("address head pair sentinel");
            if (!r.is_canonical() || !r.is_upper()) return fail("address head canonical");
            if (r.head_a != row || r.head_b != row) return fail("address head heads");
        } else {
            const std::uint8_t lo = std::min(row, col);
            const std::uint8_t hi = std::max(row, col);
            if (r.pair != pair_index(lo, hi)) return fail("address pair index");
            if (r.head_a != lo || r.head_b != hi) return fail("address pair heads");
            if (!r.is_paired()) return fail("address paired flag");
            if (r.is_canonical() == r.is_upper()) return fail("address orientation flags");
        }
    }

    if (error) error->clear();
    return true;
}

} // namespace nanlm
