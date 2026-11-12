// Native head-readout training/checkpoint loop.
//
// Each example is 128D state + target index.  The guest performs every score,
// softmax, cross-entropy and SGD update (opcode124).  The host transports
// floats, runs the loop, aggregates held-out NLL, hashes the candidate bytes,
// and writes a gate receipt.  It does not claim tensor promotion.
#include "nanlm/raw_field.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <utility>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
struct Sample {
    std::array<float, 128> state{};
    std::uint8_t target = 0;
};

std::vector<float> read_floats(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    std::vector<float> out;
    float value = 0;
    while (in >> value) out.push_back(value);
    if (!in.eof()) throw std::runtime_error("not a float list: " + path);
    return out;
}

std::vector<std::array<float, 128>> read_candidates(
    const std::string& path, std::size_t& count) {
    const auto values = read_floats(path);
    if (values.empty() || values.size() % 128u != 0u)
        throw std::runtime_error("candidates must contain N*128 floats");
    count = values.size() / 128u;
    if (count < 1u || count > 64u)
        throw std::runtime_error("candidate count must be 1..64");
    std::vector<std::array<float, 128>> out(count);
    for (std::size_t i = 0; i < count; ++i)
        for (unsigned d = 0; d < 128u; ++d)
            out[i][d] = values[i * 128u + d];
    return out;
}

std::vector<Sample> read_dataset(const std::string& path, std::size_t count) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    std::vector<Sample> out;
    std::string line;
    std::size_t line_no = 0;
    while (std::getline(in, line)) {
        ++line_no;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        std::istringstream ss(line);
        std::vector<float> values;
        float v = 0;
        while (ss >> v) values.push_back(v);
        if (values.size() != 129u)
            throw std::runtime_error("dataset line must be 128 state floats + target: " +
                                     path + ":" + std::to_string(line_no));
        Sample sample{};
        for (unsigned d = 0; d < 128u; ++d) {
            if (!std::isfinite(values[d]))
                throw std::runtime_error("nonfinite state in " + path);
            sample.state[d] = values[d];
        }
        const float target = values[128];
        if (!std::isfinite(target) || target < 0.0f ||
            target >= static_cast<float>(count) ||
            std::floor(target) != target)
            throw std::runtime_error("invalid target in " + path + ":" +
                                     std::to_string(line_no));
        sample.target = static_cast<std::uint8_t>(target);
        out.push_back(sample);
    }
    if (out.empty()) throw std::runtime_error("dataset is empty: " + path);
    return out;
}

std::string digest_candidates(
    const std::vector<std::array<float, 128>>& candidates) {
    std::vector<std::uint8_t> bytes;
    bytes.reserve(candidates.size() * 128u * sizeof(float));
    for (const auto& row : candidates) {
        for (float value : row) {
            std::uint32_t bits = 0;
            std::memcpy(&bits, &value, sizeof(bits));
            for (unsigned shift : {0u, 8u, 16u, 24u})
                bytes.push_back(static_cast<std::uint8_t>(bits >> shift));
        }
    }
    return hex(Sha256::hash(bytes.data(), bytes.size()));
}

void write_candidates(const std::string& path,
                      const std::vector<std::array<float, 128>>& candidates) {
    std::ofstream out(path, std::ios::trunc);
    if (!out) throw std::runtime_error("cannot write " + path);
    out << std::setprecision(9);
    for (const auto& row : candidates) {
        for (unsigned d = 0; d < 128u; ++d) {
            if (d) out << ' ';
            out << row[d];
        }
        out << '\n';
    }
}

double evaluate(RawFieldVM& vm,
                const std::vector<std::array<float, 128>>& candidates,
                const std::vector<Sample>& samples) {
    double sum = 0.0;
    for (const auto& sample : samples) {
        std::vector<float> probabilities;
        std::vector<std::array<float, 128>> updated;
        float loss = 0.0f;
        std::uint8_t predicted = 0;
        std::uint8_t reason = 0;
        if (!vm.native_head_state_train(
                sample.state, candidates, sample.target, 0.0f,
                probabilities, updated, loss, predicted, reason))
            throw std::runtime_error("held-out guest evaluation failed: " +
                                     vm.error());
        if (reason != 0u)
            throw std::runtime_error("held-out guest rejection reason=" +
                                     std::to_string(reason));
        sum += loss;
    }
    return sum / static_cast<double>(samples.size());
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 8) {
        std::cerr << "Usage: nanlm-head-readout-loop <candidates.f32> "
                     "<train.dat> <heldout.dat> <epochs> <lr> "
                     "<out-candidates.f32> <out.json>\n";
        return 2;
    }
    try {
        std::size_t candidate_count = 0;
        auto candidates = read_candidates(argv[1], candidate_count);
        const auto train = read_dataset(argv[2], candidate_count);
        const auto heldout = read_dataset(argv[3], candidate_count);
        const int epochs = std::stoi(argv[4]);
        const float lr = std::stof(argv[5]);
        if (epochs < 1 || epochs > 100000)
            throw std::runtime_error("epochs must be 1..100000");
        if (!std::isfinite(lr) || lr < 0.0f)
            throw std::runtime_error("learning rate must be finite and nonnegative");

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        const std::string initial_sha = digest_candidates(candidates);
        const double baseline_nll = evaluate(vm, candidates, heldout);

        for (int epoch = 0; epoch < epochs; ++epoch) {
            for (const auto& sample : train) {
                std::vector<float> probabilities;
                std::vector<std::array<float, 128>> updated;
                float loss = 0.0f;
                std::uint8_t predicted = 0;
                std::uint8_t reason = 0;
                if (!vm.native_head_state_train(
                        sample.state, candidates, sample.target, lr,
                        probabilities, updated, loss, predicted, reason))
                    throw std::runtime_error("training step failed: " + vm.error());
                if (reason != 0u)
                    throw std::runtime_error("training rejection reason=" +
                                             std::to_string(reason));
                candidates = std::move(updated);
            }
        }

        const double candidate_nll = evaluate(vm, candidates, heldout);
        const std::string final_sha = digest_candidates(candidates);
        const bool accepted = std::isfinite(baseline_nll) &&
            std::isfinite(candidate_nll) && candidate_nll < baseline_nll;
        write_candidates(argv[6], candidates);

        std::ofstream out(argv[7], std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write output JSON");
        out << "{\"schema\":\"nanlm.head-readout-loop/1\","
               "\"candidate_count\":" << candidate_count
            << ",\"train_samples\":" << train.size()
            << ",\"heldout_samples\":" << heldout.size()
            << ",\"epochs\":" << epochs
            << ",\"learning_rate\":" << lr
            << ",\"baseline_heldout_nll\":" << baseline_nll
            << ",\"candidate_heldout_nll\":" << candidate_nll
            << ",\"nll_delta\":" << (baseline_nll - candidate_nll)
            << ",\"accepted\":" << (accepted ? "true" : "false")
            << ",\"initial_candidate_sha256\":\"" << initial_sha << "\""
            << ",\"candidate_sha256\":\"" << final_sha << "\""
            << ",\"host_math\":false,"
               "\"tensor_promotion\":false,"
               "\"scope\":\"readout checkpoint gate only; no 48M or page promotion\"}\n";
        std::cout << "head_readout_loop baseline=" << baseline_nll
                  << " candidate=" << candidate_nll
                  << " accepted=" << (accepted ? "true" : "false")
                  << " candidates=" << candidate_count
                  << " output=" << argv[6] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_readout_loop_error: " << e.what() << "\n";
        return 1;
    }
}
