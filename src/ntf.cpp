#include "nanlm/ntf.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <cstdlib>
#include <sstream>

namespace nanlm {
namespace {

std::optional<std::uint64_t> parse_number(std::string_view s) {
    if (s.empty()) return std::nullopt;
    std::string tmp(s);
    char* end = nullptr;
    const unsigned long long v = std::strtoull(tmp.c_str(), &end, 0);
    if (!end || *end != '\0') return std::nullopt;
    return static_cast<std::uint64_t>(v);
}

std::vector<std::string> split(std::string_view text, char sep) {
    std::vector<std::string> out;
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t pos = text.find(sep, start);
        if (pos == std::string_view::npos) {
            out.emplace_back(text.substr(start));
            break;
        }
        out.emplace_back(text.substr(start, pos - start));
        start = pos + 1;
    }
    return out;
}

std::uint8_t hex_nibble(char c) {
    if (c >= '0' && c <= '9') return static_cast<std::uint8_t>(c - '0');
    if (c >= 'a' && c <= 'f') return static_cast<std::uint8_t>(10 + c - 'a');
    if (c >= 'A' && c <= 'F') return static_cast<std::uint8_t>(10 + c - 'A');
    return 0xFF;
}

} // namespace

NodeId NodeId::from_hex(std::string_view text) {
    NodeId id;
    if (text.size() != 64) return id;
    for (std::size_t i = 0; i < 32; ++i) {
        const std::uint8_t hi = hex_nibble(text[i * 2]);
        const std::uint8_t lo = hex_nibble(text[i * 2 + 1]);
        if (hi == 0xFF || lo == 0xFF) return id;
        id.bytes[i] = static_cast<std::uint8_t>((hi << 4) | lo);
    }
    id.valid = true;
    return id;
}

std::string NodeId::hex() const {
    static constexpr char digits[] = "0123456789abcdef";
    std::string out;
    out.reserve(64);
    for (std::uint8_t b : bytes) {
        out.push_back(digits[b >> 4]);
        out.push_back(digits[b & 0x0Fu]);
    }
    return out;
}

std::string PhysicalLocator::to_string() const {
    std::ostringstream os;
    os << scheme << "://" << host;
    if (port) os << ':' << port;
    if (!path.empty()) os << '/' << path;
    return os.str();
}

std::string UniverseAddress::to_string() const {
    std::ostringstream os;
    os << "nan://U-" << std::hex << std::uppercase << universe
       << "/R-" << static_cast<unsigned>(region)
       << "/H-0x" << head
       << "/T-" << std::dec << generation;
    if (!object.empty()) os << '/' << object;
    return os.str();
}

std::optional<UniverseAddress> UniverseAddress::parse(std::string_view text) {
    if (text.substr(0, 6) != "nan://") return std::nullopt;
    const std::string rest(text.substr(6));
    const auto parts = split(rest, '/');
    if (parts.size() < 4) return std::nullopt;
    UniverseAddress a;
    for (std::size_t i = 0; i < 4; ++i) {
        const std::string& p = parts[i];
        if (p.rfind("U-", 0) == 0) {
            auto v = parse_number(p.substr(2));
            if (!v || *v > 0xFFFF) return std::nullopt;
            a.universe = static_cast<std::uint16_t>(*v);
        } else if (p.rfind("R-", 0) == 0) {
            auto v = parse_number(p.substr(2));
            if (!v || *v > 0xFF) return std::nullopt;
            a.region = static_cast<std::uint8_t>(*v);
        } else if (p.rfind("H-", 0) == 0) {
            auto v = parse_number(p.substr(2));
            if (!v || *v > 0xFFFF) return std::nullopt;
            a.head = static_cast<std::uint16_t>(*v);
        } else if (p.rfind("T-", 0) == 0) {
            auto v = parse_number(p.substr(2));
            if (!v) return std::nullopt;
            a.generation = *v;
        } else {
            return std::nullopt;
        }
    }
    if (parts.size() > 4) {
        for (std::size_t i = 4; i < parts.size(); ++i) {
            if (i > 4) a.object.push_back('/');
            a.object += parts[i];
        }
    }
    return a;
}

Hash256 MappingRecord::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'N', 'T', 'F', '0', '1'};
    h.update(tag, sizeof(tag));
    h.update(&universe, sizeof(universe));
    h.update(&mapping_version, sizeof(mapping_version));
    h.update(&generation, sizeof(generation));
    h.update(topology_root.data(), topology_root.size());
    h.update(owner.bytes.data(), owner.bytes.size());
    const auto providers_n = static_cast<std::uint32_t>(providers.size());
    h.update(&providers_n, sizeof(providers_n));
    for (const NodeId& p : providers) h.update(p.bytes.data(), p.bytes.size());
    const auto locators_n = static_cast<std::uint32_t>(locators.size());
    h.update(&locators_n, sizeof(locators_n));
    for (const PhysicalLocator& l : locators) {
        h.update(l.scheme.data(), l.scheme.size());
        h.update(l.host.data(), l.host.size());
        h.update(&l.port, sizeof(l.port));
        h.update(l.path.data(), l.path.size());
    }
    h.update(&expiry_unix, sizeof(expiry_unix));
    h.update(&capabilities, sizeof(capabilities));
    h.update(&suite, sizeof(suite));
    h.update(signature.data(), signature.size());
    return h.final();
}

bool TranslationFabric::publish(const MappingRecord& record, std::uint64_t now,
                                std::string* error) {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    if (record.locators.empty()) return fail("mapping has no locators");
    if (!record.signature_present()) return fail("mapping is unsigned");
    if (record.expiry_unix <= now) return fail("mapping already expired");
    auto it = mappings_.find(record.universe);
    if (it != mappings_.end()) {
        if (record.mapping_version <= it->second.mapping_version)
            return fail("stale mapping version");
        if (record.generation < it->second.generation)
            return fail("stale universe generation");
    }
    mappings_[record.universe] = record;
    return true;
}

RouteResultNTF TranslationFabric::resolve(std::uint16_t universe, std::uint64_t now,
                                          std::uint64_t min_generation) const {
    RouteResultNTF r;
    auto it = mappings_.find(universe);
    if (it == mappings_.end()) {
        r.error = "universe not registered";
        return r;
    }
    if (!it->second.signature_present()) {
        r.error = "mapping is unsigned";
        return r;
    }
    if (it->second.expiry_unix <= now) {
        r.error = "mapping expired";
        return r;
    }
    if (it->second.generation < min_generation) {
        r.error = "stale universe generation";
        return r;
    }
    r.ok = true;
    r.mapping = it->second;
    r.locators = it->second.locators;
    return r;
}

RouteResultNTF TranslationFabric::route(const UniverseAddress& address,
                                        std::uint64_t now) const {
    return resolve(address.universe, now, address.generation);
}

bool TranslationFabric::revoke(std::uint16_t universe, const NodeId& owner) {
    auto it = mappings_.find(universe);
    if (it == mappings_.end()) return false;
    if (!(it->second.owner == owner)) return false;
    mappings_.erase(it);
    return true;
}

bool validate_handoff(const TemporalHandoff& handoff, const MappingRecord& destination,
                      std::uint64_t now, std::string* error) {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    if (handoff.destination.universe != destination.universe)
        return fail("destination universe mismatch");
    if (handoff.destination_generation != destination.generation)
        return fail("stale destination generation");
    if (destination.expiry_unix <= now) return fail("destination mapping expired");
    if (handoff.phase > 1) return fail("invalid temporal phase");
    if (handoff.epoch == 0 && handoff.destination.generation == 0)
        return fail("missing temporal epoch");
    if (error) error->clear();
    return true;
}

bool MeshRegistry::advertise(const MeshPeer& peer, std::uint64_t now, std::string* error) {
    if (!peer.id.valid) {
        if (error) *error = "invalid peer id";
        return false;
    }
    if (peer.locators.empty()) {
        if (error) *error = "peer has no locators";
        return false;
    }
    MeshPeer p = peer;
    p.last_seen = now;
    peers_[p.id.hex()] = p;
    return true;
}

std::optional<MeshPeer> MeshRegistry::find(const NodeId& id) const {
    auto it = peers_.find(id.hex());
    if (it == peers_.end()) return std::nullopt;
    return it->second;
}

std::vector<MeshPeer> MeshRegistry::peers() const {
    std::vector<MeshPeer> out;
    out.reserve(peers_.size());
    for (const auto& kv : peers_) out.push_back(kv.second);
    return out;
}

std::size_t MeshRegistry::expire(std::uint64_t now, std::uint64_t max_age) {
    std::size_t removed = 0;
    for (auto it = peers_.begin(); it != peers_.end();) {
        if (it->second.last_seen + max_age < now) {
            it = peers_.erase(it);
            ++removed;
        } else {
            ++it;
        }
    }
    return removed;
}

} // namespace nanlm
