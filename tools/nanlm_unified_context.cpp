// Unified long-context CLI: checkpoint -> native 64-slot worker -> summary bank
// -> native retrieval. Host performs transport, selection and JSON only.
#include "nanlm/unified_context_runtime.hpp"

#include <array>
#include <cmath>
#include <cstdint>
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
void load_bank(SummaryBank& bank, const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read bank " + path);
    std::string line;
    ChunkSummary current{};
    bool open = false;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        std::istringstream ss(line);
        std::uint64_t id = 0, count = 0;
        unsigned head = 0;
        if (!(ss >> id >> count >> head) || head >= 255u)
            throw std::runtime_error("malformed bank line");
        std::array<float, 128> state{};
        for (unsigned d = 0; d < 128u; ++d)
            if (!(ss >> state[d]) || !std::isfinite(state[d]))
                throw std::runtime_error("malformed bank state");
        if (!open || id != current.chunk_id) {
            if (open) bank.append(std::move(current));
            current = ChunkSummary{};
            current.chunk_id = id;
            current.token_count = static_cast<std::size_t>(count);
            open = true;
        } else if (current.token_count != count) {
            throw std::runtime_error("bank chunk token-count mismatch");
        }
        for (unsigned old : current.heads)
            if (old == head) throw std::runtime_error("duplicate bank head");
        current.heads.push_back(head);
        current.states.push_back(state);
        if (bank.size() + (open ? 1u : 0u) > bank.capacity())
            throw std::runtime_error("bank capacity exceeded");
    }
    if (open) bank.append(std::move(current));
}
void write_state(std::ostream& out, const std::array<float, 128>& state) {
    out << '[';
    for (unsigned d = 0; d < 128u; ++d) {
        if (d) out << ',';
        out << state[d];
    }
    out << ']';
}
} // namespace

int main(int argc, char** argv) {
    if (argc < 6) {
        std::cerr << "Usage: nanlm-unified-context <checkpoint-dir> <heads.csv> "
                     "<credits.f32> <tokens.f32> <out.json> [--bank bank.tsv] "
                     "[--top-k N] [--summary-k N] [--local-limit N] "
                     "[--retrieve-head H] [--retrieve-k N] [--query query.f32]\n";
        return 2;
    }
    try {
        const auto heads = parse_heads(argv[2]);
        const auto credit_values = read_floats(argv[3]);
        if (credit_values.size() != 255u)
            throw std::runtime_error("credits must contain exactly 255 floats");
        std::array<float, 255> credits{};
        for (unsigned i = 0; i < 255u; ++i) credits[i] = credit_values[i];
        const auto token_values = read_floats(argv[4]);
        if (token_values.empty() || token_values.size() % 128u != 0u)
            throw std::runtime_error("tokens must contain T*128 floats");
        std::vector<std::array<float, 128>> tokens(token_values.size() / 128u);
        for (std::size_t i = 0; i < tokens.size(); ++i)
            for (unsigned d = 0; d < 128u; ++d)
                tokens[i][d] = token_values[i * 128u + d];

        std::string bank_path;
        std::size_t top_k = 20u, summary_k = 2u, local_limit = 0u;
        std::size_t retrieve_k = 8u;
        unsigned retrieve_head = heads.front();
        std::vector<float> query_values;
        for (int i = 6; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg == "--bank" && i + 1 < argc) bank_path = argv[++i];
            else if (arg == "--top-k" && i + 1 < argc) top_k = std::stoul(argv[++i]);
            else if (arg == "--summary-k" && i + 1 < argc) summary_k = std::stoul(argv[++i]);
            else if (arg == "--local-limit" && i + 1 < argc) local_limit = std::stoul(argv[++i]);
            else if (arg == "--retrieve-k" && i + 1 < argc) retrieve_k = std::stoul(argv[++i]);
            else if (arg == "--retrieve-head" && i + 1 < argc) retrieve_head = std::stoul(argv[++i]);
            else if (arg == "--query" && i + 1 < argc) query_values = read_floats(argv[++i]);
            else throw std::runtime_error("unknown/incomplete argument " + arg);
        }
        if (retrieve_head >= 255u) throw std::runtime_error("retrieve head invalid");
        if (!query_values.empty() && query_values.size() != 128u)
            throw std::runtime_error("query must contain 128 floats");

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        HeadPageArena arena;
        UnifiedContextRuntime runtime(vm, arena);
        runtime.load_checkpoint(argv[1], heads);

        SummaryBank bank(512);
        if (!bank_path.empty()) load_bank(bank, bank_path);
        const std::size_t loaded = bank.size();
        const auto result = runtime.advance(
            credits, tokens, top_k, bank_path.empty() ? nullptr : &bank,
            bank_path.empty() ? 0u : summary_k, local_limit);
        if (!result.accepted)
            throw std::runtime_error("unified context rejected reason=" +
                                     std::to_string(result.reason));

        std::array<float, 128> query{};
        const bool query_file = !query_values.empty();
        if (query_file)
            for (unsigned d = 0; d < 128u; ++d) query[d] = query_values[d];
        else
            query = runtime.memory(retrieve_head);
        const auto hits = runtime.retrieve(bank, retrieve_head, query, retrieve_k);

        std::ofstream out(argv[5], std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write output");
        out << "{\"schema\":\"nanlm.unified-context/1\","
               "\"accepted\":true,\"host_math\":false,"
               "\"checkpoint\":{\"heads\":[";
        for (std::size_t i = 0; i < heads.size(); ++i) {
            if (i) out << ',';
            out << heads[i];
        }
        out << "],\"resident\":" << runtime.resident_pages()
            << "},\"input\":{\"credits\":255,\"tokens\":" << tokens.size()
            << ",\"dim\":128},\"bank\":{\"capacity\":512,\"loaded\":" << loaded
            << ",\"size\":" << bank.size() << "},"
               "\"advance\":{\"hierarchical\":"
            << (bank_path.empty() ? "false" : "true")
            << ",\"chunks\":" << result.chunks << ",\"heads\":[";
        for (std::size_t i = 0; i < result.heads.size(); ++i) {
            if (i) out << ',';
            out << result.heads[i];
        }
        out << "],\"final_states\":[";
        for (std::size_t i = 0; i < result.final_states.size(); ++i) {
            if (i) out << ',';
            write_state(out, result.final_states[i]);
        }
        out << "]},\"retrieve\":{\"head\":" << retrieve_head
            << ",\"query\":\"" << (query_file ? "file" : "memory") << "\""
            << ",\"top_k\":" << retrieve_k << ",\"hits\":[";
        for (std::size_t i = 0; i < hits.size(); ++i) {
            if (i) out << ',';
            out << "{\"bank_index\":" << hits[i].bank_index
                << ",\"head_index\":" << hits[i].head_index
                << ",\"chunk_id\":" << hits[i].chunk_id
                << ",\"score\":" << hits[i].score << '}';
        }
        out << "]},\"memory\":{\"head\":" << heads.front() << ",\"state\":";
        write_state(out, runtime.memory(static_cast<std::uint8_t>(heads.front())));
        out << "}}\n";
        std::cout << "unified_context heads=" << heads.size()
                  << " tokens=" << tokens.size()
                  << " summaries=" << bank.size()
                  << " hits=" << hits.size()
                  << " output=" << argv[5] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "unified_context_error: " << e.what() << "\n";
        return 1;
    }
}
