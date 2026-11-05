#include "nanlm/global.hpp"
#include "nanlm/ledger.hpp"
#include "nanlm/pager.hpp"
#include "nanlm/resonance.hpp"
#include "nanlm/ring.hpp"
#include "nanlm/router.hpp"
#include "nanlm/ntf.hpp"
#include "nanlm/byte_model.hpp"
#include "nanlm/slot_memory.hpp"
#include "nanlm/context2.hpp"
#include "nanlm/vector_store.hpp"
#include "nanlm/handoff.hpp"
#include "nanlm/schedule.hpp"
#include "nanlm/universe.hpp"

#include <cctype>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <fstream>
#include <iterator>
#include <iostream>
#include <memory>
#include <string>

namespace {

using namespace nanlm;

int failures = 0;

void check(bool ok, const std::string& name) {
    std::cout << (ok ? "PASS  " : "FAIL  ") << name << "\n";
    if (!ok) ++failures;
}

int cmd_verify() {
    std::cout << "NaNLM Universal — core verification\n\n";

    check(kAddressCount == 65536, "65,536 addresses");
    check(kFixedPointCount == 256, "256 palindromic fixed points");
    check(kMirrorPairCount == 32640, "32,640 mirror pairs");
    check(kCanonicalCount == 32896, "32,896 canonical cells");
    check(kMirrorPairCount == (kFixedPointCount * (kFixedPointCount - 1)) / 2,
          "32,640 == C(256,2)");

    bool pair_ok = true;
    for (std::uint32_t p = 0; p < kMirrorPairCount; ++p) {
        const auto [a, b] = pair_heads(p);
        if (a >= b || pair_index(a, b) != p) pair_ok = false;
    }
    check(pair_ok, "pair index round-trips over all 32,640 pairs");

    bool transpose_ok = true;
    std::uint32_t fixed = 0;
    for (std::uint32_t i = 0; i < kAddressCount; ++i) {
        const auto a = static_cast<std::uint16_t>(i);
        const auto r = matrix_row(a);
        const auto c = matrix_col(a);
        if (reverse16(a) != matrix_addr(c, r)) transpose_ok = false;
        if (is_palindrome16(a)) ++fixed;
        if (reverse16(reverse16(a)) != a) transpose_ok = false;
    }
    check(transpose_ok, "reverse16 is matrix transposition for all 65,536 addresses");
    check(fixed == 256, "exactly 256 addresses are palindromic");

    bool bool_ok = true;
    for (std::uint8_t n = 0; n < 16; ++n) {
        const std::uint32_t a = 0xCCCCCCCCu;
        const std::uint32_t b = 0xAAAAAAAAu;
        const std::uint32_t expect = static_cast<std::uint32_t>(n) * 0x11111111u;
        if (NanWord::eval_bool(n, a, b) != expect) bool_ok = false;
        for (int lane = 0; lane < 32; ++lane) {
            const std::uint32_t av = (a >> lane) & 1u;
            const std::uint32_t bv = (b >> lane) & 1u;
            const std::uint32_t bit = (NanWord::eval_bool(n, a, b) >> lane) & 1u;
            if (bit != ((n >> (2u * av + bv)) & 1u)) bool_ok = false;
        }
    }
    check(bool_ok, "all 16 Boolean functions match their truth tables");
    check(NanWord::eval_bool(6, 0xCCCCCCCCu, 0xAAAAAAAAu) == 0x66666666u,
          "lane identity: XOR(0xCCCCCCCC, 0xAAAAAAAA) == 0x66666666");

    bool mirror_law = true;
    for (std::uint8_t n = 0; n < 16; ++n) {
        const std::uint32_t a = 0xCCCCCCCCu;
        const std::uint32_t b = 0xAAAAAAAAu;
        if (NanWord::eval_bool(rot2(n), a, b) != NanWord::eval_bool(n, ~a, b)) {
            mirror_law = false;
        }
    }
    check(mirror_law, "mirror law: BOOL.rot2(n)(a,b) == BOOL.n(~a,b)");

    const NanWord w = NanWord::make(NanType::SignalPositive, NanType::QuietNegative, 0xDEADBEEFu);
    check(w.valid(), "NaN16 word with legal heads is valid");
    check(w.far_head() == 0x7FF1 && w.near_head() == 0xFFF8, "far/near heads round-trip");
    check(w.payload() == 0xDEADBEEFu, "payload round-trips");
    check(w.bswap().bswap().raw == w.raw, "BSWAPM is an involution");
    check(w.bswap().opcode() == rot2(w.opcode()), "BSWAPM rotates the class nibble");

    Universe u1(0x0123456789ABCDEFull);
    Universe u2(0x0123456789ABCDEFull);
    std::string err;
    check(u1.verify(&err), "universe structural verification " + err);
    check(u1.digest() == u2.digest(), "genesis is deterministic");
    check(u1.at(0, 0).is_head() && u1.at(255, 255).is_head(),
          "all 256 diagonal cells are heads");
    check(u1.at(0, 1).is_pair() && u1.at(1, 0).is_pair(),
          "off-diagonal cells are pair cells");
    check(u1.descriptor_pair(pair_index(0, 1)).head_a == 0 &&
              u1.descriptor_pair(pair_index(0, 1)).head_b == 1,
          "pair descriptor links the two heads");
    check(u1.adjacent(0, 1) && u1.adjacent(1, 0), "adjacency bitmap is symmetric");
    check(!u1.adjacent(0, 0), "diagonal is not an edge");

    // Bit-level paging and copy-on-write.
    PageTable table;
    auto root = std::make_shared<Universe>(0);
    check(table.map(PageId::root(), root), "map root universe");
    const BitAddress bit{PageId::root(), matrix_addr(0, 1), 0, 5};
    check(table.write_bit(bit, true), "write one bit");
    bool value = false;
    check(table.read_bit(bit, value) && value, "read the same bit");
    check(table.dirty_cell_count(PageId::root()) == 1, "dirty cell tracked");

    const PageId alias = PageId::child(PageId::root(), 42);
    check(table.map(alias, root), "map a child alias to the same page");
    const BitAddress abit{alias, matrix_addr(0, 1), 0, 5};
    check(table.write_bit(abit, false), "write through alias (COW)");
    bool root_value = true;
    bool alias_value = true;
    check(table.read_bit(bit, root_value) && root_value, "root keeps the old bit");
    check(table.read_bit(abit, alias_value) && !alias_value, "alias has the new bit");
    check(table.entry(PageId::root())->page != table.entry(alias)->page,
          "COW cloned the page");
    const Hash256 root_before = table.root_hash();
    check(table.write_bit(bit, false), "write root again");
    check(!(table.root_hash() == root_before), "root hash changes after a write");

    // Ledger chain and tamper detection.
    Ledger ledger;
    for (int i = 0; i < 100; ++i) {
        Hash256 before{};
        Hash256 after{};
        before[0] = static_cast<std::uint8_t>(i);
        after[0] = static_cast<std::uint8_t>(i + 1);
        ledger.append(1, 1, static_cast<std::uint64_t>(i), before, after);
    }
    check(ledger.verify(&err), "100-event ledger verifies");
    Ledger copy = Ledger::from_bytes(ledger.serialize().data(), ledger.serialize().size());
    check(copy.verify(&err), "ledger serializes and restores");
    check(ledger.head() == copy.head(), "restored ledger has the same head");
    Ledger tampered = ledger;
    tampered = Ledger::from_bytes(ledger.serialize().data(), ledger.serialize().size());
    // Re-serialize with one event byte flipped.
    auto bytes = ledger.serialize();
    const std::size_t event_offset = 8 + 32 + 32 + 8;
    bytes[event_offset + 50 * sizeof(Event) + 7] ^= 0x01u;
    Ledger broken = Ledger::from_bytes(bytes.data(), bytes.size());
    check(!broken.verify(&err), "tampered ledger is rejected");

    // Resonance.
    ResonanceLattice r;
    check(r.coupling(0, 1) == r.coupling(1, 0), "resonance coupling is symmetric");
    const int steps = r.propagate(0, 255, 19661, 500);
    check(steps > 0, "wave reaches the opposite corner in " + std::to_string(steps) + " steps");
    check(r.coherence() >= 0 && r.coherence() <= 65536, "coherence is in range");
    ResonanceLattice r2;
    ResonanceLattice r3;
    check(r2.digest() == r3.digest(), "resonance is deterministic");

    // One global topology: charts are coordinate regions, not separate minds.
    GlobalTopology g(0x1234);
    check(g.chart_count() == 1, "initial brain is exactly one chart");
    const PageId child = g.add_chart(PageId::root(), 7);
    check(g.has_chart(child) && g.chart_count() == 2, "a chart is added to the same object");
    const BitAddress root_bit{PageId::root(), matrix_addr(0, 1), 0, 0};
    const BitAddress child_bit{child, matrix_addr(1, 2), 0, 0};
    Hyperedge cross;
    cross.label = 1;
    cross.members = {Ref::from_bit(root_bit), Ref::from_bit(child_bit)};
    check(g.hypergraph().add(cross) != 0, "cross-space hyperedge is a field of the one object");
    check(g.temporal().link(Ref::from_bit(root_bit), Ref::from_bit(child_bit), 1) != 0,
          "temporal link is a field of the one object");
    check(g.ledger().verify(), "one global ledger verifies");
    GlobalTopology g2(0x1234);
    g2.add_chart(PageId::root(), 7);
    g2.hypergraph().add(cross);
    g2.temporal().link(Ref::from_bit(root_bit), Ref::from_bit(child_bit), 1);
    check(g.global_digest() == g2.global_digest(), "global identity is deterministic");
    const BitAddress mirrored = GlobalTopology::mirror(root_bit);
    check(mirrored.cell == reverse16(root_bit.cell), "global mirror is the chart-local involution");

    HeadArray heads = g.root_heads();
    check(heads.verify(), "256-head palindromic layer verifies");
    check(heads.digest() == g2.root_heads().digest(), "head layer is deterministic");
    HeadRunner runner(heads, PageId::root(), &g.temporal());
    HeadToken token;
    token.payload = 9;
    token.epoch = 100;
    const RunnerResult handoff = runner.run(0, token);
    check(handoff.ok && handoff.next == 1, "runner follows the first topology edge");
    check(handoff.out.epoch == 101, "runner preserves and advances the epoch");
    check(heads.history(0).size() == 1, "head history records the handoff");

    TemporalClock c;
    check(c.tick() == 0 && c.future() == ClockState::Halt, "clock genesis is HALT");
    c.step();
    check(c.past_rewrite() == ClockState::Loop && c.contradiction(),
          "clock produces the +qNaN -> LOOP contradiction");
    c.step();
    check(c.past_rewrite() == ClockState::Halt, "clock produces the -sNaN -> HALT rewrite");
    c.step();
    std::uint64_t cycle_start = 0, cycle_length = 0;
    check(c.cycle(cycle_start, cycle_length) && cycle_length == 2,
          "clock enters the period-2 temporal orbit");
    check(g.clock().tick() == 0, "global clock is a field of the one object");
    const Hash256 before_clock = g.global_digest();
    g.clock().step();
    check(!(g.global_digest() == before_clock), "clock is included in the global digest");

    std::cout << "\n" << (failures == 0 ? "ALL CHECKS PASSED" : "FAILURES: " + std::to_string(failures))
              << "\n";
    return failures == 0 ? 0 : 1;
}

void print_word(const char* label, const NanWord& w) {
    std::cout << label << " raw=0x" << std::hex << w.raw << std::dec
              << " op=" << static_cast<unsigned>(w.opcode()) << " ("
              << bool_op_name(w.opcode()) << ")"
              << " payload=0x" << std::hex << w.payload() << std::dec << "\n";
}

int cmd_genesis() {
    Universe u(0x4E614E4C4D000001ull);
    std::string err;
    if (!u.verify(&err)) {
        std::cerr << "genesis verification failed: " << err << "\n";
        return 1;
    }
    std::cout << "NaNLM Universal — genesis register file\n\n";
    std::cout << "digest        " << hex(u.digest()) << "\n";
    std::cout << "cells         " << u.canonical_count() << " ("
              << kFixedPointCount << " heads + " << kMirrorPairCount << " pairs)\n";
    std::cout << "page bytes    " << kPageBytes << " (8 MiB)\n";
    std::cout << "address regs  " << kAddressCount << " x " << sizeof(AddressReg)
              << " B (every address, both mirrors)\n";
    std::cout << "cell bytes    " << sizeof(NanCell) << "\n";
    std::cout << "descriptor    " << sizeof(Descriptor) << " bytes\n\n";

    const auto& h0 = u.head(0);
    std::cout << "head 0        fixed=0x" << std::hex << h0.fixed_addr << std::dec
              << " edges=" << h0.edge_count << " phase=" << h0.phase
              << " energy=" << h0.energy << "\n";
    print_word("  s+", u.head_cell(0).s_plus());
    print_word("  s-", u.head_cell(0).s_minus());
    print_word("  q+", u.head_cell(0).q_plus());
    print_word("  q-", u.head_cell(0).q_minus());

    const auto p = pair_index(0, 1);
    const auto& d = u.descriptor_pair(p);
    std::cout << "\npair (0,1)    index=" << d.pair << " canon=0x" << std::hex << d.canonical
              << " mirror=0x" << d.mirror << std::dec << " rule=" << unsigned(d.rule) << "\n";
    const auto& c = u.pair_cell(0, 1);
    print_word("  s+", c.s_plus());
    print_word("  s-", c.s_minus());
    print_word("  q+", c.q_plus());
    print_word("  q-", c.q_minus());
    std::cout << "  ops=0x" << std::hex << c.ops << std::dec << "\n";
    return 0;
}

int cmd_scale() {
    std::cout << "NaNLM Universal — scaling (one 8 MiB coordinate region per chart)\n\n";
    std::cout << "One global topology; a chart is a local coordinate region, not a mind.\n\n";
    std::cout << "depth  universes        addresses        canonical        pairs            fixed            dense\n";
    for (int d = 0; d <= 8; ++d) {
        const ScalePlan p = scale_plan(d);
        std::cout << d << "      " << u128_to_string(p.universes) << "  "
                  << u128_to_string(p.addresses) << "  "
                  << u128_to_string(p.canonical) << "  "
                  << u128_to_string(p.pairs) << "  "
                  << u128_to_string(p.fixed) << "  "
                  << human_bytes(p.dense_bytes) << "\n";
    }
    std::cout << "\n6 head-runner slots, 7 GiB each (placement of the one object):\n";
    for (int d = 1; d <= 4; ++d) {
        const RingPlan r = ring_plan(d, 6);
        std::cout << "  depth " << d << ": " << u128_to_string(r.total_universes)
                  << " universes, dense " << human_bytes(r.total_bytes)
                  << ", per node " << human_bytes(r.per_node_bytes)
                  << (r.all_fit ? " (fits)" : " (needs remote tiers)") << "\n";
    }
    return 0;
}

int cmd_resonance() {
    ResonanceLattice r;
    const int steps = r.propagate(0, 255, 19661, 500);
    std::cout << "NaNLM Universal — resonance\n\n";
    std::cout << "wave 0 -> 255: " << (steps < 0 ? "not reached" : std::to_string(steps) + " steps")
              << "\n";
    std::cout << "coherence: " << r.coherence() << " / 65536\n";
    std::cout << "digest: " << hex(r.digest()) << "\n";
    for (int i : {0, 1, 15, 16, 128, 240, 255}) {
        std::cout << "  head " << i << " energy=" << r.energy(i)
                  << " phase=" << r.node(i).phase << "\n";
    }
    return steps < 0 ? 1 : 0;
}

int cmd_bits() {
    PageTable table;
    auto root = std::make_shared<Universe>(0);
    table.map(PageId::root(), root);
    const auto addr = matrix_addr(3, 7);
    const BitAddress b{PageId::root(), addr, 0, 13};
    table.write_bit(b, true);
    bool v = false;
    table.read_bit(b, v);
    std::cout << "root bit " << static_cast<int>(v) << " dirty cells "
              << table.dirty_cell_count(PageId::root()) << "\n";

    const PageId child = PageId::child(PageId::root(), 3);
    table.map(child, table.resolve(PageId::root()));
    table.write_bit({child, addr, 0, 13}, false);
    bool rv = true, cv = true;
    table.read_bit(b, rv);
    table.read_bit({child, addr, 0, 13}, cv);
    std::cout << "after COW: root=" << rv << " child=" << cv
              << " root_hash=" << hex(table.root_hash()) << "\n";
    std::cout << "encoded bit address: 0x" << std::hex << b.encode() << std::dec << "\n";
    return (rv && !cv) ? 0 : 1;
}

int cmd_global() {
    GlobalTopology g(0x4E614E4C4D000001ull);
    const PageId child = g.add_chart(PageId::root(), 7);
    const BitAddress a{PageId::root(), matrix_addr(3, 9), 0, 5};
    const BitAddress b{child, matrix_addr(9, 3), 0, 5};
    g.write_bit(a, true);
    g.write_bit(b, true);
    Hyperedge e;
    e.label = 0x484F5045; // HOPE
    e.epoch = 1;
    e.members = {Ref::from_bit(a), Ref::from_bit(b)};
    g.hypergraph().add(e);
    g.temporal().link(Ref::from_bit(a), Ref::from_bit(b), 1, kTemporalBranch);
    g.commit(1, 9, 0, {}, {});

    std::cout << "NaNLM Universal — one global topology\n\n";
    std::cout << "charts        " << g.chart_count() << "\n";
    std::cout << "global digest " << hex(g.global_digest()) << "\n";
    std::cout << "pages digest  " << hex(g.pages().root_hash()) << "\n";
    std::cout << "hypergraph    " << g.hypergraph().size() << " hyperedges\n";
    std::cout << "temporal      " << g.temporal().size() << " links\n";
    std::cout << "ledger        " << g.ledger().size() << " events\n\n";
    for (const auto& c : g.charts()) {
        std::cout << "  chart " << c.to_string() << "\n";
    }
    std::cout << "\nThe 256 palindromic heads are present in every chart.\n";
    std::cout << "A chart is a local coordinate region, not a separate mind.\n";
    return 0;
}

int cmd_growth() {
    GlobalTopology g(0x4E614E4C4D000001ull);
    GrowthPolicy policy;
    HeadArray heads = g.root_heads();
    HeadView h = heads.at(0);
    for (int i = 0; i < policy.error_streak_required; ++i) {
        h.note_self_model_error(40000, policy.self_error_threshold,
                                policy.error_streak_required);
    }
    std::cout << "NaNLM Universal — growth and consolidation\n\n";
    std::cout << "head 0 error=" << h.self_error() << " streak="
              << static_cast<int>(h.error_streak()) << "\n";
    const PageId parent = PageId::root();
    const PageId child = g.grow_head(parent, 0, policy, 0x99);
    std::cout << "grew child " << child.to_string() << ", charts=" << g.chart_count()
              << ", manifest gen=" << g.manifest().generation << "\n";

    const auto* entry = g.pages().entry(parent);
    if (!entry) return 1;
    ScratchJournal j;
    j.id = 1;
    j.epoch = g.clock().tick();
    j.page = parent;
    j.base = entry->page->digest();
    j.ops.push_back({ScratchKind::Chart, 0, 0, {1, 2, 3}});
    j.ops.push_back({ScratchKind::HeadLocal, 0, 0, {0xAA, 0xBB}});
    const ConsolidationResult r = g.consolidate(j, 1);
    std::cout << "consolidate ok=" << r.ok << " gen=" << r.generation
              << " error=" << r.error << "\n";
    std::cout << "global digest " << hex(g.global_digest()) << "\n";
    return r.ok ? 0 : 1;
}

int cmd_snapshot(int argc, char** argv) {
    const char* out = "state/chart.nmc";
    for (int i = 2; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "--out") == 0) out = argv[i + 1];
    }
    Universe u(0x4E614E4C4D000001ull);
    const auto bytes = u.serialize();
    std::ofstream f(out, std::ios::binary);
    if (!f) { std::cerr << "cannot write " << out << "\n"; return 1; }
    f.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    std::cout << "snapshot " << out << " bytes=" << bytes.size()
              << " digest=" << hex(u.digest()) << "\n";
    return 0;
}

int cmd_headshift(int argc, char** argv) {
    int slot = 1;
    std::uint64_t epoch = 0;
    int runners = 6;
    std::string snapshot = "state/chart.nmc";
    std::string out = "state/chart.nmc";
    std::string json = "state/packets.json";
    for (int i = 2; i + 1 < argc; ++i) {
        const std::string key = argv[i];
        const std::string val = argv[i + 1];
        if (key == "--slot") slot = std::stoi(val);
        else if (key == "--epoch") epoch = std::stoull(val);
        else if (key == "--runners") runners = std::stoi(val);
        else if (key == "--snapshot") snapshot = val;
        else if (key == "--out") out = val;
        else if (key == "--json") json = val;
    }
    if (slot < 1 || slot > runners) { std::cerr << "slot out of range\n"; return 2; }
    std::unique_ptr<Universe> u;
    std::ifstream in(snapshot, std::ios::binary);
    if (in) {
        std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(in)),
                                        std::istreambuf_iterator<char>());
        u = Universe::from_bytes(bytes.data(), bytes.size());
    }
    if (!u) u = std::make_unique<Universe>(0x4E614E4C4D000001ull);

    HeadArray heads(*u, PageId::root());
    HeadMap map(static_cast<std::uint8_t>(runners));
    if (!map.valid()) { std::cerr << "invalid head map\n"; return 3; }
    std::vector<HeadPacket> packets;
    for (std::uint8_t head : map.heads_for(static_cast<std::uint8_t>(slot - 1))) {
        HeadView h = heads.at(head);
        HeadPacket p;
        p.head = head;
        p.epoch = epoch;
        p.phase = h.record().phase;
        p.transform_phase = h.transform_phase();
        p.self_error = h.self_error();
        p.scratch_used = h.scratch_used();
        p.state_hash = Universe::cell_checksum(h.cell());
        auto local = h.scratch().local();
        for (int i = 0; i < 32; ++i) p.output[i] = local[i];
        packets.push_back(p);
        h.advance_transform_phase();
        h.phase_step(static_cast<std::uint32_t>(epoch + head));
    }

    std::ofstream js(json);
    if (!js) { std::cerr << "cannot write " << json << "\n"; return 4; }
    js << "[\n";
    for (std::size_t i = 0; i < packets.size(); ++i) {
        const auto& p = packets[i];
        js << " {\"head\":" << static_cast<unsigned>(p.head)
           << ",\"epoch\":" << p.epoch
           << ",\"phase\":" << p.phase
           << ",\"transform_phase\":" << static_cast<unsigned>(p.transform_phase)
           << ",\"self_error\":" << p.self_error
           << ",\"scratch_used\":" << p.scratch_used
           << ",\"state_hash\":" << p.state_hash
           << ",\"output\":[";
        for (int k = 0; k < 32; ++k) {
            if (k) js << ',';
            js << static_cast<unsigned>(p.output[k]);
        }
        js << "]}";
        if (i + 1 < packets.size()) js << ',';
        js << "\n";
    }
    js << "]\n";

    const auto bytes = u->serialize();
    std::ofstream of(out, std::ios::binary);
    if (!of) { std::cerr << "cannot write " << out << "\n"; return 5; }
    of.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    std::cout << "headshift slot=" << slot << " epoch=" << epoch
              << " heads=" << packets.size() << " digest=" << hex(u->digest()) << "\n";
    return 0;
}

int cmd_bootstrap(int argc, char** argv) {
    const char* path = argc > 2 ? argv[2] : "data/alice_full.txt";
    int epochs = argc > 3 ? std::stoi(argv[3]) : 1;
    int chunks = argc > 4 ? std::stoi(argv[4]) : 8;
    if (epochs < 1) epochs = 1;
    if (chunks < 1) chunks = 1;
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::cerr << "cannot open " << path << "\n"; return 1; }
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    if (data.size() < 1000) { std::cerr << "corpus too small\n"; return 1; }
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());
    Context2Model model;
    const std::size_t chunk = (train.size() + static_cast<std::size_t>(chunks) - 1) /
                              static_cast<std::size_t>(chunks);
    std::cout << "bootstrap corpus=" << path << " train=" << train.size()
              << " test=" << test.size() << " epochs=" << epochs
              << " chunks=" << chunks << "\n";
    std::size_t seen = 0;
    for (int epoch = 1; epoch <= epochs; ++epoch) {
        for (std::size_t begin = 0; begin < train.size(); begin += chunk) {
            const std::size_t end = std::min(train.size(), begin + chunk);
            // Count each trigram exactly once per pass, in stream order.
            for (std::size_t i = std::max<std::size_t>(2, begin); i < end; ++i) {
                model.observe(train[i - 2], train[i - 1], train[i]);
            }
            seen += end - std::max<std::size_t>(2, begin);
            const Context2Eval eval = model.evaluate(test, 2, test.size());
            std::size_t word_start_total = 0;
            std::size_t word_start_correct = 0;
            std::size_t alpha_total = 0;
            std::size_t alpha_correct = 0;
            for (std::size_t i = 2; i < test.size(); ++i) {
                const std::uint8_t a = test[i - 2];
                const std::uint8_t b = test[i - 1];
                const std::uint8_t c = test[i];
                const bool predicted = model.predict(a, b) == c;
                if (std::isalpha(static_cast<unsigned char>(c))) {
                    ++alpha_total;
                    if (predicted) ++alpha_correct;
                    if (std::isspace(static_cast<unsigned char>(b))) {
                        ++word_start_total;
                        if (predicted) ++word_start_correct;
                    }
                }
            }
            const double ws = word_start_total
                ? static_cast<double>(word_start_correct) / word_start_total : 0.0;
            const double alpha = alpha_total
                ? static_cast<double>(alpha_correct) / alpha_total : 0.0;
            std::cout << "epoch=" << epoch << " chunk_end=" << end
                      << " bytes_seen=" << seen << " slabs=" << model.slabs()
                      << " bpc=" << eval.bits_per_byte
                      << " top1=" << eval.accuracy
                      << " alpha_top1=" << alpha
                      << " word_start_top1=" << ws << "\n";
        }
    }
    return 0;
}

int cmd_vectors() {
    BinStore store;
    const BinId keys = store.create(8, 2);
    const BinId values = store.create(8, 1);
    if (keys == kInvalidBin || values == kInvalidBin) return 1;
    store.write(keys, 0, {1, 2, 0, 0, 0, 0, 0, 0});
    store.write(keys, 1, {0, 0, 3, 4, 0, 0, 0, 0});
    store.write(values, 0, {7, 0, 0, 0, 0, 0, 0, 0});

    PointBinMap points;
    points.bind(16254, BinRef{keys, 0});

    AssocMemory memory(store);
    memory.bind({BinRef{keys, 0}}, {BinRef{values, 0}}, 65536, 0x50414952ull);
    memory.bind({BinRef{keys, 1}}, {BinRef{values, 0}}, 65536, 0x4B455932ull);

    std::cout << "point 16254 -> bin " << points.resolve(16254).bin
              << " slot " << points.resolve(16254).slot << "\n";
    const auto hits = memory.recall({1, 2, 0, 0, 0, 0, 0, 0}, 2);
    for (const auto& hit : hits) {
        std::cout << "recall id=" << hit.id << " score=" << hit.score
                  << " value_bin=" << hit.values.front().bin << "\n";
    }
    std::cout << "bins=" << store.size() << " bindings=" << points.bindings()
              << " associations=" << memory.size() << "\n";
    return hits.empty() ? 1 : 0;
}

int cmd_ctx2(int argc, char** argv) {
    const char* path = argc > 2 ? argv[2] : "data/alice_full.txt";
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::cerr << "cannot open " << path << "\n"; return 1; }
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());
    Context2Model model;
    model.train(train);
    const Context2Eval eval = model.evaluate(test, 2, test.size());
    std::cout << "context2 corpus=" << path << " bytes=" << data.size()
              << " slabs=" << model.slabs() << "\n";
    std::cout << "top1=" << eval.accuracy << " bpc=" << eval.bits_per_byte << "\n";
    return 0;
}

int cmd_kn(int argc, char** argv) {
    const char* path = argc > 2 ? argv[2] : "data/alice_full.txt";
    int order = argc > 3 ? std::stoi(argv[3]) : 2;
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::cerr << "cannot open " << path << "\n"; return 1; }
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    if (data.size() < 100) { std::cerr << "corpus too small\n"; return 1; }
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());
    KneserNey kn(order);
    kn.train(train);
    const SlotEval eval = kn.evaluate(test, static_cast<std::size_t>(order), test.size());
    std::cout << "Kneser-Ney order=" << order << " corpus=" << path
              << " bytes=" << data.size() << " test=" << test.size() << "\n";
    std::cout << "top1=" << eval.accuracy << " bpc=" << eval.bits_per_byte << "\n";
    return 0;
}

int cmd_byte(int argc, char** argv) {
    const char* path = argc > 2 ? argv[2] : "data/alice_excerpt.txt";
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::cerr << "cannot open " << path << "\n"; return 1; }
    std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(f)),
                                   std::istreambuf_iterator<char>());
    if (data.size() < 100) { std::cerr << "corpus too small\n"; return 1; }
    const std::size_t split = (data.size() * 4) / 5;
    std::vector<std::uint8_t> train(data.begin(), data.begin() + split);
    std::vector<std::uint8_t> test(data.begin() + split, data.end());
    Universe u(0x4E614E4C4D000001ull);
    ByteModel model(u);
    model.train(train);
    const ByteEval eval = model.evaluate(test, 1, test.size());
    const ByteEval ref = ByteModel::reference(train, test);
    const ByteEval order0 = ByteModel::order0_reference(train, test);
    std::cout << "NaNLMind — single-universe byte bigram\n\n";
    std::cout << "corpus " << path << " bytes=" << data.size()
              << " train=" << train.size() << " test=" << test.size() << "\n";
    std::cout << "topology  acc=" << eval.accuracy << " bpc=" << eval.bits_per_byte << "\n";
    std::cout << "reference acc=" << ref.accuracy << " bpc=" << ref.bits_per_byte << "\n";
    std::cout << "order0    acc=" << order0.accuracy << " bpc=" << order0.bits_per_byte << "\n";
    std::cout << "match=" << ((eval.correct == ref.correct &&
                               std::abs(eval.bits_per_byte - ref.bits_per_byte) < 1e-9) ? "yes" : "no")
              << " cells=" << u.canonical_count() << "\n";
    return (eval.correct == ref.correct) ? 0 : 2;
}

int cmd_ntf() {
    std::cout << "NaNLMind — NaN Translation Fabric\n\n";
    const auto a = UniverseAddress::parse("nan://U-07/R-03/H-0x0180/T-108/model/a");
    if (!a) { std::cerr << "address parse failed\n"; return 1; }
    MappingRecord m;
    m.universe = 7;
    m.mapping_version = 1;
    m.generation = 108;
    m.owner = NodeId::from_hex("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff");
    m.providers.push_back(m.owner);
    m.locators.push_back({"tcp", "node-a.example", 7401, "nan"});
    m.locators.push_back({"quic", "node-b.example", 7402, "nan"});
    m.expiry_unix = 2000000000;
    m.capabilities = kCapRead | kCapWrite | kCapExec;
    m.suite = CryptoSuite::Nsp8;
    m.signature[0] = 1;
    TranslationFabric fabric;
    std::string err;
    const bool published = fabric.publish(m, 1793860000, &err);
    const auto r = fabric.route(*a, 1793860000);
    std::cout << "address " << a->to_string() << "\n";
    std::cout << "published=" << published << " route_ok=" << r.ok
              << " locators=" << r.locators.size() << "\n";
    for (const auto& l : r.locators) std::cout << "  " << l.to_string() << "\n";
    std::cout << "mapping digest " << hex(m.digest()) << "\n";
    return (published && r.ok) ? 0 : 1;
}

int cmd_router() {
    GlobalTopology g(0x4E614E4C4D000001ull);
    RouterChart router(g, PageId::root());
    std::cout << "NaNLMind — meta-router chart\n\n";
    std::cout << "portals 256, routes 32640, portal address (src<<8)|rev8(dst)\n";
    const bool opened = router.open_universe(3, 0x99);
    const RouteResult w = router.route(3, 7, PortalOp::WriteForward, 0xDEADBEEFu, 0x5, 1);
    const RouteResult r = router.read(3, 7, true);
    std::cout << "open universe 3: " << (opened ? "yes" : "no") << "\n";
    std::cout << "write forward: ok=" << w.ok << " data=0x" << std::hex << w.word.data
              << " flags=0x" << static_cast<int>(w.word.flags) << std::dec << "\n";
    std::cout << "read  forward: ok=" << r.ok << " data=0x" << std::hex << r.word.data
              << " flags=0x" << static_cast<int>(r.word.flags) << std::dec << "\n";
    std::cout << "charts=" << g.chart_count() << " manifest=" << g.manifest().generation
              << " digest=" << hex(g.global_digest()) << "\n";
    return (opened && w.ok && r.ok) ? 0 : 1;
}

int cmd_phase() {
    std::cout << "NaNLM Universal — transform phase and wake scheduling\n\n";
    std::uint32_t c4 = 0, c2 = 0, c1 = 0;
    for (std::uint32_t i = 0; i < 65536; ++i) {
        const std::uint8_t s = transform_orbit_size(static_cast<std::uint16_t>(i));
        if (s == 4) ++c4;
        else if (s == 2) ++c2;
        else ++c1;
    }
    std::cout << "transform orbits (I, B, BR, R):\n";
    std::cout << "  size 4  " << c4 << "\n";
    std::cout << "  size 2  " << c2 << "\n";
    std::cout << "  size 1  " << c1 << "\n\n";
    std::cout << "wake-slot max gap (256 slots):\n";
    std::cout << "  alive  ideal  bit-reversed  linear  random\n";
    for (int k : {8, 16, 32, 5}) {
        const auto br = bit_reversed_wake_slots(k);
        const auto lin = linear_wake_slots(k);
        const auto rnd = random_wake_slots(k, 0x4E614E4C);
        std::cout << "  " << k << "      " << ideal_max_gap(k) << "     "
                  << max_wake_gap(br) << "           " << max_wake_gap(lin) << "     "
                  << max_wake_gap(rnd) << "\n";
    }
    std::cout << "\npalindromic 16-bit epoch markers: " << palindromic_epochs().size() << "\n";
    std::cout << "These are markers, not a regular wall clock.\n";
    return 0;
}

int cmd_clock() {
    TemporalClock c;
    std::cout << "NaNLM Universal — temporal clock (from nanclock.zip)\n\n";
    std::cout << "cells " << TemporalClock::kCells
              << "  past=0  future=" << (TemporalClock::kCells - 1) << "\n";
    std::cout << "+qNaN 0x" << std::hex << TemporalClock::kQnanPositive
              << "  -sNaN 0x" << TemporalClock::kSnanNegative << std::dec << "\n\n";
    for (int i = 0; i < 8; ++i) {
        c.step();
        std::cout << "tick " << (c.tick() - 1)
                  << ": future=" << clock_state_name(c.future())
                  << " -> " << clock_signal_name(c.signal())
                  << " -> past rewrites future=" << clock_state_name(c.past_rewrite())
                  << (c.contradiction() ? " [CONTRADICTION]" : " [CONSISTENT]") << "\n";
    }
    std::uint64_t start = 0, length = 0;
    if (c.cycle(start, length)) {
        std::cout << "\ncycle start=" << start << " length=" << length << "\n";
    }
    std::cout << "events " << c.event_count() << "  digest " << hex(c.digest()) << "\n";
    return 0;
}

int cmd_heads() {
    GlobalTopology g(0x4E614E4C4D000001ull);
    HeadArray heads = g.root_heads();
    std::string err;
    if (!heads.verify(&err)) {
        std::cerr << "head verification failed: " << err << "\n";
        return 1;
    }
    std::cout << "NaNLM Universal — 256-head palindromic layer\n\n";
    std::cout << "implementation 0x" << std::hex << HeadArray::kImplementationId << std::dec << "\n";
    std::cout << "count          " << HeadArray::size() << "\n";
    std::cout << "array digest   " << hex(heads.digest()) << "\n\n";
    for (int i = 0; i < 8; ++i) {
        HeadView h = heads.at(static_cast<std::uint8_t>(i));
        std::cout << "head " << i << " addr=0x" << std::hex << h.address().value << std::dec
                  << " phase=" << static_cast<int>(h.phase())
                  << " energy=" << h.record().energy
                  << " links=" << h.links().total() << "\n";
    }
    BidirectionalMemory temporal;
    HeadRunner runner(heads, PageId::root(), &temporal);
    HeadToken token;
    token.id = 1;
    token.payload = 0x21;
    token.epoch = 0;
    std::uint8_t at = 0;
    std::cout << "\nrunner chain:\n";
    for (int i = 0; i < 8; ++i) {
        const RunnerResult r = runner.run(at, token);
        if (!r.ok) {
            std::cout << "  stopped: " << r.error << "\n";
            break;
        }
        std::cout << "  " << static_cast<int>(at) << " -> " << static_cast<int>(r.next)
                  << " epoch=" << r.out.epoch << " phase=0x" << std::hex << r.out.phase
                  << std::dec << "\n";
        at = r.next;
        token = r.out;
    }
    std::cout << "\ntemporal links " << temporal.size()
              << ", history(0) " << heads.history(0).size() << "\n";
    return 0;
}

void usage() {
    std::cout << "nanlm-universal <command>\n\n"
              << "  verify      exhaustive invariants and self-tests\n"
              << "  genesis     materialize and describe the genesis register file\n"
              << "  global      one global topology with cross-space relations\n"
              << "  heads       256-head palindromic layer and runner handoff\n"
              << "  clock       temporal oscillator / global epoch heartbeat\n"
              << "  phase       transform-phase orbits and wake-slot scheduling\n"
              << "  router      meta-router: universes as heads, routes as pairs\n"
              << "  ntf         NaN Translation Fabric address/route demo\n"
              << "  byte [path] single-universe byte bigram train/eval\n"
              << "  kn [path] [order] Kneser-Ney byte baseline\n"
              << "  ctx2 [path] context-2 child-chart layout\n"
              << "  vectors      addressable vector bins and macro recall\n"
              << "  bootstrap [path] [epochs] streaming byte bootstrap\n"
              << "  snapshot    write state/chart.nmc\n"
              << "  headshift   real HeadView packets for one slot\n"
              << "  growth      child-chart growth and scratch consolidation\n"
              << "  scale       print the hierarchical scaling table\n"
              << "  resonance   run the 256-head resonance wave\n"
              << "  bits        demonstrate bit addressing and copy-on-write\n";
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        usage();
        return 0;
    }
    const std::string cmd = argv[1];
    if (cmd == "verify") return cmd_verify();
    if (cmd == "genesis") return cmd_genesis();
    if (cmd == "global") return cmd_global();
    if (cmd == "heads") return cmd_heads();
    if (cmd == "clock") return cmd_clock();
    if (cmd == "phase") return cmd_phase();
    if (cmd == "router") return cmd_router();
    if (cmd == "ntf") return cmd_ntf();
    if (cmd == "byte") return cmd_byte(argc, argv);
    if (cmd == "kn") return cmd_kn(argc, argv);
    if (cmd == "ctx2") return cmd_ctx2(argc, argv);
    if (cmd == "vectors") return cmd_vectors();
    if (cmd == "bootstrap") return cmd_bootstrap(argc, argv);
    if (cmd == "snapshot") return cmd_snapshot(argc, argv);
    if (cmd == "headshift") return cmd_headshift(argc, argv);
    if (cmd == "growth") return cmd_growth();
    if (cmd == "scale") return cmd_scale();
    if (cmd == "resonance") return cmd_resonance();
    if (cmd == "bits") return cmd_bits();
    usage();
    return 1;
}
