// One-page native training adapter: final-W2 local update.
//
// The guest runs the six-token forward pass and the local error-corrective W2
// update (opcode125). The host only loads/transports the checkpoint page,
// context and target, then writes the modified 1 MiB page to a candidate
// checkpoint. This is not full three-layer backpropagation.
#include "nanlm/head_page_checkpoint.hpp"
#include "nanlm/head_page_loader.hpp"
#include "nanlm/raw_field.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
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
} // namespace

int main(int argc, char** argv) {
    if (argc != 9 && argc != 10) {
        std::cerr << "Usage: nanlm-head-page-train <checkpoint-dir> "
                     "<context.f32> <target.f32> <head> <lr> <epochs> "
                     "<out-dir> <out.json> [w2|wo|w1|wv|qk]\n";
        return 2;
    }
    try {
        const unsigned head = static_cast<unsigned>(std::stoul(argv[4]));
        if (head >= 255u) throw std::runtime_error("head 255 is VOID");
        const float lr = std::stof(argv[5]);
        const int epochs = std::stoi(argv[6]);
        const std::string mode = argc == 10 ? argv[9] : "w2";
        if (mode != "w2" && mode != "wo" && mode != "w1" &&
            mode != "wv" && mode != "qk")
            throw std::runtime_error("projection mode must be w2, wo, w1, wv, or qk");
        const bool update_wo = mode == "wo";
        const bool update_w1 = mode == "w1";
        const bool update_wv = mode == "wv";
        const bool update_qk = mode == "qk";
        if (!std::isfinite(lr) || lr < 0.0f)
            throw std::runtime_error("learning rate must be finite and nonnegative");
        if (epochs < 1 || epochs > 10000)
            throw std::runtime_error("epochs must be 1..10000");

        const auto context_values = read_floats(argv[2]);
        if (context_values.empty() || context_values.size() % 128u != 0u)
            throw std::runtime_error("context must contain T*128 floats");
        const std::size_t token_count = context_values.size() / 128u;
        if (token_count < 1u || token_count > 6u)
            throw std::runtime_error("token count must be 1..6");
        std::array<float, 6 * 128> context{};
        for (std::size_t i = 0; i < context_values.size(); ++i)
            context[i] = context_values[i];
        const auto target_values = read_floats(argv[3]);
        if (target_values.size() != 128u)
            throw std::runtime_error("target must contain exactly 128 floats");
        std::array<float, 128> target{};
        for (unsigned d = 0; d < 128u; ++d) target[d] = target_values[d];

        HeadPageCheckpoint source(argv[1]);
        std::string error;
        if (!source.verify_all(&error))
            throw std::runtime_error("source checkpoint invalid: " + error);
        if (!source.present(head))
            throw std::runtime_error("source checkpoint missing head " +
                                     std::to_string(head));
        const auto generation = source.record(head).generation;
        const auto source_sha = source.record(head).sha256;

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        HeadPageArena arena;
        HeadPageLoader loader(vm, arena);
        if (!source.read_page(head, arena))
            throw std::runtime_error("cannot load source page");
        const std::size_t slot = loader.load(head);

        float error_norm = 0.0f;
        std::array<float, 6 * 128> output{};
        std::uint8_t reason = 0;
        for (int epoch = 0; epoch < epochs; ++epoch) {
            const bool ok = update_w1
                ? vm.native_head_page_train_w1(
                      context, static_cast<std::uint8_t>(token_count),
                      static_cast<std::uint8_t>(slot), target, lr, output,
                      error_norm, reason)
                : update_wv
                    ? vm.native_head_page_train_wv(
                          context, static_cast<std::uint8_t>(token_count),
                          static_cast<std::uint8_t>(slot), target, lr, output,
                          error_norm, reason)
                : update_qk
                    ? vm.native_head_page_train_qk(
                          context, static_cast<std::uint8_t>(token_count),
                          static_cast<std::uint8_t>(slot), target, lr, output,
                          error_norm, reason)
                    : vm.native_head_page_train(
                          context, static_cast<std::uint8_t>(token_count),
                          static_cast<std::uint8_t>(slot), target, lr, output,
                          error_norm, reason, update_wo);
            if (!ok)
                throw std::runtime_error("page train: " + vm.error());
            if (reason != 0u)
                throw std::runtime_error("page train rejected reason=" +
                                         std::to_string(reason));
        }
        const auto updated = loader.export_page(slot);
        HeadPageCheckpoint out(argv[7]);
        out.write_page(head, updated.data(), updated.size(), generation + 1u);

        std::ofstream receipt(argv[8], std::ios::trunc);
        if (!receipt) throw std::runtime_error("cannot write output JSON");
        receipt << "{\"schema\":\"nanlm.head-page-train/1\","
                   "\"head\":" << head
                << ",\"epochs\":" << epochs
                << ",\"learning_rate\":" << lr
                << ",\"error_norm\":" << error_norm
                << ",\"source_generation\":" << generation
                << ",\"candidate_generation\":" << (generation + 1u)
                << ",\"source_page_sha256\":\"" << source_sha << "\""
                << ",\"candidate_page_sha256\":\""
                << out.record(head).sha256 << "\""
                << ",\"host_math\":false,"
                   "\"local_scope\":\""
                << (update_w1 ? "final_layer_W1_only"
                              : update_wv ? "final_layer_Wv_only"
                              : update_qk ? "final_layer_Wq_Wk_only"
                              : update_wo ? "final_layer_Wo_only"
                                          : "final_layer_W2_only")
                << "\","
                   "\"tensor_promotion\":false,"
                   "\"page_training\":true}\n";
        std::cout << "head_page_train head=" << head
                  << " epochs=" << epochs
                  << " error_norm=" << error_norm
                  << " candidate_generation=" << (generation + 1u)
                  << " output=" << argv[7] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_page_train_error: " << e.what() << "\n";
        return 1;
    }
}
