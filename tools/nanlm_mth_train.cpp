// Native NaNLMind MTH seven-method trainer.
// The C++ caller only parses bounded receipts, stages NaN0S guest inputs,
// and reads results. All CFT/TRAIL/HOLO/RING/LEAF/TCA/FLUX and combination
// mathematics runs inside the original NaN16 .nas kernels.
#include "nanlm/raw_field.hpp"
#include <array>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using nanlm::RawFieldVM;
using nanlm::TrunkWeights;
constexpr std::size_t N = nanlm::kTriadMemberCount;
std::int64_t signed_value(const std::string& token) {
    std::size_t used = 0;
    const auto x = std::stoll(token, &used, 0);
    if (used != token.size() ||
        x < std::numeric_limits<std::int32_t>::min() ||
        x > std::numeric_limits<std::int32_t>::max())
        throw std::invalid_argument("invalid signed 32-bit input: " + token);
    return x;
}
std::int32_t q(const std::string& token) {
    return static_cast<std::int32_t>(signed_value(token));
}
std::uint32_t unsigned_value(const std::string& token) {
    std::size_t used = 0;
    if (!token.empty() && token[0] == '-')
        throw std::invalid_argument("negative unsigned input");
    const auto x = std::stoull(token, &used, 0);
    if (used != token.size() || x > std::numeric_limits<std::uint32_t>::max())
        throw std::invalid_argument("invalid unsigned 32-bit input: " + token);
    return static_cast<std::uint32_t>(x);
}
std::uint16_t turn(const std::string& token) {
    const auto x = unsigned_value(token);
    if (x > 65535u) throw std::invalid_argument("phase must be 16-bit turns");
    return static_cast<std::uint16_t>(x);
}
std::uint8_t head(const std::string& token) {
    const auto x = unsigned_value(token);
    if (x >= 255u) throw std::invalid_argument("head 255 is reserved");
    return static_cast<std::uint8_t>(x);
}
TrunkWeights initial_weights() {
    TrunkWeights w{};
    for (std::size_t i = 0; i < 64; ++i) {
        const bool diagonal = i / 8 == i % 8;
        w.wq[i] = diagonal ? 1.0f : 0.0f;
        w.wk[i] = w.wq[i];
        w.wv[i] = w.wq[i];
        w.wout[i] = w.wq[i];
    }
    for (std::size_t i = 0; i < 8; ++i) {
        w.w1[i * 8 + i] = 1.0f;
        w.w2[i * 16 + i] = 1.0f;
    }
    return w;
}
std::vector<std::array<float, nanlm::kRawFeatureDim>>
tokens_from_hex(const std::string& hex) {
    if (hex.size() != 16) throw std::invalid_argument("context must be eight hex bytes");
    std::vector<std::array<float, nanlm::kRawFeatureDim>> tokens(8);
    for (std::size_t i = 0; i < 8; ++i) {
        if (!std::isxdigit(static_cast<unsigned char>(hex[2 * i])) ||
            !std::isxdigit(static_cast<unsigned char>(hex[2 * i + 1])))
            throw std::invalid_argument("invalid context hex");
        const auto value = std::stoul(hex.substr(i * 2, 2), nullptr, 16);
        tokens[i][value & 7u] = 1.0f;
    }
    return tokens;
}
std::vector<std::string> words(const std::string& line) {
    std::istringstream stream(line);
    std::vector<std::string> result;
    std::string token;
    while (stream >> token) {
        if (token[0] == '#') break;
        result.push_back(token);
    }
    return result;
}
void require(bool ok, const RawFieldVM& vm, const char* label) {
    if (!ok) throw std::runtime_error(std::string(label) + ": " + vm.error());
}
void emit_weights(const std::string& path, RawFieldVM& vm) {
    TrunkWeights current{};
    require(vm.read_trunk_weights(current), vm, "read final trunk");
    std::ofstream file(path, std::ios::trunc);
    if (!file) throw std::runtime_error("cannot open output weights");
    file << "N16MTHWEIGHTS/1\n" << std::hexfloat;
    const auto write = [&file](const char* label, const auto& values) {
        file << label;
        for (float v : values) file << ' ' << v;
        file << '\n';
    };
    write("WQ", current.wq);
    write("WK", current.wk);
    write("WV", current.wv);
    write("WOUT", current.wout);
    write("W1", current.w1);
    write("W2", current.w2);
    if (!file) throw std::runtime_error("cannot persist native trunk weights");
}
void run_step(RawFieldVM& vm,
              const std::vector<std::string>& t,
              const std::array<std::uint16_t, N>& ring_phases,
              std::uint64_t number, std::uint64_t& applied_count) {
    // step + 42 fields, each required. No implicit or invented geometry.
    if (t.size() != 43) throw std::invalid_argument(
        "step needs 42 inputs: 8-byte context hex, target, wrong, rate, threshold, "
        "CFT[5], TRAIL[11], HOLO[3], RING[1], LEAF[3], TCA[3], FLUX[4], coeff[7]");
    std::size_t k = 1;
    const auto tokens = tokens_from_hex(t[k++]);
    const std::uint8_t target = head(t[k++]), wrong = head(t[k++]);
    if (target == wrong) throw std::invalid_argument("target equals wrong head");
    const std::int32_t lr = q(t[k++]), threshold = q(t[k++]);
    if (lr <= 0 || lr > 65536) throw std::invalid_argument("base rate must be Q16.16 (0,1]");
    std::array<std::int32_t, 5> cft{};
    std::array<std::int32_t, 11> trail{};
    std::array<std::uint16_t, 3> holo{};
    std::array<std::int32_t, 3> leaf{};
    std::array<std::int32_t, 3> tca{};
    std::array<std::int32_t, 4> flux{};
    std::array<std::int32_t, 7> coeff{};
    for (auto& v : cft) v = q(t[k++]);
    for (auto& v : trail) v = q(t[k++]);
    for (auto& v : holo) v = turn(t[k++]);
    const auto shift = unsigned_value(t[k++]);
    if (shift >= N) throw std::invalid_argument("ring shift outside 255 heads");
    for (auto& v : leaf) v = q(t[k++]);
    for (auto& v : tca) v = q(t[k++]);
    for (auto& v : flux) v = q(t[k++]);
    for (auto& v : coeff) v = q(t[k++]);
    if (k != t.size()) throw std::logic_error("native MTH parser mismatch");

    std::array<float, nanlm::kRawFeatureDim> feature{};
    require(vm.causal_trunk_cached(tokens, feature), vm, "causal native trunk");
    std::array<float, nanlm::kRawFeatureDim> target_row{}, wrong_row{};
    target_row[0] = 1.0f;
    wrong_row[0] = -1.0f;
    require(vm.set_readout_row(target, target_row), vm, "target readout");
    require(vm.set_readout_row(wrong, wrong_row), vm, "wrong readout");

    std::array<std::int32_t, 4> cft_out{};
    std::array<std::int32_t, 3> trail_out{}, flux_out{};
    std::array<std::int32_t, 2> holo_out{}, leaf_out{};
    std::int32_t ring_out = 0, tca_out = 0;
    require(vm.cft(cft[0], cft[1], cft[2], cft[3], cft[4], cft_out),
            vm, "CFT NaN16");
    require(vm.trail(trail[0], trail[1], trail[2], trail[3], trail[4],
                     trail[5], trail[6], trail[7], trail[8],
                     trail[9], trail[10], trail_out), vm, "TRAIL NaN16");
    require(vm.holo(holo, holo_out), vm, "HOLO NaN16");
    require(vm.ring(ring_phases, shift, ring_out), vm, "RING NaN16");
    require(vm.leaf(static_cast<std::uint32_t>(leaf[0]),
                    static_cast<std::uint32_t>(leaf[1]), leaf[2], leaf_out),
            vm, "LEAF NaN16");
    require(vm.tca(tca[0], tca[1], tca[2], tca_out), vm, "TCA NaN16");
    require(vm.flux(flux[0], flux[1], flux[2], flux[3], flux_out),
            vm, "FLUX NaN16");
    const std::array<std::int32_t, 7> credit = {
        cft_out[3], trail_out[2], holo_out[1], ring_out,
        leaf_out[1], tca_out, flux_out[2]};
    std::int32_t combined = 0;
    require(vm.combine_credits(credit, coeff, combined), vm, "MTH7 NaN16 combiner");

    // The guest gate, trunk, QKV and readout values are resident in one VM.
    // No host-side reimplementation of the gradients is permitted.
    bool applied = false;
    require(vm.combined_trunk_credit_all(target, wrong, lr, threshold,
                                         credit, coeff, applied), vm,
            "MTH7 native credit commit");
    applied_count += applied ? 1u : 0u;
    std::cout << "NANLM_MTH7_STEP index=" << number
              << " CFT=" << credit[0] << " TRAIL=" << credit[1]
              << " HOLO=" << credit[2] << " RING=" << credit[3]
              << " LEAF=" << credit[4] << " TCA=" << credit[5]
              << " FLUX=" << credit[6] << " combined=" << combined
              << " accepted=" << int(applied) << " bptt_attempted=0\n";
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 4 || std::string(argv[2]) != "--out")
            throw std::invalid_argument(
                "usage: build/nanlm-train INPUT.n16mth --out OUTPUT.weights "
                "(raw NaN16 seven-method credit source)");
        RawFieldVM vm("build/field_driver.nan");
        require(vm.ready(), vm, "load MTH native driver");
        require(vm.write_trunk_weights(initial_weights()), vm, "initialize native trunk");
        vm.reset_readout();

        std::ifstream file(argv[1]);
        if (!file) throw std::runtime_error("cannot open N16MTH/1 input");
        std::array<std::uint16_t, N> ring_phases{};
        bool header = false;
        std::uint64_t steps = 0, accepted = 0;
        std::string line;
        std::size_t line_no = 0;
        while (std::getline(file, line)) {
            ++line_no;
            const auto t = words(line);
            if (t.empty()) continue;
            if (!header) {
                if (t.size() != 1 || t[0] != "N16MTH/1")
                    throw std::invalid_argument("first non-comment line must be N16MTH/1");
                header = true;
                continue;
            }
            if (t[0] == "phase") {
                if (t.size() != 3) throw std::invalid_argument("phase requires head turn");
                ring_phases[head(t[1])] = turn(t[2]);
            } else if (t[0] == "step") {
                run_step(vm, t, ring_phases, steps + 1, accepted);
                ++steps;
            } else {
                throw std::invalid_argument("unknown training record: " + t[0]);
            }
        }
        if (file.bad() || !header || steps == 0)
            throw std::runtime_error("empty, corrupt or headerless N16MTH/1 corpus");
        emit_weights(argv[3], vm);
        std::cout << "NANLM_MTH7_TRAIN source=" << argv[1]
                  << " rows=" << steps << " accepted=" << accepted
                  << " output=" << argv[3] << " native_kernels=7"
                  << " bptt_attempted=0\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "NANLM_MTH7_ERROR " << e.what() << '\n';
        return 2;
    }
}
