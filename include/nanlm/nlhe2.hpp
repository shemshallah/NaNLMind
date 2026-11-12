// NLHE2: canonical structural hyperedge record stored as a typed tensor leaf.
//
// NLHE2 is integer-only topology plus provenance identity.  It deliberately
// contains no floats, votes, gradients, or active model state.  The enclosing
// TensorDataLeaf carries source_generation and the authenticated source SHA.
#pragma once
#include "nanlm/tensor_point.hpp"
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace nanlm {

inline constexpr std::uint8_t kNlhe2Version = 2;
inline constexpr std::size_t kNlhe2HeaderBytes = 48;
inline constexpr std::size_t kNlhe2MemberBytes = 8;
inline constexpr std::size_t kNlhe2MaxMembers = 255;
inline constexpr std::size_t kNlhe2MaxBytes = kNlhe2HeaderBytes +
    kNlhe2MemberBytes * kNlhe2MaxMembers;

inline constexpr std::uint16_t kNlhe2FlagDirected   = 1u << 0;
inline constexpr std::uint16_t kNlhe2FlagTemporal   = 1u << 1;
inline constexpr std::uint16_t kNlhe2FlagMirror     = 1u << 2;
inline constexpr std::uint16_t kNlhe2FlagCrossSpace = 1u << 3;
inline constexpr std::uint16_t kNlhe2FlagLearned    = 1u << 4;
inline constexpr std::uint16_t kNlhe2KnownFlags     = 0x001Fu;

inline constexpr std::uint8_t kNlhe2RoleMember         = 1u << 0;
inline constexpr std::uint8_t kNlhe2RoleRepresentative = 1u << 1;
inline constexpr std::uint8_t kNlhe2RoleTail           = 1u << 2;
inline constexpr std::uint8_t kNlhe2RoleHead           = 1u << 3;
inline constexpr std::uint8_t kNlhe2RoleWitness        = 1u << 4;
inline constexpr std::uint8_t kNlhe2KnownRoles         = 0x1Fu;
inline constexpr std::uint8_t kNlhe2MaxLeafKind        = 12;

enum class Nlhe2Error : std::uint8_t {
    None = 0, BadMagic, BadVersion, BadLength, BadReserved, BadFlags,
    BadLogicalId, BadWeight, BadHome, BadMemberCount, BadRole,
    BadMemberPoint, DuplicateMember, BadRepresentative, BadLeafKind,
    BadDirected, BadCrossSpace
};

constexpr std::string_view nlhe2_error_name(Nlhe2Error e) noexcept {
    switch (e) {
    case Nlhe2Error::None: return "none";
    case Nlhe2Error::BadMagic: return "bad magic";
    case Nlhe2Error::BadVersion: return "bad version";
    case Nlhe2Error::BadLength: return "bad length";
    case Nlhe2Error::BadReserved: return "bad reserved";
    case Nlhe2Error::BadFlags: return "bad flags";
    case Nlhe2Error::BadLogicalId: return "bad logical id";
    case Nlhe2Error::BadWeight: return "bad weight";
    case Nlhe2Error::BadHome: return "bad home";
    case Nlhe2Error::BadMemberCount: return "bad member count";
    case Nlhe2Error::BadRole: return "bad role";
    case Nlhe2Error::BadMemberPoint: return "bad member point";
    case Nlhe2Error::DuplicateMember: return "duplicate member";
    case Nlhe2Error::BadRepresentative: return "bad representative";
    case Nlhe2Error::BadLeafKind: return "bad leaf kind";
    case Nlhe2Error::BadDirected: return "bad directed";
    case Nlhe2Error::BadCrossSpace: return "bad cross-space";
    }
    return "unknown";
}

struct Nlhe2Member {
    TensorPointRef point{};
    std::uint8_t role = kNlhe2RoleMember;
    std::uint8_t leaf_kind = 0;
    friend constexpr bool operator==(const Nlhe2Member&,
                                     const Nlhe2Member&) = default;
};

struct Nlhe2Record {
    std::uint16_t flags = 0;
    std::uint64_t logical_edge_id = 0;
    std::uint64_t label = 0;
    std::uint32_t weight_q16 = 65536;
    std::uint64_t epoch = 0;
    TensorPointRef home{};
    std::vector<Nlhe2Member> members;
    friend bool operator==(const Nlhe2Record&, const Nlhe2Record&) = default;
};

struct Nlhe2DecodeResult {
    Nlhe2Record record{};
    Nlhe2Error error = Nlhe2Error::None;
    explicit operator bool() const noexcept { return error == Nlhe2Error::None; }
};

inline void nlhe2_put_u16(std::uint8_t* p, std::uint16_t v) noexcept {
    p[0] = static_cast<std::uint8_t>(v);
    p[1] = static_cast<std::uint8_t>(v >> 8);
}
inline void nlhe2_put_u32(std::uint8_t* p, std::uint32_t v) noexcept {
    for (unsigned i = 0; i < 4; ++i)
        p[i] = static_cast<std::uint8_t>(v >> (8 * i));
}
inline void nlhe2_put_u64(std::uint8_t* p, std::uint64_t v) noexcept {
    for (unsigned i = 0; i < 8; ++i)
        p[i] = static_cast<std::uint8_t>(v >> (8 * i));
}
inline std::uint16_t nlhe2_get_u16(const std::uint8_t* p) noexcept {
    return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
}
inline std::uint32_t nlhe2_get_u32(const std::uint8_t* p) noexcept {
    return static_cast<std::uint32_t>(p[0]) |
        (static_cast<std::uint32_t>(p[1]) << 8) |
        (static_cast<std::uint32_t>(p[2]) << 16) |
        (static_cast<std::uint32_t>(p[3]) << 24);
}
inline std::uint64_t nlhe2_get_u64(const std::uint8_t* p) noexcept {
    std::uint64_t v = 0;
    for (unsigned i = 0; i < 8; ++i)
        v |= static_cast<std::uint64_t>(p[i]) << (8 * i);
    return v;
}

inline Nlhe2Error validate_nlhe2(const Nlhe2Record& r) noexcept {
    if (r.logical_edge_id == 0) return Nlhe2Error::BadLogicalId;
    if (r.weight_q16 == 0) return Nlhe2Error::BadWeight;
    if (!r.home.valid()) return Nlhe2Error::BadHome;
    if ((r.flags & ~kNlhe2KnownFlags) != 0) return Nlhe2Error::BadFlags;
    if (r.members.size() < 2 || r.members.size() > kNlhe2MaxMembers)
        return Nlhe2Error::BadMemberCount;

    unsigned representatives = 0;
    bool tail = false, head = false;
    bool cross_space = false;
    for (std::size_t i = 0; i < r.members.size(); ++i) {
        const auto& m = r.members[i];
        if (!m.point.valid()) return Nlhe2Error::BadMemberPoint;
        if ((m.role & kNlhe2RoleMember) == 0 ||
            (m.role & ~kNlhe2KnownRoles) != 0)
            return Nlhe2Error::BadRole;
        if (m.leaf_kind > kNlhe2MaxLeafKind)
            return Nlhe2Error::BadLeafKind;
        if (m.role & kNlhe2RoleRepresentative) ++representatives;
        if (m.role & kNlhe2RoleTail) tail = true;
        if (m.role & kNlhe2RoleHead) head = true;
        if (m.point.h() != r.home.h()) cross_space = true;
        for (std::size_t j = 0; j < i; ++j)
            if (r.members[j].point == m.point)
                return Nlhe2Error::DuplicateMember;
    }
    if (representatives != 1) return Nlhe2Error::BadRepresentative;
    if (r.flags & kNlhe2FlagDirected) {
        if (!tail || !head) return Nlhe2Error::BadDirected;
        for (const auto& m : r.members)
            if ((m.role & kNlhe2RoleTail) && (m.role & kNlhe2RoleHead))
                return Nlhe2Error::BadDirected;
    } else if (tail || head) {
        return Nlhe2Error::BadDirected;
    }
    const bool flag_cross = (r.flags & kNlhe2FlagCrossSpace) != 0;
    if (flag_cross != cross_space) return Nlhe2Error::BadCrossSpace;
    return Nlhe2Error::None;
}

inline std::vector<std::uint8_t> encode_nlhe2(const Nlhe2Record& r) {
    if (validate_nlhe2(r) != Nlhe2Error::None)
        throw std::invalid_argument("invalid NLHE2 record");
    std::vector<std::uint8_t> out(kNlhe2HeaderBytes +
                                  kNlhe2MemberBytes * r.members.size(), 0);
    out[0] = 'N'; out[1] = 'L'; out[2] = 'H'; out[3] = 'E';
    out[4] = kNlhe2Version;
    out[5] = 0;
    nlhe2_put_u16(out.data() + 6, r.flags);
    nlhe2_put_u64(out.data() + 8, r.logical_edge_id);
    nlhe2_put_u64(out.data() + 16, r.label);
    nlhe2_put_u32(out.data() + 24, r.weight_q16);
    nlhe2_put_u32(out.data() + 28, r.home.bits);
    nlhe2_put_u64(out.data() + 32, r.epoch);
    nlhe2_put_u16(out.data() + 40, static_cast<std::uint16_t>(r.members.size()));
    for (std::size_t i = 0; i < r.members.size(); ++i) {
        auto* p = out.data() + kNlhe2HeaderBytes + i * kNlhe2MemberBytes;
        nlhe2_put_u32(p, r.members[i].point.bits);
        p[4] = r.members[i].role;
        p[5] = r.members[i].leaf_kind;
    }
    return out;
}

inline Nlhe2DecodeResult decode_nlhe2(std::span<const std::uint8_t> bytes) {
    Nlhe2DecodeResult result{};
    if (bytes.size() < kNlhe2HeaderBytes) {
        result.error = Nlhe2Error::BadLength;
        return result;
    }
    if (!(bytes[0] == 'N' && bytes[1] == 'L' &&
          bytes[2] == 'H' && bytes[3] == 'E')) {
        result.error = Nlhe2Error::BadMagic;
        return result;
    }
    if (bytes[4] != kNlhe2Version) {
        result.error = Nlhe2Error::BadVersion;
        return result;
    }
    if (bytes[5] != 0 || bytes[42] != 0 || bytes[43] != 0 ||
        bytes[44] != 0 || bytes[45] != 0 || bytes[46] != 0 || bytes[47] != 0) {
        result.error = Nlhe2Error::BadReserved;
        return result;
    }
    auto& r = result.record;
    r.flags = nlhe2_get_u16(bytes.data() + 6);
    r.logical_edge_id = nlhe2_get_u64(bytes.data() + 8);
    r.label = nlhe2_get_u64(bytes.data() + 16);
    r.weight_q16 = nlhe2_get_u32(bytes.data() + 24);
    const auto home = TensorPointRef::from_bits(nlhe2_get_u32(bytes.data() + 28));
    if (!home) {
        result.error = Nlhe2Error::BadHome;
        return result;
    }
    r.home = *home;
    r.epoch = nlhe2_get_u64(bytes.data() + 32);
    const unsigned count = nlhe2_get_u16(bytes.data() + 40);
    if (count < 2 || count > kNlhe2MaxMembers) {
        result.error = Nlhe2Error::BadMemberCount;
        return result;
    }
    if (bytes.size() != kNlhe2HeaderBytes + kNlhe2MemberBytes * count) {
        result.error = Nlhe2Error::BadLength;
        return result;
    }
    r.members.reserve(count);
    for (unsigned i = 0; i < count; ++i) {
        const auto* p = bytes.data() + kNlhe2HeaderBytes + i * kNlhe2MemberBytes;
        const auto point = TensorPointRef::from_bits(nlhe2_get_u32(p));
        if (!point) {
            result.error = Nlhe2Error::BadMemberPoint;
            return result;
        }
        Nlhe2Member m;
        m.point = *point;
        m.role = p[4];
        m.leaf_kind = p[5];
        if (p[6] != 0 || p[7] != 0) {
            result.error = Nlhe2Error::BadReserved;
            return result;
        }
        r.members.push_back(m);
    }
    result.error = validate_nlhe2(r);
    return result;
}

inline bool valid_nlhe2_payload(const std::vector<std::uint8_t>& bytes) {
    return static_cast<bool>(decode_nlhe2(bytes));
}

} // namespace nanlm
