// The 4 MiB register-file universe.
//
// One universe stores the 32,896 canonical cells:
//   - 256 head cells on the diagonal (self-mirrored fixed points)
//   - 32,640 edge cells, one per unordered pair of heads (C(256,2))
//
// Each cell has four NaN16 words (s+, s-, q+, q-) and a 16-bit Boolean
// operator mask. Every cell is 64 bytes. The dense register array is 2 MiB;
// descriptors, the 256x256 adjacency bitmap, head table, and dirty bits fit
// in the remaining half of a 4 MiB page.
#pragma once

#include "nanlm/nan16.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <type_traits>
#include <vector>

namespace nanlm {

inline constexpr std::size_t kCellBytes = 64;
inline constexpr std::size_t kDescriptorBytes = 48;
inline constexpr std::size_t kAddressRegBytes = 32;
inline constexpr std::size_t kHeadCount = 256;
inline constexpr std::size_t kHeadBytes = 32;
inline constexpr std::size_t kAdjacencyBytes = kHeadCount * 32; // 8 KiB bitmap
inline constexpr std::size_t kDirtyBytes = (kCanonicalCount + 7) / 8;
inline constexpr std::size_t kAddressDirtyBytes = (kAddressCount + 7) / 8;
inline constexpr std::size_t kHeadScratchBytes = 1024;      // 256 B local + 768 B work
inline constexpr std::size_t kHeadLocalBytes = 256;
inline constexpr std::size_t kChartScratchBytes = 65536;    // shared chart scratch
// Mapped hypermatrix extension: one 256-bit candidate row per unordered
// mirror pair (32,640 rows). It is part of the same 8 MiB chart, not a
// host-side side table.
inline constexpr std::size_t kHypermatrixRowBytes = 32;
inline constexpr std::size_t kHypermatrixRows = kMirrorPairCount;
inline constexpr std::size_t kHypermatrixBytes = kHypermatrixRows * kHypermatrixRowBytes;
// Adaptive triad/field state. It is a compact native overlay on the same 256
// physical heads, serialized and digested with the chart.
inline constexpr std::size_t kTriadCount = 85;
inline constexpr std::size_t kTriadSize = 3;
inline constexpr std::size_t kTriadMemberCount = kTriadCount * kTriadSize; // 255
inline constexpr std::size_t kFieldHead = 255;
inline constexpr std::size_t kTriadStateBytes =
    kTriadMemberCount + kHeadCount + kHeadCount + kTriadCount +
    kTriadCount * 2 + kTriadCount * 4 + 4 + 2 + kHeadCount * 2 + 4;

// Native sparse head/field state.  The shared trunk supplies an 8-dimensional
// Q16.16 feature vector; this bank owns the 255 independent low-rank adapters,
// router scores, hotspots and usage counters.  It is serialized and digested
// with the chart so a paged/resident sparse field has one identity.
inline constexpr std::size_t kSparseDim = 8;
inline constexpr std::size_t kSparseHeads = 255;
inline constexpr std::size_t kSparseActive = 8;
inline constexpr std::size_t kSparseRank = 2;

struct SparseFieldState {
    std::int16_t down[kSparseHeads][kSparseDim][kSparseRank]{};
    std::int16_t up[kSparseHeads][kSparseRank][kSparseDim]{};
    std::int16_t router[kSparseHeads][kSparseDim]{};
    std::int16_t hotspot[kSparseHeads]{};
    std::uint32_t usage[kSparseHeads]{};
    std::uint32_t generation = 0;
    std::uint32_t flags = 0;
};
inline constexpr std::size_t kSparseFieldBytes = sizeof(SparseFieldState);
static_assert(sizeof(SparseFieldState) <= 32768);

inline constexpr std::size_t kIndexBytes = kAddressCount * 2;
inline constexpr std::size_t kCanonicalIndexBytes = kCanonicalCount * 2;
inline constexpr std::size_t kPairIndexBytes = kMirrorPairCount * 2;
inline constexpr std::size_t kAddressTableBytes = kAddressCount * kAddressRegBytes;
inline constexpr std::size_t kRegisterBytes = kCanonicalCount * kCellBytes;
inline constexpr std::size_t kDescriptorTableBytes = kCanonicalCount * kDescriptorBytes;
inline constexpr std::size_t kPageBytes = 8u * 1024u * 1024u;

static_assert(kRegisterBytes == 2'105'344);
static_assert(kDescriptorTableBytes == 1'579'008);
static_assert(kAddressTableBytes == 2'097'152);
static_assert(kRegisterBytes + kDescriptorTableBytes + kAddressTableBytes + kIndexBytes +
                  kCanonicalIndexBytes + kPairIndexBytes + kHeadBytes * kHeadCount +
                  kAdjacencyBytes + kDirtyBytes + kAddressDirtyBytes +
                  kHeadScratchBytes * kHeadCount + kChartScratchBytes +
                  kHypermatrixBytes + kTriadStateBytes + kSparseFieldBytes < kPageBytes);

inline constexpr std::uint32_t kNoIndex = 0xFFFFFFFFu;

// Cell and descriptor flags.
inline constexpr std::uint8_t kFlagHead = 1u << 0;
inline constexpr std::uint8_t kFlagPair = 1u << 1;
inline constexpr std::uint8_t kFlagDual = 1u << 2;
inline constexpr std::uint8_t kFlagPortal = 1u << 3;
inline constexpr std::uint8_t kFlagLocked = 1u << 4;
inline constexpr std::uint8_t kFlagDirty = 1u << 5;
inline constexpr std::uint8_t kFlagChecked = 1u << 6;
inline constexpr std::uint8_t kFlagShadow = 1u << 7;

// Address flags (per one of the 65,536 addresses, including both mirrors).
inline constexpr std::uint8_t kAddrFixed = 1u << 0;
inline constexpr std::uint8_t kAddrCanonical = 1u << 1;
inline constexpr std::uint8_t kAddrUpper = 1u << 2;
inline constexpr std::uint8_t kAddrPaired = 1u << 3;
inline constexpr std::uint8_t kAddrDirty = 1u << 4;
inline constexpr std::uint8_t kAddrLocked = 1u << 5;
inline constexpr std::uint8_t kAddrPortal = 1u << 6;
inline constexpr std::uint8_t kAddrReserved = 1u << 7;

// One individually addressable register for every 16-bit address, including
// both orientations of every mirror pair. The shared pair payload lives in the
// canonical NanCell; this record carries the address-specific identity,
// mirror link, pair link, capabilities, and per-address metadata.
struct AddressReg {
    std::uint16_t addr = 0;
    std::uint16_t mirror = 0;      // reverse16(addr)
    std::uint16_t pair = kMirrorPairCount; // pair index, or sentinel for a head
    std::uint8_t head_a = 0;       // row head
    std::uint8_t head_b = 0;       // column head
    std::uint8_t flags = 0;
    std::uint8_t caps = 0x7;       // R/W/X
    std::uint16_t generation = 0;
    std::uint32_t epoch = 0;
    std::uint32_t checksum = 0;
    std::uint32_t aux = 0;
    std::uint64_t meta = 0;        // canonical cell index / future pointer

    bool is_fixed() const { return (flags & kAddrFixed) != 0; }
    bool is_canonical() const { return (flags & kAddrCanonical) != 0; }
    bool is_upper() const { return (flags & kAddrUpper) != 0; }
    bool is_paired() const { return (flags & kAddrPaired) != 0; }
    bool can_read() const { return (caps & 1u) != 0; }
    bool can_write() const { return (caps & 2u) != 0; }
    bool can_exec() const { return (caps & 4u) != 0; }
};
static_assert(sizeof(AddressReg) == kAddressRegBytes);
static_assert(std::is_trivially_copyable_v<AddressReg>);

// Per-head scratchpad: 256 bytes of local registers + 768 bytes of working
// memory. The local area is for the head's own registers/stack; the work area
// is for Boolean truth-table patches, operands, and small experiments.
// NaNNet route coordinates are six bytes in canonical GM:SC:MC:BS:HW:BSR order.
struct NannetRoute {
    std::uint8_t gm = 0;
    std::uint8_t sc = 0;
    std::uint8_t mc = 0;
    std::uint8_t bs = 0;
    std::uint8_t hw = 0;
    std::uint8_t bsr = 0;

    constexpr bool valid() const { return bsr <= 5; }
    constexpr std::array<std::uint8_t, 6> bytes() const {
        return {gm, sc, mc, bs, hw, bsr};
    }
    static constexpr bool from_bytes(const std::array<std::uint8_t, 6>& raw,
                                     NannetRoute& route) {
        route = {raw[0], raw[1], raw[2], raw[3], raw[4], raw[5]};
        return route.valid();
    }
};

// The translator is a real per-Universe module, anchored at diagonal cell (0,0).
// Its wire representation preserves NaN16DE words bit-for-bit.
class PointZeroTranslator {
public:
    static constexpr std::uint8_t kPointIndex = 0;
    static constexpr std::uint8_t kProtocolVersion = 1;

    constexpr PointZeroTranslator() = default;

    constexpr bool bind(NannetRoute route) {
        if (!route.valid()) return false;
        local_route_ = route;
        return true;
    }
    constexpr const NannetRoute& local_route() const { return local_route_; }
    constexpr NannetRoute point_route() const { return NannetRoute{}; }
    constexpr std::uint8_t point_index() const { return kPointIndex; }
    constexpr std::uint8_t protocol_version() const { return kProtocolVersion; }

    static constexpr std::array<std::uint8_t, 6> encode_route(NannetRoute route) {
        return route.bytes();
    }
    static constexpr bool decode_route(const std::array<std::uint8_t, 6>& raw,
                                       NannetRoute& route) {
        return NannetRoute::from_bytes(raw, route);
    }
    static std::string route_uri(NannetRoute route) {
        return "nan://GM" + std::to_string(route.gm) + ":SC" +
               std::to_string(route.sc) + ":MC" + std::to_string(route.mc) +
               ":BS" + std::to_string(route.bs) + ":HW" +
               std::to_string(route.hw) + ":BSR" + std::to_string(route.bsr);
    }
    static constexpr NanWord preserve_word(NanWord word) { return NanWord(word.raw); }

private:
    NannetRoute local_route_{};
};

struct HeadScratch {
    std::array<std::uint8_t, kHeadScratchBytes> bytes{};

    std::uint8_t* local() { return bytes.data(); }
    const std::uint8_t* local() const { return bytes.data(); }
    std::uint8_t* work() { return bytes.data() + kHeadLocalBytes; }
    const std::uint8_t* work() const { return bytes.data() + kHeadLocalBytes; }
    void clear() { bytes.fill(0); }
};
static_assert(sizeof(HeadScratch) == kHeadScratchBytes);
static_assert(std::is_trivially_copyable_v<HeadScratch>);

struct NanCell {
    NanWord words[4];        // [0]=s+, [1]=s-, [2]=q+, [3]=q-
    std::uint32_t epoch = 0;
    std::uint16_t ops = 0;   // 16 Boolean functions enabled
    std::uint16_t generation = 0;
    std::uint16_t owner = 0;
    std::uint16_t aux = 0;
    std::uint8_t rule = 0;   // selected function 0..15
    std::uint8_t flags = 0;
    std::uint8_t meta[18] = {};

    NanWord& s_plus() { return words[0]; }
    NanWord& s_minus() { return words[1]; }
    NanWord& q_plus() { return words[2]; }
    NanWord& q_minus() { return words[3]; }
    const NanWord& s_plus() const { return words[0]; }
    const NanWord& s_minus() const { return words[1]; }
    const NanWord& q_plus() const { return words[2]; }
    const NanWord& q_minus() const { return words[3]; }

    bool is_head() const { return (flags & kFlagHead) != 0; }
    bool is_pair() const { return (flags & kFlagPair) != 0; }
    bool is_dual() const { return (flags & kFlagDual) != 0; }
    bool is_portal() const { return (flags & kFlagPortal) != 0; }
    void set_flag(std::uint8_t f, bool on) {
        if (on) flags = static_cast<std::uint8_t>(flags | f);
        else flags = static_cast<std::uint8_t>(flags & ~f);
    }
    void reset() { *this = NanCell{}; }
};
static_assert(sizeof(NanCell) == kCellBytes);
static_assert(std::is_trivially_copyable_v<NanCell>);

struct Descriptor {
    std::uint16_t canonical = 0;
    std::uint16_t mirror = 0;
    std::uint32_t pair = kMirrorPairCount; // sentinel for heads
    std::uint8_t head_a = 0;
    std::uint8_t head_b = 0;
    std::uint8_t flags = 0;
    std::uint8_t rule = 0;
    std::uint16_t generation = 0;
    std::uint16_t owner = 0;
    std::uint32_t epoch = 0;
    std::uint32_t child = 0;      // child page id / 0 = none
    std::uint32_t checksum = 0;
    std::uint32_t aux = 0;
    std::uint32_t next_a = kNoIndex; // next pair in head_a's linked list
    std::uint32_t next_b = kNoIndex; // next pair in head_b's linked list
    std::uint8_t reserved[8] = {};

    bool is_head() const { return (flags & kFlagHead) != 0; }
    bool is_pair() const { return (flags & kFlagPair) != 0; }
};
static_assert(sizeof(Descriptor) == kDescriptorBytes);
static_assert(std::is_trivially_copyable_v<Descriptor>);

struct Head {
    std::uint16_t fixed_addr = 0;
    std::uint16_t edge_head = 0xFFFFu; // first pair index in the row list
    std::uint16_t child = 0;           // 1 = has a child chart at PageId::child(chart, h)
    std::uint16_t self_error = 0;      // normalized self-model error, 0..65535
    std::uint32_t phase = 0;           // Q16.16 phase
    std::uint32_t energy = 0;          // Q16.16 amplitude
    std::uint16_t load = 0;            // homeostasis
    std::uint16_t scratch_used = 0;    // high-water mark of the head scratchpad
    std::uint8_t edge_count = 0;       // 255 for an interior head
    std::uint8_t flags = 0;
    std::uint8_t error_streak = 0;     // consecutive high-error observations
    std::uint8_t transform_phase = 0; // 2 bits: I/B/BR/R oscillator phase
    std::uint32_t genome = 0;
    std::uint32_t checksum = 0;
};
static_assert(sizeof(Head) == kHeadBytes);
static_assert(std::is_trivially_copyable_v<Head>);

class Universe {
public:
    explicit Universe(std::uint64_t genome = 0);
    Universe(const Universe&) = default;
    Universe& operator=(const Universe&) = default;

    static std::unique_ptr<Universe> from_bytes(const std::uint8_t* data, std::size_t len);

    // Address views. All aliases canonicalize through the index table.
    NanCell& at_addr(std::uint16_t addr);
    const NanCell& at_addr(std::uint16_t addr) const;
    NanCell& at(std::uint8_t row, std::uint8_t col) { return at_addr(matrix_addr(row, col)); }
    const NanCell& at(std::uint8_t row, std::uint8_t col) const {
        return at_addr(matrix_addr(row, col));
    }
    NanCell& head_cell(std::uint8_t i) { return at(i, i); }
    const NanCell& head_cell(std::uint8_t i) const { return at(i, i); }
    NanCell& pair_cell(std::uint8_t a, std::uint8_t b);
    const NanCell& pair_cell(std::uint8_t a, std::uint8_t b) const;

    Descriptor& descriptor_at_addr(std::uint16_t addr);
    const Descriptor& descriptor_at_addr(std::uint16_t addr) const;
    Descriptor& descriptor_index(std::uint32_t idx);
    const Descriptor& descriptor_index(std::uint32_t idx) const;
    Descriptor& descriptor_pair(std::uint32_t pair);
    const Descriptor& descriptor_pair(std::uint32_t pair) const;

    // Full-address register view: every address, including both mirrors.
    AddressReg& address_reg(std::uint16_t addr);
    const AddressReg& address_reg(std::uint16_t addr) const;
    bool address_dirty(std::uint16_t addr) const;
    void mark_address_dirty(std::uint16_t addr);
    void set_address_meta(std::uint16_t addr, std::uint64_t value);
    void clear_address_dirty();
    std::size_t address_dirty_count() const;
    bool set_capability(std::uint16_t addr, std::uint8_t caps);
    static std::uint32_t address_checksum(const AddressReg& reg);

    PointZeroTranslator& point_zero_translator() { return point_zero_translator_; }
    const PointZeroTranslator& point_zero_translator() const { return point_zero_translator_; }
    bool bind_point_zero_route(NannetRoute route);

    Head& head(std::uint8_t i) { return heads_[i]; }
    const Head& head(std::uint8_t i) const { return heads_[i]; }

    HeadScratch& head_scratch(std::uint8_t i) { return head_scratch_[i]; }
    const HeadScratch& head_scratch(std::uint8_t i) const { return head_scratch_[i]; }
    std::array<std::uint8_t, kChartScratchBytes>& chart_scratch() { return chart_scratch_; }
    const std::array<std::uint8_t, kChartScratchBytes>& chart_scratch() const {
        return chart_scratch_;
    }

    // The mapped hypermatrix: 32,640 unordered-pair rows x 256 candidate bits.
    // A triad (a,b,c) uses three pair rows: p(a,b) bit c, p(b,c) bit a, and
    // p(c,a) bit b. Rows are part of the chart digest and serialize with it.
    std::array<std::uint8_t, kHypermatrixRowBytes>& hypermatrix_row(std::uint32_t pair) {
        return hypermatrix_[pair];
    }
    const std::array<std::uint8_t, kHypermatrixRowBytes>&
    hypermatrix_row(std::uint32_t pair) const {
        return hypermatrix_[pair];
    }
    std::vector<std::array<std::uint8_t, kHypermatrixRowBytes>>& hypermatrix() {
        return hypermatrix_;
    }
    const std::vector<std::array<std::uint8_t, kHypermatrixRowBytes>>&
    hypermatrix() const {
        return hypermatrix_;
    }
    std::size_t hypermatrix_nonzero() const;

    // Adaptive triad map and integer credit fields. Heads 0..254 are a
    // permutation of the 255 triad members; head 255 is the field head.
    // The mapping is temporary and may be remapped by a triad/field vote.
    std::array<std::uint8_t, kTriadMemberCount>& triad_members() { return triad_members_; }
    const std::array<std::uint8_t, kTriadMemberCount>& triad_members() const { return triad_members_; }
    std::array<std::uint8_t, kHeadCount>& triad_of() { return triad_of_; }
    const std::array<std::uint8_t, kHeadCount>& triad_of() const { return triad_of_; }
    std::array<std::uint8_t, kHeadCount>& triad_slot() { return triad_slot_; }
    const std::array<std::uint8_t, kHeadCount>& triad_slot() const { return triad_slot_; }
    std::array<std::uint8_t, kTriadCount>& triad_votes() { return triad_votes_; }
    const std::array<std::uint8_t, kTriadCount>& triad_votes() const { return triad_votes_; }
    std::array<std::int16_t, kTriadCount>& triad_credit() { return triad_credit_; }
    const std::array<std::int16_t, kTriadCount>& triad_credit() const { return triad_credit_; }
    std::array<std::int32_t, kTriadCount>& triad_group_gain() { return triad_group_gain_; }
    const std::array<std::int32_t, kTriadCount>& triad_group_gain() const { return triad_group_gain_; }
    std::array<std::int16_t, kHeadCount>& head_credit() { return head_credit_; }
    const std::array<std::int16_t, kHeadCount>& head_credit() const { return head_credit_; }
    SparseFieldState& sparse_field() { return sparse_field_; }
    const SparseFieldState& sparse_field() const { return sparse_field_; }
    std::int32_t& triad_field_gain() { return triad_field_gain_; }
    std::int32_t triad_field_gain() const { return triad_field_gain_; }
    std::uint16_t& triad_field_count() { return triad_field_count_; }
    std::uint16_t triad_field_count() const { return triad_field_count_; }
    std::int32_t& field_coherence() { return field_coherence_; }
    std::int32_t field_coherence() const { return field_coherence_; }
    std::uint8_t triad_index(std::uint8_t head) const {
        return head < kFieldHead ? triad_of_[head] : 0xFFu;
    }
    void reset_triad_map();

    bool adjacent(std::uint8_t a, std::uint8_t b) const;
    void set_adjacent(std::uint8_t a, std::uint8_t b, bool value);

    std::uint32_t index_of_addr(std::uint16_t addr) const;
    std::uint32_t index_of_pair(std::uint32_t pair) const;
    std::uint16_t canonical_of_index(std::uint32_t idx) const;
    std::uint32_t canonical_count() const { return kCanonicalCount; }
    std::uint32_t pair_count() const { return kMirrorPairCount; }

    const std::vector<NanCell>& cells() const { return cells_; }
    std::vector<NanCell>& cells() { return cells_; }
    const std::vector<Descriptor>& descriptors() const { return desc_; }
    std::vector<Descriptor>& descriptors() { return desc_; }
    const std::array<Head, kHeadCount>& heads() const { return heads_; }
    std::array<Head, kHeadCount>& heads() { return heads_; }

    std::uint64_t genome() const { return genome_; }
    Hash256 digest() const;
    std::vector<std::uint8_t> serialize() const;
    bool verify(std::string* error = nullptr) const;

    // Rebuild the two linked adjacency lists and the 256x256 bitmap.
    void rebuild_links();

    // Deterministic per-cell checksum (FNV-1a over the 64-byte cell).
    static std::uint32_t cell_checksum(const NanCell& cell);

    // Recompute all descriptor checksums after host-side model training that
    // edits cells directly.
    void refresh_checksums();

private:
    void build_index();
    void build_genesis(std::uint64_t genome);

    PointZeroTranslator point_zero_translator_{};
    std::uint64_t genome_ = 0;
    std::vector<NanCell> cells_;                 // 32,896 x 64 = 2 MiB
    std::vector<AddressReg> addr_regs_;          // 65,536 x 32 = 2 MiB
    std::vector<Descriptor> desc_;               // 32,896 x 48 = 1.5 MiB
    std::array<std::uint16_t, kAddressCount> index_{};
    std::array<std::uint16_t, kCanonicalCount> canon_{};
    std::array<std::uint16_t, kMirrorPairCount> pair_to_index_{};
    std::array<Head, kHeadCount> heads_{};
    std::array<std::array<std::uint64_t, 4>, kHeadCount> adjacency_{};
    std::array<std::uint64_t, (kAddressCount + 63) / 64> addr_dirty_{};
    std::array<HeadScratch, kHeadCount> head_scratch_{};
    std::array<std::uint8_t, kChartScratchBytes> chart_scratch_{};
    std::vector<std::array<std::uint8_t, kHypermatrixRowBytes>> hypermatrix_;
    std::array<std::uint8_t, kTriadMemberCount> triad_members_{};
    std::array<std::uint8_t, kHeadCount> triad_of_{};
    std::array<std::uint8_t, kHeadCount> triad_slot_{};
    std::array<std::uint8_t, kTriadCount> triad_votes_{};
    std::array<std::int16_t, kTriadCount> triad_credit_{};
    std::array<std::int32_t, kTriadCount> triad_group_gain_{};
    std::array<std::int16_t, kHeadCount> head_credit_{};
    SparseFieldState sparse_field_{};
    std::int32_t triad_field_gain_ = 65536;
    std::uint16_t triad_field_count_ = 0;
    std::int32_t field_coherence_ = 0;
};

} // namespace nanlm
