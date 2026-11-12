// One-step native head-state candidate-vector trainer adapter.
//
// All scores, softmax, cross-entropy and the SGD update run in the NaN16
// head worker (opcode124). This host program only reads/writes float files,
// transports the target/lr, and serializes the guest receipt.
#include "nanlm/raw_field.hpp"

#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
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
void write_floats(const std::string& path,
                  const std::vector<std::array<float, 128>>& values) {
    std::ofstream out(path, std::ios::trunc);
    if (!out) throw std::runtime_error("cannot write " + path);
    out << std::setprecision(9);
    for (const auto& row : values) {
        for (unsigned d = 0; d < 128u; ++d) {
            if (d) out << ' ';
            out << row[d];
        }
        out << '\n';
    }
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 7) {
        std::cerr << "Usage: nanlm-head-readout-train <state.f32> "
                     "<candidates.f32> <target> <lr> <out-candidates.f32> "
                     "<out.json>\n";
        return 2;
    }
    try {
        const auto state_values = read_floats(argv[1]);
        if (state_values.size() != 128u)
            throw std::runtime_error("state must contain exactly 128 floats");
        const auto candidate_values = read_floats(argv[2]);
        if (candidate_values.empty() || candidate_values.size() % 128u != 0u)
            throw std::runtime_error("candidates must contain N*128 floats");
        const std::size_t count = candidate_values.size() / 128u;
        if (count < 1u || count > 64u)
            throw std::runtime_error("candidate count must be 1..64");
        const unsigned target = static_cast<unsigned>(std::stoul(argv[3]));
        const float lr = std::stof(argv[4]);
        if (target >= count)
            throw std::runtime_error("target outside candidate range");

        std::array<float, 128> state{};
        for (unsigned d = 0; d < 128u; ++d) state[d] = state_values[d];
        std::vector<std::array<float, 128>> candidates(count);
        for (std::size_t i = 0; i < count; ++i)
            for (unsigned d = 0; d < 128u; ++d)
                candidates[i][d] = candidate_values[i * 128u + d];

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        std::vector<float> probabilities;
        std::vector<std::array<float, 128>> updated;
        float loss = 0.0f;
        std::uint8_t predicted = 0;
        std::uint8_t reason = 0;
        if (!vm.native_head_state_train(
                state, candidates, static_cast<std::uint8_t>(target), lr,
                probabilities, updated, loss, predicted, reason))
            throw std::runtime_error("native head train: " + vm.error());
        if (reason != 0u)
            throw std::runtime_error("native head train rejected reason=" +
                                     std::to_string(reason));

        write_floats(argv[5], updated);
        std::ofstream out(argv[6], std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write output JSON");
        out << "{\"schema\":\"nanlm.head-readout-train/1\","
               "\"target\":" << target << ",\"learning_rate\":" << lr
            << ",\"predicted\":" << unsigned(predicted)
            << ",\"loss\":" << loss << ",\"host_math\":false,"
               "\"candidate_count\":" << count << ",\"probabilities\":[";
        for (std::size_t i = 0; i < probabilities.size(); ++i) {
            if (i) out << ',';
            out << probabilities[i];
        }
        out << "]}\n";
        std::cout << "head_readout_train target=" << target
                  << " predicted=" << unsigned(predicted)
                  << " loss=" << loss << " candidates=" << count
                  << " output=" << argv[5] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_readout_train_error: " << e.what() << "\n";
        return 1;
    }
}
