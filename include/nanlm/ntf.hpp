// NaN Translation Fabric (NTF).
//
// Three address domains:
//   physical  scheme://host:port/path
//   universe  nan://U-xxxx/R-xx/H-0xhhhh/T-generation[/object]
//   semantic  model / corpus / service / resource key
//
// The fabric resolves a logical universe address to one or more physical
// locators without letting the physical address become the identity. Mapping
// records are versioned, generation-stamped, expiring, and signed (the crypto
// verifier is a hook; NaN/0S supplies Ed25519 / ML-KEM / SHA3 / NSP8).
#pragma once

#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

enum class CryptoSuite : std::uint8_t {
    Ed25519 = 0,
    MlKem = 1,
    Sha3 = 2,
    Nsp8 = 3,
};

inline constexpr std::uint32_t kCapRead = 1u << 0;
inline constexpr std::uint32_t kCapWrite = 1u << 1;
inline constexpr std::uint32_t kCapExec = 1u << 2;
inline constexpr std::uint32_t kCapStore = 1u << 3;
inline constexpr std::uint32_t kCapRelay = 1u << 4;
inline constexpr std::uint32_t kCapAdmin = 1u << 5;

struct NodeId {
    std::array<std::uint8_t, 32> bytes{};
    bool valid = false;
    static NodeId from_hex(std::string_view hex);
    std::string hex() const;
    bool operator==(const NodeId& other) const { return bytes == other.bytes; }
};

struct PhysicalLocator {
    std::string scheme = "tcp";
    std::string host;
    std::uint16_t port = 0;
    std::string path;
    std::string to_string() const;
};

struct UniverseAddress {
    std::uint16_t universe = 0;
    std::uint8_t region = 0;
    std::uint16_t head = 0;
    std::uint64_t generation = 0;
    std::string object;

    std::string to_string() const;
    static std::optional<UniverseAddress> parse(std::string_view text);
};

struct MappingRecord {
    std::uint16_t universe = 0;
    std::uint64_t mapping_version = 0;
    std::uint64_t generation = 0;
    Hash256 topology_root{};
    NodeId owner{};
    std::vector<NodeId> providers;
    std::vector<PhysicalLocator> locators;
    std::uint64_t expiry_unix = 0;
    std::uint32_t capabilities = 0;
    CryptoSuite suite = CryptoSuite::Ed25519;
    std::array<std::uint8_t, 64> signature{};

    Hash256 digest() const;
    bool signature_present() const { return signature[0] != 0; }
};

struct RouteResultNTF {
    bool ok = false;
    MappingRecord mapping{};
    std::vector<PhysicalLocator> locators;
    std::string error;
};

class TranslationFabric {
public:
    bool publish(const MappingRecord& record, std::uint64_t now, std::string* error = nullptr);
    RouteResultNTF resolve(std::uint16_t universe, std::uint64_t now,
                           std::uint64_t min_generation = 0) const;
    RouteResultNTF route(const UniverseAddress& address, std::uint64_t now) const;
    bool revoke(std::uint16_t universe, const NodeId& owner);
    std::size_t size() const { return mappings_.size(); }

private:
    std::unordered_map<std::uint16_t, MappingRecord> mappings_;
};

struct TemporalHandoff {
    UniverseAddress source{};
    UniverseAddress destination{};
    std::uint64_t source_generation = 0;
    std::uint64_t destination_generation = 0;
    std::uint64_t epoch = 0;
    std::uint8_t phase = 0;
    Hash256 payload{};
};

bool validate_handoff(const TemporalHandoff& handoff, const MappingRecord& destination,
                      std::uint64_t now, std::string* error = nullptr);

struct MeshPeer {
    NodeId id{};
    std::vector<PhysicalLocator> locators;
    std::uint32_t capabilities = 0;
    std::uint64_t last_seen = 0;
};

class MeshRegistry {
public:
    bool advertise(const MeshPeer& peer, std::uint64_t now, std::string* error = nullptr);
    std::optional<MeshPeer> find(const NodeId& id) const;
    std::vector<MeshPeer> peers() const;
    std::size_t expire(std::uint64_t now, std::uint64_t max_age);

private:
    std::unordered_map<std::string, MeshPeer> peers_;
};

} // namespace nanlm
