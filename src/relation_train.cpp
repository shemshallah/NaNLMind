#include "nanlm/relation_train.hpp"

#include "nanlm/global.hpp"
#include "nanlm/sha256.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {
namespace {
struct Example {
    bool train = false;
    bool positive = true;
    std::uint8_t resolution = 0;
    std::uint32_t confidence = 0;
    std::string subject, predicate, object;
    Hash256 sh{}, ph{}, oh{}, event_hash{};
    std::uint64_t label = 0;
};

bool unhex(const std::string& in, std::string& out) {
    if (in.empty() || (in.size() & 1u)) return false;
    auto nibble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    out.clear();
    for (std::size_t i = 0; i < in.size(); i += 2u) {
        const int a = nibble(in[i]), b = nibble(in[i + 1u]);
        if (a < 0 || b < 0) return false;
        out.push_back(static_cast<char>((a << 4) | b));
    }
    return true;
}

bool parse_examples(const std::string& path, std::vector<Example>& examples) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { std::cerr << "cannot open relation records\n"; return false; }
    std::string header;
    if (!std::getline(in, header) || header != "N16REL/1") {
        std::cerr << "expected N16REL/1 header\n"; return false;
    }
    std::string line;
    std::size_t line_no = 1;
    while (std::getline(in, line)) {
        ++line_no;
        if (line.empty()) continue;
        std::array<std::string, 8> f{};
        std::size_t n = 0, start = 0;
        for (std::size_t i = 0; i <= line.size(); ++i) {
            if (i == line.size() || line[i] == '\t') {
                if (n == f.size()) { std::cerr << "too many fields at " << line_no << "\n"; return false; }
                f[n++] = line.substr(start, i - start);
                start = i + 1u;
            }
        }
        if (n != 8 || (f[0] != "train" && f[0] != "test") ||
            (f[2] != "+" && f[2] != "-")) {
            std::cerr << "invalid relation row at " << line_no << "\n"; return false;
        }
        Example e;
        try {
            const int r = std::stoi(f[1]);
            const unsigned long c = std::stoul(f[3]);
            if (r < 0 || r > 9 || c > 65535ul) throw std::out_of_range("field");
            e.resolution = static_cast<std::uint8_t>(r);
            e.confidence = static_cast<std::uint32_t>(c);
        } catch (...) { std::cerr << "invalid resolution/confidence at " << line_no << "\n"; return false; }
        e.train = f[0] == "train";
        e.positive = f[2] == "+";
        if (!unhex(f[4], e.subject) || !unhex(f[5], e.predicate) ||
            !unhex(f[6], e.object) || f[7].size() != 64u) {
            std::cerr << "invalid hex/source digest field at " << line_no << "\n"; return false;
        }
        for (char c : f[7]) {
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                  (c >= 'A' && c <= 'F'))) {
                std::cerr << "invalid source digest at " << line_no << "\n"; return false;
            }
        }
        e.sh = Sha256::hash(e.subject.data(), e.subject.size());
        e.ph = Sha256::hash(e.predicate.data(), e.predicate.size());
        e.oh = Sha256::hash(e.object.data(), e.object.size());
        e.event_hash = Sha256::hash(line.data(), line.size());
        for (unsigned i = 0; i < 8; ++i) e.label = (e.label << 8) | e.event_hash[i];
        if (!e.label) e.label = 1;
        examples.push_back(std::move(e));
    }
    return !examples.empty();
}

std::uint8_t predicate_head(std::uint8_t resolution, const Hash256& hash) {
    return static_cast<std::uint8_t>(resolution * 25u + hash[0] % 25u);
}

std::uint8_t distinct_head(std::uint8_t base, std::uint8_t candidate,
                           std::uint8_t first, std::uint8_t second) {
    for (unsigned i = 0; i < 25u && (candidate == first || candidate == second); ++i)
        candidate = static_cast<std::uint8_t>(base + ((candidate - base + 1u) % 25u));
    return candidate;
}

bool update_pair(GlobalTopology& topology, std::uint8_t a, std::uint8_t b,
                 const Example& e, std::uint64_t epoch, Ref& ref) {
    if (a == b) return false;
    const std::uint16_t address = canonical16(matrix_addr(a, b));
    NanCell* cell = topology.cell(PageId::root(), address);
    if (!cell || !cell->is_pair()) return false;
    const std::uint32_t fingerprint =
        (std::uint32_t(e.event_hash[0]) << 24) |
        (std::uint32_t(e.event_hash[1]) << 16) |
        (std::uint32_t(e.event_hash[2]) << 8) | e.event_hash[3];
    const std::uint32_t payload = cell->s_plus().payload() ^ fingerprint;
    cell->s_plus() = NanWord::make(NanType::SignalPositive, NanType::QuietPositive, payload);
    cell->s_minus() = NanWord::make(NanType::SignalNegative, NanType::QuietNegative, ~payload);
    const std::uint64_t weight = std::uint64_t(cell->q_plus().payload()) + e.confidence;
    cell->q_plus() = NanWord::make(NanType::QuietPositive, NanType::QuietPositive,
        static_cast<std::uint32_t>(std::min<std::uint64_t>(weight, 0xFFFFFFFFull)));
    cell->q_minus() = NanWord::make(NanType::QuietNegative, NanType::QuietNegative,
                                    static_cast<std::uint32_t>(epoch));
    cell->epoch = static_cast<std::uint32_t>(epoch);
    cell->meta[0] = e.resolution;
    cell->meta[1] = e.positive ? 1u : 0u;
    cell->meta[2] = a; cell->meta[3] = b;
    for (unsigned i = 0; i < 8; ++i) cell->meta[4u + i] = e.event_hash[i];
    const std::uint16_t count = static_cast<std::uint16_t>(cell->meta[16]) |
                                (static_cast<std::uint16_t>(cell->meta[17]) << 8);
    const std::uint16_t next = count == 0xFFFFu ? count : static_cast<std::uint16_t>(count + 1u);
    cell->meta[16] = static_cast<std::uint8_t>(next & 0xFFu);
    cell->meta[17] = static_cast<std::uint8_t>(next >> 8);
    ++cell->generation;
    cell->set_flag(kFlagDirty, true);
    ref = Ref::from_bit(BitAddress{PageId::root(), address, 0, 0});
    return true;
}
} // namespace

int relation_train_cli(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "usage: nanlm-universal relation-train RECORDS STATE\n"
                  << "N16REL/1 rows: split<TAB>resolution(0..9)<TAB>polarity(+|-)"
                  << "<TAB>confidence<TAB>subject_hex<TAB>predicate_hex<TAB>object_hex<TAB>source_sha256\n";
        return 2;
    }
    std::vector<Example> examples;
    if (!parse_examples(argv[2], examples)) return 2;
    int epochs = 1;
    if (argc > 4) {
        try { epochs = std::stoi(argv[4]); }
        catch (...) { std::cerr << "invalid relation epochs\\n"; return 2; }
        if (epochs < 1 || epochs > 100) { std::cerr << "relation epochs must be 1..100\\n"; return 2; }
    }
    const std::string state_path = argv[3];
    const auto parent = std::filesystem::path(state_path).parent_path();
    std::filesystem::create_directories(parent.empty() ? std::filesystem::path(".") : parent);
    std::unique_ptr<GlobalTopology> topology;
    if (std::filesystem::exists(state_path)) {
        std::ifstream prior(state_path, std::ios::binary);
        std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(prior)),
                                        std::istreambuf_iterator<char>());
        topology = GlobalTopology::from_bytes(bytes.data(), bytes.size());
        if (!topology) { std::cerr << "invalid relation state\n"; return 6; }
    } else topology = std::make_unique<GlobalTopology>(0x4E414E52454C0001ull);
    HeadArray heads = topology->root_heads();
    const Hash256 before = topology->global_digest();

    std::array<std::uint64_t,10> train_n{}, train_pos{}, test_n{}, test_ok{};
    std::array<std::uint64_t,10> test_pos{}, test_neg{}, tp{}, tn{}, baseline_ok{};
    std::array<std::uint64_t,10> pre_test_n{}, pre_test_ok{}, pre_test_pos{}, pre_test_neg{}, pre_tp{}, pre_tn{};
    std::array<Hash256,256> head_state_before{};
    std::array<bool,256> decayed{};
    auto head_state_hash = [](HeadView& h) {
        Sha256 digest;
        digest.update(&h.cell(), sizeof(NanCell));
        digest.update(&h.scratch(), sizeof(HeadScratch));
        return digest.final();
    };
    for (std::uint16_t i=0;i<256;++i) {
        HeadView h=heads.at(static_cast<std::uint8_t>(i));
        head_state_before[i]=head_state_hash(h);
    }
    std::uint64_t accepted=0, duplicates=0, pair_updates=0, edges_added=0;
    for (const auto& e : examples) if (e.train) {
        ++train_n[e.resolution];
        if (e.positive) ++train_pos[e.resolution];
    }
    // Measure the exact same held-out rows before mutation, then again after
    // training. This makes per-run movement observable instead of reporting
    // only a post-training scalar.
    for (const auto& e : examples) if (!e.train) {
        const HeadView h = heads.at(predicate_head(e.resolution, e.ph));
        unsigned votes = 0;
        for (unsigned lane=0; lane<8; ++lane)
            votes += (NanWord::eval_bool(h.boolean_rule(), e.sh[lane]&1u, e.oh[lane]&1u)&1u) ? 1u : 0u;
        const bool prediction = votes >= 4u;
        ++pre_test_n[e.resolution];
        if (e.positive) { ++pre_test_pos[e.resolution]; if (prediction) ++pre_tp[e.resolution]; }
        else { ++pre_test_neg[e.resolution]; if (!prediction) ++pre_tn[e.resolution]; }
        if (prediction == e.positive) ++pre_test_ok[e.resolution];
    }
    for (const auto& e : examples) {
        const std::uint8_t base = static_cast<std::uint8_t>(e.resolution * 25u);
        const std::uint8_t ph = predicate_head(e.resolution, e.ph);
        if (!e.train) {
            const HeadView h = heads.at(ph);
            unsigned votes = 0;
            for (unsigned lane=0; lane<8; ++lane)
                votes += (NanWord::eval_bool(h.boolean_rule(), e.sh[lane]&1u, e.oh[lane]&1u)&1u) ? 1u : 0u;
            const bool prediction = votes >= 4u;
            ++test_n[e.resolution];
            if (e.positive) ++test_pos[e.resolution]; else ++test_neg[e.resolution];
            if (prediction == e.positive) ++test_ok[e.resolution];
            if (e.positive && prediction) ++tp[e.resolution];
            if (!e.positive && !prediction) ++tn[e.resolution];
            if ((train_pos[e.resolution] * 2u >= train_n[e.resolution]) == e.positive)
                ++baseline_ok[e.resolution];
            continue;
        }
        bool duplicate = false;
        for (std::uint32_t id=1; id<topology->hypergraph().next_id(); ++id) {
            const Hyperedge* old = topology->hypergraph().get(id);
            if (old && old->label == e.label) { duplicate=true; break; }
        }
        if (duplicate) { ++duplicates; continue; }
        std::uint8_t sh = distinct_head(base, static_cast<std::uint8_t>(base + e.sh[1]%25u), ph, 255u);
        std::uint8_t oh = distinct_head(base, static_cast<std::uint8_t>(base + e.oh[2]%25u), ph, sh);
        if (sh==ph || oh==ph || oh==sh) { std::cerr << "relation head collision\n"; return 7; }
        HeadView p = heads.at(ph), s = heads.at(sh), o = heads.at(oh);
        if (!decayed[ph]) { p.decay_boolean_scores(1); decayed[ph] = true; }
        if (!decayed[sh]) { s.decay_boolean_scores(1); decayed[sh] = true; }
        if (!decayed[oh]) { o.decay_boolean_scores(1); decayed[oh] = true; }
        for (int epoch=0; epoch<epochs; ++epoch) {
            for (unsigned lane=0; lane<8; ++lane) {
                p.train_boolean(e.sh[lane]&1u, e.oh[lane]&1u, e.positive);
                s.train_boolean(e.ph[lane]&1u, e.oh[lane]&1u, e.positive);
                o.train_boolean(e.sh[lane]&1u, e.ph[lane]&1u, e.positive);
            }
        }
        const std::uint64_t epoch=topology->ledger().size()+1u;
        BitAddress sb{PageId::root(),heads.at(sh).address().value,0,0};
        BitAddress pb{PageId::root(),heads.at(ph).address().value,0,0};
        BitAddress ob{PageId::root(),heads.at(oh).address().value,0,0};
        Ref sp{},po{},so{};
        if (!update_pair(*topology,sh,ph,e,epoch,sp) ||
            !update_pair(*topology,ph,oh,e,epoch,po) ||
            !update_pair(*topology,sh,oh,e,epoch,so)) {
            std::cerr << "mirror-pair update failed\n"; return 7;
        }
        pair_updates += 3;
        Hyperedge edge;
        edge.flags=kHyperLearned|kHyperTemporal|kHyperMirror;
        edge.weight=std::max<std::uint32_t>(1u,e.confidence);
        edge.epoch=epoch; edge.label=e.label;
        edge.members={Ref::from_bit(sb),Ref::from_bit(pb),Ref::from_bit(ob),sp,po,so};
        if (!topology->hypergraph().add(edge)) { std::cerr << "hyperedge append failed\n"; return 7; }
        topology->temporal().link(Ref::from_bit(sb),sp,epoch);
        topology->temporal().link(Ref::from_bit(pb),po,epoch);
        topology->temporal().link(Ref::from_bit(ob),so,epoch);
        ++accepted; ++edges_added;
    }
    auto emit_resolution_metrics = [&]() {
        for (std::size_t r=0;r<10;++r) if (train_n[r] || test_n[r]) {
            const double acc=test_n[r]?double(test_ok[r])/test_n[r]:0.0;
            const double before_acc=pre_test_n[r]?double(pre_test_ok[r])/pre_test_n[r]:0.0;
            const double baseacc=test_n[r]?double(baseline_ok[r])/test_n[r]:0.0;
            const double sens=test_pos[r]?double(tp[r])/test_pos[r]:0.0;
            const double spec=test_neg[r]?double(tn[r])/test_neg[r]:0.0;
            const double before_sens=pre_test_pos[r]?double(pre_tp[r])/pre_test_pos[r]:0.0;
            const double before_spec=pre_test_neg[r]?double(pre_tn[r])/pre_test_neg[r]:0.0;
            std::cout << "resolution_L" << r << " train=" << train_n[r] << " test=" << test_n[r]
                      << " before_accuracy=" << before_acc << " accuracy=" << acc
                      << " delta=" << (acc-before_acc)
                      << " before_balanced_accuracy=" << (before_sens+before_spec)/2.0
                      << " balanced_accuracy=" << (sens+spec)/2.0
                      << " majority_baseline=" << baseacc << "\n";
        }
    };
    if (!accepted) {
        if (duplicates) {
            const std::uintmax_t existing_bytes = std::filesystem::exists(state_path)
                ? std::filesystem::file_size(state_path) : 0u;
            const Hash256 current = topology->global_digest();
            std::cout << "relation_train status=no_op epochs=" << epochs
                      << " train_events=0 duplicate_events=" << duplicates
                      << " changed_heads=0 mirror_pair_updates=0 hyperedges_added=0"
                      << " state_bytes=" << existing_bytes
                      << " state_digest_before=" << hex(current)
                      << " state_digest_after=" << hex(current) << "\n";
            emit_resolution_metrics();
            return 0;
        }
        std::cerr << "no new relation events; duplicates=0\n";
        return 8;
    }
    topology->commit(0x48u,0x41u,0,before,topology->global_digest(),
                     static_cast<std::uint64_t>(topology->ledger().size()+1u));
    const auto bytes=topology->serialize();
    const std::string tmp=state_path+".tmp";
    {
        std::ofstream out(tmp,std::ios::binary|std::ios::trunc);
        if (!out) { std::cerr << "cannot write relation state\n"; return 5; }
        out.write(reinterpret_cast<const char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));
        out.flush(); if (!out) { std::cerr << "relation state write failed\n"; return 5; }
    }
    std::error_code ec; std::filesystem::rename(tmp,state_path,ec);
    if (ec) { std::cerr << "relation state publish failed: " << ec.message() << "\n"; std::filesystem::remove(tmp); return 5; }
    std::uint64_t changed=0;
    for (std::uint16_t i=0;i<256;++i) {
        HeadView h=heads.at(static_cast<std::uint8_t>(i));
        if (!(head_state_before[i] == head_state_hash(h))) ++changed;
    }
    std::cout << "relation_train status=updated epochs=" << epochs << " train_events=" << accepted
              << " duplicate_events=" << duplicates << " changed_heads=" << changed
              << " mirror_pair_updates=" << pair_updates << " hyperedges_added=" << edges_added
              << " state_bytes=" << bytes.size() << " state_digest_before=" << hex(before)
              << " state_digest_after=" << hex(topology->global_digest()) << "\n";
    emit_resolution_metrics();
    return 0;
}

} // namespace nanlm
