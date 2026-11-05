#include "nanlm/ntf.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    const auto a = UniverseAddress::parse("nan://U-07/R-03/H-0x0180/T-108/model/a");
    CHECK(a.has_value());
    if (a) {
        CHECK_EQ(a->universe, 7u);
        CHECK_EQ(a->region, 3u);
        CHECK_EQ(a->head, 0x0180u);
        CHECK_EQ(a->generation, 108u);
        CHECK_EQ(a->object, std::string("model/a"));
        const auto b = UniverseAddress::parse(a->to_string());
        CHECK(b.has_value());
        if (b) {
            CHECK_EQ(b->universe, a->universe);
            CHECK_EQ(b->head, a->head);
            CHECK_EQ(b->generation, a->generation);
            CHECK_EQ(b->object, a->object);
        }
    }

    const auto hex_address = UniverseAddress::parse("nan://U-10/R-10/H-0x00AF/T-2");
    CHECK(hex_address.has_value());
    if (hex_address) {
        CHECK_EQ(hex_address->universe, 16u);
        CHECK_EQ(hex_address->region, 10u);
        CHECK_EQ(hex_address->head, 0x00AFu);
        const auto roundtrip = UniverseAddress::parse(hex_address->to_string());
        CHECK(roundtrip.has_value());
        if (roundtrip) CHECK_EQ(roundtrip->universe, 16u);
    }

    NodeId owner = NodeId::from_hex(
        "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff");
    CHECK(owner.valid);
    CHECK_EQ(owner.hex().size(), 64u);

    MappingRecord m;
    m.universe = 7;
    m.mapping_version = 3;
    m.generation = 108;
    m.topology_root[0] = 0xAA;
    m.owner = owner;
    m.providers.push_back(owner);
    m.locators.push_back({"tcp", "node-a.example", 7401, "nan"});
    m.locators.push_back({"quic", "node-b.example", 7402, "nan"});
    m.expiry_unix = 1000;
    m.capabilities = kCapRead | kCapWrite | kCapExec;
    m.suite = CryptoSuite::Nsp8;
    m.signature[0] = 1; // test signature placeholder

    TranslationFabric fabric;
    std::string err;
    CHECK(!fabric.publish(m, 100, &err));
    fabric.set_signature_verifier([](const MappingRecord& record, const Hash256&) {
        return record.signature[0] == 1;
    });
    CHECK(fabric.publish(m, 100, &err));
    const auto r = fabric.resolve(7, 200, 108);
    CHECK(r.ok);
    CHECK_EQ(r.locators.size(), 2u);
    CHECK_EQ(r.mapping.generation, 108u);
    CHECK(r.mapping.digest() == m.digest());

    const auto route = fabric.route(*a, 200);
    CHECK(route.ok);
    CHECK_EQ(route.locators[0].host, std::string("node-a.example"));

    // Stale version and generation are rejected.
    MappingRecord stale = m;
    stale.mapping_version = 3;
    CHECK(!fabric.publish(stale, 200, &err));
    stale.mapping_version = 4;
    stale.generation = 107;
    CHECK(!fabric.publish(stale, 200, &err));

    // Expiry is rejected on resolve.
    CHECK(!fabric.resolve(7, 1001).ok);
    // Unknown universe.
    CHECK(!fabric.resolve(8, 200).ok);

    // Revoke requires the owner.
    NodeId other = owner;
    other.bytes[0] ^= 0xFF;
    CHECK(!fabric.revoke(7, other));
    CHECK(fabric.revoke(7, owner));
    CHECK_EQ(fabric.size(), 0u);

    // Temporal handoff validation.
    TranslationFabric f2;
    f2.set_signature_verifier([](const MappingRecord& record, const Hash256&) {
        return record.signature[0] == 1;
    });
    CHECK(f2.publish(m, 100));
    TemporalHandoff h;
    h.source.universe = 3;
    h.source_generation = 99;
    h.destination = *a;
    h.destination_generation = 108;
    h.epoch = 42;
    h.phase = 0;
    h.payload[0] = 1;
    CHECK(validate_handoff(h, f2.resolve(7, 200).mapping, 200, &err));
    h.destination_generation = 107;
    CHECK(!validate_handoff(h, f2.resolve(7, 200).mapping, 200, &err));
    h.destination_generation = 108;
    CHECK(!validate_handoff(h, f2.resolve(7, 200).mapping, 1001, &err));

    // Mesh registry.
    MeshRegistry mesh;
    MeshPeer p;
    p.id = owner;
    p.locators.push_back({"tcp", "node-a.example", 7401, "nan"});
    p.capabilities = kCapRead | kCapStore;
    CHECK(mesh.advertise(p, 100, &err));
    CHECK(mesh.find(owner).has_value());
    CHECK_EQ(mesh.peers().size(), 1u);
    CHECK_EQ(mesh.expire(200, 50), 1u);
    CHECK(!mesh.find(owner).has_value());

    return test_done("NaN Translation Fabric");
}
