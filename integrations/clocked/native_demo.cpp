// Clocked -> native NaNLMind routing demo.
// This is a small, explicit task-family experiment, not a language-model benchmark.
// Training rows are admitted only after the Python harness verifies Clocked's
// predicted label against an independently supplied gold label.
#include "nanlm/bootstrap_router.hpp"
#include "nanlm/learning_mesh.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <utility>

namespace {
using namespace nanlm;

struct Sample {
    std::uint32_t label = 0;
    std::string text;
};

const std::array<std::string, 6> kLabels{{
    "technical_document", "code_or_script", "support_request",
    "general_prose", "structured_record", "unknown"
}};

int label_id(const std::string& value) {
    for (std::size_t i = 0; i < kLabels.size(); ++i)
        if (kLabels[i] == value) return static_cast<int>(i);
    return -1;
}

std::vector<std::string> words(const std::string& text) {
    std::vector<std::string> out;
    std::string current;
    for (unsigned char c : text) {
        if (std::isalnum(c)) current.push_back(static_cast<char>(std::tolower(c)));
        else if (!current.empty()) { out.push_back(current); current.clear(); }
    }
    if (!current.empty()) out.push_back(current);
    return out;
}

std::uint8_t family_dimension(const std::vector<std::string>& tokens) {
    // Transparent lexical anchors make this a small routing-memory demo.
    // They are not claimed to be a general semantic encoder.
    static const std::array<std::vector<std::string>, 5> anchors{{
        {"technical", "architecture", "specification", "protocol", "design", "documentation"},
        {"python", "code", "script", "compiler", "function", "debug"},
        {"support", "customer", "login", "password", "account", "reset"},
        {"meeting", "notes", "prose", "story", "report", "paragraph"},
        {"invoice", "receipt", "amount", "total", "payment", "due"}
    }};
    std::array<unsigned, 5> counts{};
    for (const auto& token : tokens)
        for (std::size_t family = 0; family < anchors.size(); ++family)
            if (std::find(anchors[family].begin(), anchors[family].end(), token) != anchors[family].end())
                ++counts[family];
    std::size_t best = 0;
    for (std::size_t i = 1; i < counts.size(); ++i)
        if (counts[i] > counts[best]) best = i;
    if (counts[best] == 0) return 20; // unknown bucket
    return static_cast<std::uint8_t>(best * 4);
}

HopfieldRouter::Vector encode(const std::string& text) {
    HopfieldRouter::Vector query{};
    const auto tokens = words(text);
    const std::uint8_t anchor = family_dimension(tokens);
    query[anchor] = 256;
    // Add bounded, deterministic lexical context outside the anchor dimension.
    for (const auto& token : tokens) {
        std::uint32_t hash = 2166136261u;
        for (unsigned char c : token) { hash ^= c; hash *= 16777619u; }
        const std::size_t dim = 24u + (hash % 8u);
        if (query[dim] < 100) ++query[dim];
    }
    return query;
}

bool read_samples(const std::string& path, std::vector<Sample>& train,
                  std::vector<Sample>& test) {
    std::ifstream in(path);
    if (!in) return false;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty()) continue;
        const auto first = line.find('\t');
        const auto second = first == std::string::npos ? first : line.find('\t', first + 1);
        if (first == std::string::npos || second == std::string::npos) return false;
        const std::string split = line.substr(0, first);
        const std::string label = line.substr(first + 1, second - first - 1);
        const std::string text = line.substr(second + 1);
        const int id = label_id(label);
        if (id < 0 || text.empty()) return false;
        Sample sample{static_cast<std::uint32_t>(id), text};
        if (split == "train") train.push_back(std::move(sample));
        else if (split == "test") test.push_back(std::move(sample));
        else return false;
    }
    return !train.empty() && !test.empty();
}

std::string event_id(std::uint64_t n) {
    std::ostringstream out;
    out << std::hex << std::setfill('0') << std::setw(64) << n;
    return out.str();
}

struct Score { std::size_t total = 0, correct = 0, abstain = 0; };

Score evaluate(const HopfieldRouter& router, const std::vector<Sample>& samples) {
    Score score;
    for (const auto& sample : samples) {
        ++score.total;
        const auto prediction = router.predict(encode(sample.text));
        if (prediction.abstain) ++score.abstain;
        else if (prediction.token == sample.label) ++score.correct;
    }
    return score;
}

double accuracy(const Score& score) {
    return score.total ? static_cast<double>(score.correct) / score.total : 0.0;
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: clocked-demo <verified-samples.tsv>\n";
        return 2;
    }

    std::vector<Sample> train, test;
    if (!read_samples(argv[1], train, test)) {
        std::cerr << "invalid or empty verified sample file\n";
        return 2;
    }

    HopfieldConfig config;
    config.top_k = 1;
    config.max_strength = 32767;
    HopfieldRouter router(config);
    for (std::uint16_t h = 0; h < 256; ++h) {
        HopfieldRouter::Vector key{};
        key[h % HopfieldRouter::kDim] = 1;
        router.set_head(static_cast<std::uint8_t>(h), key);
    }

    const Score baseline = evaluate(router, test);
    OverbootstrapLearner overbootstrap;
    std::uint64_t event_number = 1;
    for (const auto& sample : train) {
        const auto query = encode(sample.text);
        const auto before = router.predict(query);
        EndpointObservation observation;
        observation.endpoint = EndpointId::ClockedDemo;
        observation.base_generation = 0;
        observation.event_id = event_id(event_number++);
        observation.active_heads = before.active;
        observation.outcome_verified = true; // Python runner checked Clocked label against gold.
        observation.correct = true;
        if (overbootstrap.observe_endpoint(observation) != EndpointIngestResult::Accepted) {
            std::cerr << "native evidence fold rejected a verified demo event\n";
            return 3;
        }
        if (!router.learn(query, sample.label)) {
            std::cerr << "native router could not learn a verified sample\n";
            return 3;
        }
    }

    const auto feedback = overbootstrap.feedback();
    std::size_t nonzero_biases = 0;
    std::int16_t max_bias = 0;
    for (std::uint16_t h = 0; h < 256; ++h) {
        const auto bias = feedback[h];
        router.set_head_bias(static_cast<std::uint8_t>(h), bias);
        if (bias != 0) ++nonzero_biases;
        max_bias = std::max<std::int16_t>(max_bias, static_cast<std::int16_t>(std::abs(bias)));
    }
    const Score replay = evaluate(router, test);
    const auto stats = overbootstrap.endpoint_stats(EndpointId::ClockedDemo);

    std::cout << "{"
              << "\"baseline_accuracy\":" << accuracy(baseline) << ","
              << "\"baseline_abstentions\":" << baseline.abstain << ","
              << "\"heldout_accuracy\":" << accuracy(replay) << ","
              << "\"heldout_correct\":" << replay.correct << ","
              << "\"heldout_total\":" << replay.total << ","
              << "\"verified_training_examples\":" << train.size() << ","
              << "\"clocked_verified_events\":" << stats.verified << ","
              << "\"clocked_evidence_only_events\":" << stats.evidence_only << ","
              << "\"nonzero_routing_biases\":" << nonzero_biases << ","
              << "\"max_abs_routing_bias\":" << max_bias << ","
              << "\"overbootstrap_digest\":\"";
    const auto digest = overbootstrap.digest();
    for (auto byte : digest) std::cout << std::hex << std::setw(2) << std::setfill('0') << static_cast<unsigned>(byte);
    std::cout << "\"}\n";
    return replay.correct == replay.total ? 0 : 4;
}
