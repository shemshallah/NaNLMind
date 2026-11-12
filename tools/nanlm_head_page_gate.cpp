// Page-checkpoint validation and held-out NLL gate.
//
// Both checkpoints are verified page-by-page, then selected pages are loaded
// through the 16-slot page loader and executed by the native six-token worker.
// The last-token states are scored by the native head-state readout with lr=0
// (opcode124); the host only aggregates the reported held-out losses and
// applies the gate. No page or tensor values are mutated.
#include "nanlm/head_page_checkpoint.hpp"
#include "nanlm/head_page_loader.hpp"
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
    float value = 0;
    while (in >> value) out.push_back(value);
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
struct CheckpointResult {
    double nll = 0.0;
    std::string state_sha256;
    std::size_t heads = 0;
};
CheckpointResult evaluate_checkpoint(
    RawFieldVM& vm, HeadPageArena& arena, const std::filesystem::path& dir,
    const std::array<float, 6 * 128>& context, std::uint8_t token_count,
    const std::vector<unsigned>& heads,
    const std::vector<std::array<float, 128>>& candidates,
    std::uint8_t target) {
    HeadPageCheckpoint store(dir);
    std::string error;
    if (!store.verify_all(&error))
        throw std::runtime_error("checkpoint invalid: " + error);
    HeadPageLoader loader(vm, arena);
    Sha256 digest;
    double nll_sum = 0.0;
    for (unsigned head : heads) {
        if (!store.present(head))
            throw std::runtime_error("checkpoint missing head " + std::to_string(head));
        if (!store.read_page(head, arena))
            throw std::runtime_error("cannot load checkpoint page " + std::to_string(head));
        const std::size_t slot = loader.load(head);
        std::array<float, 6 * 128> output{};
        std::uint8_t reason = 0;
        if (!vm.native_head_block6(context, token_count,
                                   static_cast<std::uint8_t>(slot), output, reason))
            throw std::runtime_error("worker: " + vm.error());
        if (reason != 0u)
            throw std::runtime_error("worker rejected page " + std::to_string(head) +
                                     " reason=" + std::to_string(reason));
        const std::size_t base =
            (static_cast<std::size_t>(token_count) - 1u) * 128u;
        std::array<float, 128> state{};
        for (unsigned d = 0; d < 128u; ++d) state[d] = output[base + d];
        std::array<std::uint8_t, 1> head_byte = {
            static_cast<std::uint8_t>(head)};
        digest.update(head_byte.data(), head_byte.size());
        for (float value : state) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &value, sizeof(bits));
            for (unsigned shift : {0u, 8u, 16u, 24u})
                digest.update(reinterpret_cast<const std::uint8_t*>(
                                  &bits) + shift, 1);
        }
        std::vector<float> probabilities;
        std::vector<std::array<float, 128>> updated;
        float loss = 0.0f;
        std::uint8_t predicted = 0;
        if (!vm.native_head_state_train(state, candidates, target, 0.0f,
                                        probabilities, updated, loss,
                                        predicted, reason))
            throw std::runtime_error("readout: " + vm.error());
        if (reason != 0u)
            throw std::runtime_error("readout rejected target=" +
                                     std::to_string(target) +
                                     " reason=" + std::to_string(reason));
        nll_sum += loss;
    }
    CheckpointResult result{};
    result.heads = heads.size();
    result.nll = nll_sum / static_cast<double>(heads.size());
    result.state_sha256 = hex(digest.final());
    return result;
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 8) {
        std::cerr << "Usage: nanlm-head-page-gate <baseline-dir> "
                     "<candidate-dir> <context.f32> <heads> <candidates.f32> "
                     "<target> <out.json>\n";
        return 2;
    }
    try {
        const auto heads = parse_heads(argv[4]);
        const auto context_values = read_floats(argv[3]);
        if (context_values.empty() || context_values.size() % 128u != 0u)
            throw std::runtime_error("context must contain T*128 floats");
        const std::size_t token_count = context_values.size() / 128u;
        if (token_count < 1u || token_count > 6u)
            throw std::runtime_error("token count must be 1..6");
        std::array<float, 6 * 128> context{};
        for (std::size_t i = 0; i < context_values.size(); ++i)
            context[i] = context_values[i];

        const auto candidate_values = read_floats(argv[5]);
        if (candidate_values.empty() || candidate_values.size() % 128u != 0u)
            throw std::runtime_error("candidates must contain N*128 floats");
        const std::size_t candidate_count = candidate_values.size() / 128u;
        if (candidate_count < 1u || candidate_count > 64u)
            throw std::runtime_error("candidate count must be 1..64");
        std::vector<std::array<float, 128>> candidates(candidate_count);
        for (std::size_t i = 0; i < candidate_count; ++i)
            for (unsigned d = 0; d < 128u; ++d)
                candidates[i][d] = candidate_values[i * 128u + d];
        const unsigned target_value = static_cast<unsigned>(std::stoul(argv[6]));
        if (target_value >= candidate_count)
            throw std::runtime_error("target outside candidate range");
        const auto target = static_cast<std::uint8_t>(target_value);

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        HeadPageArena arena;
        const auto baseline = evaluate_checkpoint(
            vm, arena, argv[1], context,
            static_cast<std::uint8_t>(token_count), heads, candidates, target);
        const auto candidate = evaluate_checkpoint(
            vm, arena, argv[2], context,
            static_cast<std::uint8_t>(token_count), heads, candidates, target);
        HeadPageCheckpoint baseline_store(argv[1]);
        HeadPageCheckpoint candidate_store(argv[2]);
        const bool accepted = std::isfinite(baseline.nll) &&
            std::isfinite(candidate.nll) && candidate.nll < baseline.nll;

        std::ofstream out(argv[7], std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write output");
        out << "{\"schema\":\"nanlm.head-page-gate/1\","
               "\"head_count\":" << heads.size()
            << ",\"token_count\":" << token_count
            << ",\"baseline_nll\":" << baseline.nll
            << ",\"candidate_nll\":" << candidate.nll
            << ",\"nll_delta\":" << (baseline.nll - candidate.nll)
            << ",\"accepted\":" << (accepted ? "true" : "false")
            << ",\"baseline_state_sha256\":\""
            << baseline.state_sha256 << "\""
            << ",\"candidate_state_sha256\":\""
            << candidate.state_sha256 << "\""
            << ",\"baseline_root\":\"" << baseline_store.root_digest() << "\""
            << ",\"candidate_root\":\"" << candidate_store.root_digest() << "\""
            << ",\"host_math\":false,"
               "\"tensor_promotion\":false,"
               "\"page_training\":false,"
               "\"scope\":\"page checkpoint validation and held-out readout NLL gate only\"}\n";
        std::cout << "head_page_gate heads=" << heads.size()
                  << " baseline=" << baseline.nll
                  << " candidate=" << candidate.nll
                  << " accepted=" << (accepted ? "true" : "false")
                  << " output=" << argv[7] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_page_gate_error: " << e.what() << "\n";
        return 1;
    }
}
