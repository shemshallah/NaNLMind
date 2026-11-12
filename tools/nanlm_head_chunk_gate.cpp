// Native 64-slot long-chunk checkpoint gate.
//
// Loads baseline/candidate page checkpoints, processes a token-vector chunk
// through the native 64-slot recurrent worker, and scores the final per-head
// memory with the native readout. The host only transports and aggregates
// reported guest losses.
#include "nanlm/head_page_checkpoint.hpp"
#include "nanlm/long_context64_scheduler.hpp"
#include "nanlm/raw_field.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::vector<float> read_floats(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    std::vector<float> out;
    float v = 0;
    while (in >> v) out.push_back(v);
    if (!in.eof()) throw std::runtime_error("not a float list: " + path);
    return out;
}
std::vector<unsigned> parse_heads(const std::string& text) {
    std::vector<unsigned> heads;
    std::stringstream ss(text);
    std::string item;
    while (std::getline(ss, item, ',')) {
        if (item.empty()) throw std::runtime_error("empty head");
        const unsigned h = static_cast<unsigned>(std::stoul(item));
        if (h >= 255u) throw std::runtime_error("head 255 is VOID");
        for (unsigned old : heads)
            if (old == h) throw std::runtime_error("duplicate head");
        heads.push_back(h);
    }
    if (heads.empty() || heads.size() > 16u)
        throw std::runtime_error("heads must contain 1..16 active heads");
    return heads;
}
struct Result {
    double nll = 0.0;
    std::size_t chunks = 0;
    std::string state_sha256;
};
Result evaluate(RawFieldVM& vm, const std::filesystem::path& dir,
                const std::vector<std::array<float, 128>>& tokens,
                const std::vector<unsigned>& heads,
                const std::vector<std::array<float, 128>>& candidates,
                std::uint8_t target) {
    HeadPageCheckpoint store(dir);
    std::string error;
    if (!store.verify_all(&error))
        throw std::runtime_error("checkpoint invalid: " + error);
    HeadPageArena arena;
    for (unsigned head : heads) {
        if (!store.present(head))
            throw std::runtime_error("checkpoint missing head " + std::to_string(head));
        if (!store.read_page(head, arena))
            throw std::runtime_error("cannot load page " + std::to_string(head));
    }
    LongContext64Scheduler scheduler(vm, arena, 63, true);
    std::array<float, 255> credits{};
    for (std::size_t i = 0; i < heads.size(); ++i)
        credits[heads[i]] = static_cast<float>(heads.size() - i);
    const auto run = scheduler.run(credits, tokens, heads.size());
    if (!run.accepted)
        throw std::runtime_error("chunk scheduler rejected reason=" +
                                 std::to_string(run.reason));
    if (run.heads.size() != heads.size() || run.final_states.size() != heads.size())
        throw std::runtime_error("chunk scheduler result shape mismatch");
    Sha256 digest;
    double nll_sum = 0.0;
    for (std::size_t i = 0; i < run.heads.size(); ++i) {
        std::vector<float> probabilities;
        std::vector<std::array<float, 128>> updated;
        float loss = 0.0f;
        std::uint8_t predicted = 0, reason = 0;
        if (!vm.native_head_state_train(
                run.final_states[i], candidates, target, 0.0f,
                probabilities, updated, loss, predicted, reason))
            throw std::runtime_error("chunk readout: " + vm.error());
        if (reason != 0u)
            throw std::runtime_error("chunk readout rejected");
        nll_sum += loss;
        const std::uint8_t hb = static_cast<std::uint8_t>(run.heads[i]);
        digest.update(&hb, 1);
        for (float value : run.final_states[i]) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &value, sizeof(bits));
            for (unsigned shift : {0u, 8u, 16u, 24u})
                digest.update(reinterpret_cast<const std::uint8_t*>(&bits) + shift, 1);
        }
    }
    return {nll_sum / static_cast<double>(run.heads.size()),
            run.chunks, hex(digest.final())};
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 8) {
        std::cerr << "Usage: nanlm-head-chunk-gate <baseline-dir> "
                     "<candidate-dir> <tokens.f32> <heads> <candidates.f32> "
                     "<target> <out.json>\n";
        return 2;
    }
    try {
        const auto heads = parse_heads(argv[4]);
        const auto token_values = read_floats(argv[3]);
        if (token_values.empty() || token_values.size() % 128u != 0u)
            throw std::runtime_error("tokens must contain N*128 floats");
        std::vector<std::array<float, 128>> tokens(token_values.size() / 128u);
        for (std::size_t i = 0; i < tokens.size(); ++i)
            for (unsigned d = 0; d < 128u; ++d)
                tokens[i][d] = token_values[i * 128u + d];
        const auto cand_values = read_floats(argv[5]);
        if (cand_values.empty() || cand_values.size() % 128u != 0u)
            throw std::runtime_error("candidates must contain N*128 floats");
        const std::size_t count = cand_values.size() / 128u;
        if (count < 1u || count > 64u)
            throw std::runtime_error("candidate count must be 1..64");
        std::vector<std::array<float, 128>> candidates(count);
        for (std::size_t i = 0; i < count; ++i)
            for (unsigned d = 0; d < 128u; ++d)
                candidates[i][d] = cand_values[i * 128u + d];
        const unsigned target_value = static_cast<unsigned>(std::stoul(argv[6]));
        if (target_value >= count) throw std::runtime_error("target outside candidates");

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        const auto baseline = evaluate(vm, argv[1], tokens, heads, candidates,
                                       static_cast<std::uint8_t>(target_value));
        const auto candidate = evaluate(vm, argv[2], tokens, heads, candidates,
                                        static_cast<std::uint8_t>(target_value));
        HeadPageCheckpoint bstore(argv[1]), cstore(argv[2]);
        const bool accepted = std::isfinite(baseline.nll) &&
            std::isfinite(candidate.nll) && candidate.nll < baseline.nll;
        std::ofstream out(argv[7], std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write output");
        out << "{\"schema\":\"nanlm.head-chunk-gate/1\","
               "\"heads\":" << heads.size()
            << ",\"tokens\":" << tokens.size()
            << ",\"baseline_nll\":" << baseline.nll
            << ",\"candidate_nll\":" << candidate.nll
            << ",\"nll_delta\":" << (baseline.nll - candidate.nll)
            << ",\"accepted\":" << (accepted ? "true" : "false")
            << ",\"baseline_chunks\":" << baseline.chunks
            << ",\"candidate_chunks\":" << candidate.chunks
            << ",\"baseline_state_sha256\":\"" << baseline.state_sha256 << "\""
            << ",\"candidate_state_sha256\":\"" << candidate.state_sha256 << "\""
            << ",\"baseline_root\":\"" << bstore.root_digest() << "\""
            << ",\"candidate_root\":\"" << cstore.root_digest() << "\""
            << ",\"host_math\":false,\"tensor_promotion\":false,"
               "\"scope\":\"64-slot long-chunk checkpoint gate; readout-panel NLL only\"}\n";
        std::cout << "head_chunk_gate heads=" << heads.size()
                  << " tokens=" << tokens.size()
                  << " baseline=" << baseline.nll
                  << " candidate=" << candidate.nll
                  << " accepted=" << (accepted ? "true" : "false") << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_chunk_gate_error: " << e.what() << "\n";
        return 1;
    }
}
