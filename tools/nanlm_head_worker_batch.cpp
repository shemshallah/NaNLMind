// Head-worker batch CLI adapter.
//
// Loads selected 1 MiB head pages from a directory, runs the native six-token
// worker for each selected head through the opcode122 ABI, and serializes the
// guest states.  The host performs file transport, page paging, selection and
// JSON serialization only; it computes no attention, LayerNorm or MLP.
#include "nanlm/head_worker_scheduler.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace nanlm;

namespace {
std::vector<std::uint8_t> read_bytes(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("cannot read " + path);
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}
std::vector<float> read_floats(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("cannot read " + path);
    std::vector<float> out;
    float v = 0;
    while (in >> v) out.push_back(v);
    if (!in.eof()) throw std::runtime_error("not a float list: " + path);
    return out;
}
std::string json_quote(const std::string& text) {
    std::string out = "\"";
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
        else if (c < 0x20) {
            static const char* hex = "0123456789abcdef";
            out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15];
        } else out += static_cast<char>(c);
    }
    out += "\"";
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
    if (heads.empty() || heads.size() > HeadWorkerScheduler::kMaxHeads)
        throw std::runtime_error("heads must contain 1..16 active heads");
    return heads;
}
std::string page_path(const std::string& dir, unsigned head) {
    const std::string h3 = [&] {
        std::string s = std::to_string(head);
        while (s.size() < 3) s.insert(s.begin(), '0');
        return s;
    }();
    for (const std::string& name : {
             dir + "/head-" + h3 + ".page",
             dir + "/head-" + std::to_string(head) + ".page",
             dir + "/" + h3 + ".page"}) {
        std::ifstream test(name, std::ios::binary);
        if (test.good()) return name;
    }
    throw std::runtime_error("missing page for head " + std::to_string(head) +
                             " in " + dir);
}
} // namespace

int main(int argc, char** argv) {
    if (argc != 5) {
        std::cerr << "Usage: nanlm-head-worker-batch <pages-dir> <context.f32> "
                     "<heads> <out.json>\n"
                     "heads: comma-separated 0..254, at most 16\n";
        return 2;
    }
    try {
        const auto heads = parse_heads(argv[3]);
        const auto context_values = read_floats(argv[2]);
        if (context_values.empty() || context_values.size() % 128u != 0u)
            throw std::runtime_error("context must contain T*128 floats");
        const std::size_t token_count = context_values.size() / 128u;
        if (token_count < 1u || token_count > 6u)
            throw std::runtime_error("token count must be 1..6");
        std::array<float, 6 * 128> context{};
        for (std::size_t i = 0; i < context_values.size(); ++i)
            context[i] = context_values[i];

        RawFieldVM vm("build/head_worker.nan");
        if (!vm.ready()) throw std::runtime_error(vm.error());
        HeadPageArena pages;
        std::array<std::string, 16> page_sha{};
        for (std::size_t i = 0; i < heads.size(); ++i) {
            const auto path = page_path(argv[1], heads[i]);
            const auto bytes = read_bytes(path);
            if (bytes.size() != HeadPageArena::kPageBytes)
                throw std::runtime_error("page must be exactly 1 MiB: " + path);
            pages.load_page(heads[i], bytes.data(), bytes.size());
            page_sha[i] = hex(Sha256::hash(bytes.data(), bytes.size()));
        }

        std::array<float, 255> credits{};
        for (std::size_t i = 0; i < heads.size(); ++i)
            credits[heads[i]] = static_cast<float>(heads.size() - i);
        HeadWorkerScheduler scheduler(vm, pages);
        const auto batch = scheduler.run(
            credits, context, static_cast<std::uint8_t>(token_count),
            heads.size());
        if (!batch.accepted)
            throw std::runtime_error("head worker batch rejected reason=" +
                                     std::to_string(batch.reason));

        std::ofstream out(argv[4], std::ios::binary | std::ios::trunc);
        if (!out) throw std::runtime_error("cannot open output");
        out << "{\"schema\":\"nanlm.head-worker-batch/1\","
               "\"accepted\":true,\"token_count\":" << token_count
            << ",\"host_math\":false,\"selected\":[";
        for (std::size_t i = 0; i < batch.heads.size(); ++i) {
            const auto& state = batch.heads[i];
            if (i) out << ',';
            const std::size_t base =
                (static_cast<std::size_t>(state.token_count) - 1u) * 128u;
            out << "{\"head\":" << unsigned(state.head)
                << ",\"slot\":" << unsigned(state.slot)
                << ",\"page_sha256\":" << json_quote(page_sha[i])
                << ",\"last_state\":[";
            for (unsigned d = 0; d < 128u; ++d) {
                if (d) out << ',';
                out << state.output[base + d];
            }
            out << "]}";
        }
        out << "],\"resident\":" << scheduler.resident_count()
            << ",\"zero_void_head\":true}\n";
        std::cout << "head_worker_batch selected=" << batch.heads.size()
                  << " tokens=" << token_count
                  << " resident=" << scheduler.resident_count()
                  << " output=" << argv[4] << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "head_worker_batch_error: " << e.what() << "\n";
        return 1;
    }
}
