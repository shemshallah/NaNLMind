#include "nanlm/trunk_train.hpp"
#include "nanlm/raw_field.hpp"
#include "nanlm/sha256.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <unordered_map>
#include <unordered_set>
#include <string>
#include <vector>

namespace nanlm {
namespace {
TrunkWeights identity_trunk() {
    TrunkWeights w;
    for (std::size_t i = 0; i < 64; ++i) {
        const bool diagonal = (i / 8 == i % 8);
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

std::vector<std::uint8_t> make_window(std::string_view line,
                                       std::size_t window) {
    std::vector<std::uint8_t> bytes(window, static_cast<std::uint8_t>(' '));
    const std::size_t take = std::min(window, line.size());
    const std::size_t offset = window - take;
    for (std::size_t i = 0; i < take; ++i)
        bytes[offset + i] = static_cast<std::uint8_t>(line[line.size() - take + i]);
    return bytes;
}

std::array<float, kRawFeatureDim> token_vector(std::uint8_t byte) {
    std::array<float, kRawFeatureDim> v{};
    v[byte & 7u] = 1.0f;
    return v;
}
} // namespace

int trunk_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal trunk-train CORPUS [MAX_LINES] [EPOCHS] [REPORT_EVERY]"
                     " [sampled|full|softmax] [ordered|shuffle] [LR] [EVAL_EVERY] [LR_DECAY]\n"
                  << "Runs raw NaN16 trunk readout training over the whole corpus.\n"
                  << "softmax (default) trains all 255 rows and learns; sampled is the fast diagnostic path.\n"
                  << "softmax trains all 255 rows with a full softmax step.\n"
                  << "EVAL_EVERY runs the full 255-class evaluation after that many epochs.\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, epochs = 3, report_every = 1000, eval_every = 0;
    std::string mode = argc > 6 ? argv[6] : "softmax";
    std::string order_mode = argc > 7 ? argv[7] : "ordered";
    float base_lr = 0.05f;
    float lr_decay = 1.0f;
    if (mode != "sampled" && mode != "full" && mode != "softmax") {
        std::cerr << "mode must be sampled, full or softmax\n";
        return 2;
    }
    if (order_mode != "ordered" && order_mode != "shuffle") {
        std::cerr << "order must be ordered or shuffle\n";
        return 2;
    }
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) epochs = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) report_every = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 8) base_lr = std::stof(argv[8]);
        if (argc > 9) eval_every = static_cast<std::size_t>(std::stoull(argv[9]));
        if (argc > 10) lr_decay = std::stof(argv[10]);
    } catch (...) { std::cerr << "invalid numeric argument\n"; return 2; }
    if (base_lr <= 0.0f || lr_decay <= 0.0f) {
        std::cerr << "learning rate and decay must be positive\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    std::string data((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    std::vector<std::string_view> lines;
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        if (end == std::string::npos) {
            if (begin < data.size()) lines.emplace_back(data.data() + begin,
                                                        data.size() - begin);
            break;
        }
        lines.emplace_back(data.data() + begin, end - begin);
        begin = end + 1;
        if (max_lines && lines.size() >= max_lines) break;
    }
    std::vector<std::string_view> usable;
    usable.reserve(lines.size());
    for (const auto line : lines) {
        if (line.size() >= 9 && static_cast<std::uint8_t>(line[8]) < 255) {
            usable.push_back(line);
        }
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    vm.reset_readout();
    const TrunkWeights weights = identity_trunk();
    if (!vm.write_trunk_weights(weights)) {
        std::cerr << "raw trunk weights unavailable: " << vm.error() << "\n";
        return 7;
    }
    // The trunk is frozen in this run. Compute every feature once, then train
    // only the readout in the epoch loop.
    std::vector<std::array<float, kRawFeatureDim>> cached_features;
    std::vector<std::uint8_t> cached_targets;
    cached_features.reserve(usable.size());
    cached_targets.reserve(usable.size());
    const auto feature_started = std::chrono::steady_clock::now();
    for (const auto line : usable) {
        std::vector<std::array<float, kRawFeatureDim>> tokens;
        tokens.reserve(8);
        for (std::size_t j = 0; j < 8; ++j) {
            tokens.push_back(token_vector(static_cast<std::uint8_t>(line[j])));
        }
        std::array<float, kRawFeatureDim> feature{};
        if (!vm.trunk_feature(tokens, feature)) {
            std::cerr << "native trunk feature failed: " << vm.error() << "\n";
            return 7;
        }
        cached_features.push_back(feature);
        cached_targets.push_back(static_cast<std::uint8_t>(line[8]));
    }
    const double feature_seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - feature_started).count();
    std::cout << "trunk_features samples=" << cached_features.size()
              << " seconds=" << feature_seconds << "\n";

    const auto evaluate = [&](std::size_t epoch, bool final) {
        const auto eval_started = std::chrono::steady_clock::now();
        std::size_t eval_total = 0, eval_correct = 0;
        double eval_loss = 0.0;
        for (std::size_t sample = 0; sample < cached_features.size(); ++sample) {
            bool correct = false;
            float target_score = 0.0f, best_wrong = 0.0f, loss = 0.0f;
            if (!vm.readout_only(cached_features[sample], cached_targets[sample], 0.0f,
                                 correct, target_score, best_wrong, loss)) {
                std::cerr << "native full evaluation failed: " << vm.error() << "\n";
                return false;
            }
            ++eval_total;
            eval_correct += correct ? 1u : 0u;
            eval_loss += loss;
        }
        const double eval_seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - eval_started).count();
        const auto print = [&](const char* tag) {
            std::cout << tag << " samples=" << eval_total
                      << " loss=" << (eval_loss / std::max<std::size_t>(1, eval_total))
                      << " accuracy="
                      << (100.0 * eval_correct / std::max<std::size_t>(1, eval_total))
                      << " seconds=" << eval_seconds;
            if (!final) std::cout << " epoch=" << epoch;
            std::cout << "\n";
        };
        print(final ? "trunk_full_eval" : "trunk_eval");
        return true;
    };

    std::vector<std::size_t> order(cached_features.size());
    for (std::size_t i = 0; i < order.size(); ++i) order[i] = i;
    std::mt19937 rng(1);
    const auto started = std::chrono::steady_clock::now();
    std::size_t global_step = 0;
    bool final_evaluated = false;
    for (std::size_t epoch = 1; epoch <= epochs; ++epoch) {
        if (order_mode == "shuffle") {
            std::shuffle(order.begin(), order.end(), rng);
        }
        const float lr = base_lr * std::pow(lr_decay, static_cast<float>(epoch - 1));
        std::size_t epoch_total = 0, epoch_correct = 0;
        double epoch_loss = 0.0;
        std::size_t report_total = 0, report_correct = 0;
        double report_loss = 0.0;
        for (std::size_t position = 0; position < order.size(); ++position) {
            const std::size_t sample = order[position];
            const std::uint8_t target = cached_targets[sample];
            bool correct = false;
            float target_score = 0.0f, best_wrong = 0.0f, loss = 0.0f;
            const bool full_step = mode == "full" ||
                ((position + epoch * 7u) % 16u) == 0u;
            const std::uint32_t salt = static_cast<std::uint32_t>(global_step);
            bool step_ok = false;
            if (mode == "softmax") {
                float target_probability = 0.0f;
                step_ok = vm.readout_softmax(cached_features[sample], target, lr,
                                             correct, loss, target_probability);
            } else if (full_step) {
                step_ok = vm.readout_only(cached_features[sample], target, lr,
                                          correct, target_score, best_wrong, loss);
            } else {
                step_ok = vm.readout_sample(cached_features[sample], target, lr, salt,
                                            correct, target_score, best_wrong, loss);
            }
            if (!step_ok) {
                std::cerr << "native readout step failed: " << vm.error() << "\n";
                return 7;
            }
            ++global_step;
            ++epoch_total;
            ++report_total;
            epoch_correct += correct ? 1u : 0u;
            report_correct += correct ? 1u : 0u;
            epoch_loss += loss;
            report_loss += loss;
            if (report_every && report_total >= report_every) {
                std::cout << "trunk_step epoch=" << epoch
                          << " step=" << global_step
                          << " train_loss=" << (report_loss / report_total)
                          << " train_accuracy="
                          << (100.0 * report_correct / report_total)
                          << "\n";
                report_total = report_correct = 0;
                report_loss = 0.0;
            }
        }
        if (report_total) {
            std::cout << "trunk_step epoch=" << epoch
                      << " step=" << global_step
                      << " train_loss=" << (report_loss / report_total)
                      << " train_accuracy="
                      << (100.0 * report_correct / report_total)
                      << "\n";
        }
        const auto elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        std::cout << "trunk_epoch epoch=" << epoch
                  << " samples=" << epoch_total
                  << " train_loss=" << (epoch_loss / std::max<std::size_t>(1, epoch_total))
                  << " train_accuracy="
                  << (100.0 * epoch_correct / std::max<std::size_t>(1, epoch_total))
                  << " seconds=" << elapsed
                  << " lr=" << lr
                  << "\n";
        if (eval_every && epoch % eval_every == 0) {
            const bool last = epoch == epochs;
            if (!evaluate(epoch, last)) return 7;
            final_evaluated = last;
        }
    }
    if (!final_evaluated && !evaluate(epochs, true)) return 7;
    return 0;
}

int hier_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal hier-train CORPUS [MAX_LINES] [EPOCHS]"
                     " [REPORT_EVERY] [LR] [LR_DECAY] [EVAL_EVERY]\n"
                  << "Trains a raw 16x16 conditional nibble readout on the last four bytes.\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, epochs = 3, report_every = 10000, eval_every = 1;
    float base_lr = 0.5f, lr_decay = 1.0f;
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) epochs = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) report_every = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 6) base_lr = std::stof(argv[6]);
        if (argc > 7) lr_decay = std::stof(argv[7]);
        if (argc > 8) eval_every = static_cast<std::size_t>(std::stoull(argv[8]));
    } catch (...) { std::cerr << "invalid numeric argument\n"; return 2; }
    if (base_lr <= 0.0f || lr_decay <= 0.0f) {
        std::cerr << "learning rate and decay must be positive\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    std::string data((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    std::vector<std::string_view> lines;
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        if (end == std::string::npos) {
            if (begin < data.size()) lines.emplace_back(data.data() + begin,
                                                        data.size() - begin);
            break;
        }
        lines.emplace_back(data.data() + begin, end - begin);
        begin = end + 1;
        if (max_lines && lines.size() >= max_lines) break;
    }
    std::vector<std::string_view> usable;
    usable.reserve(lines.size());
    for (const auto line : lines) {
        if (line.size() >= 9 && static_cast<std::uint8_t>(line[8]) < 255) {
            usable.push_back(line);
        }
    }
    // Positional nibble feature: four recent bytes, each represented by
    // separate low/high nibble one-hots. This is a tokenizer feature bank;
    // the readout arithmetic and updates are raw NaN16.
    constexpr std::size_t kDim = 128;
    std::vector<float> features(usable.size() * kDim, 0.0f);
    std::vector<std::uint8_t> targets(usable.size());
    for (std::size_t i = 0; i < usable.size(); ++i) {
        const auto line = usable[i];
        targets[i] = static_cast<std::uint8_t>(line[8]);
        float* row = features.data() + i * kDim;
        for (std::size_t k = 0; k < 4; ++k) {
            const std::uint8_t byte = static_cast<std::uint8_t>(line[7 - k]);
            row[k * 32 + (byte & 15u)] = 1.0f;
            row[k * 32 + 16 + (byte >> 4)] = 1.0f;
        }
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.reset_hier_readout(kDim)) {
        std::cerr << "cannot reset hierarchical readout: " << vm.error() << "\n";
        return 7;
    }
    const auto evaluate = [&](std::size_t epoch, bool final) -> bool {
        const auto started = std::chrono::steady_clock::now();
        std::size_t total = 0, correct_count = 0;
        double loss_sum = 0.0;
        for (std::size_t sample = 0; sample < usable.size(); ++sample) {
            bool correct = false;
            float loss = 0.0f;
            std::uint8_t ph = 0, pl = 0;
            if (!vm.readout_hier(features.data() + sample * kDim, targets[sample],
                                 0.0f, kDim, correct, loss, ph, pl)) {
                std::cerr << "hier eval failed: " << vm.error() << "\n";
                return false;
            }
            ++total;
            correct_count += correct ? 1u : 0u;
            loss_sum += loss;
        }
        const double seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        const auto print = [&](const char* tag) {
            std::cout << tag << " samples=" << total
                      << " loss=" << (loss_sum / std::max<std::size_t>(1, total))
                      << " accuracy="
                      << (100.0 * correct_count / std::max<std::size_t>(1, total))
                      << " seconds=" << seconds;
            if (!final) std::cout << " epoch=" << epoch;
            std::cout << "\n";
        };
        print(final ? "hier_full_eval" : "hier_eval");
        return true;
    };

    std::vector<std::size_t> order(usable.size());
    for (std::size_t i = 0; i < order.size(); ++i) order[i] = i;
    std::mt19937 rng(1);
    std::size_t global_step = 0;
    bool final_evaluated = false;
    const auto started = std::chrono::steady_clock::now();
    for (std::size_t epoch = 1; epoch <= epochs; ++epoch) {
        std::shuffle(order.begin(), order.end(), rng);
        const float lr = base_lr * std::pow(lr_decay, static_cast<float>(epoch - 1));
        std::size_t epoch_total = 0, epoch_correct = 0;
        std::size_t report_total = 0, report_correct = 0;
        double epoch_loss = 0.0, report_loss = 0.0;
        for (std::size_t position = 0; position < order.size(); ++position) {
            const std::size_t sample = order[position];
            bool correct = false;
            float loss = 0.0f;
            std::uint8_t ph = 0, pl = 0;
            if (!vm.readout_hier(features.data() + sample * kDim, targets[sample],
                                 lr, kDim, correct, loss, ph, pl)) {
                std::cerr << "hier step failed: " << vm.error() << "\n";
                return 7;
            }
            ++global_step;
            ++epoch_total;
            ++report_total;
            epoch_correct += correct ? 1u : 0u;
            report_correct += correct ? 1u : 0u;
            epoch_loss += loss;
            report_loss += loss;
            if (report_every && report_total >= report_every) {
                std::cout << "hier_step epoch=" << epoch
                          << " step=" << global_step
                          << " train_loss=" << (report_loss / report_total)
                          << " train_accuracy="
                          << (100.0 * report_correct / report_total)
                          << "\n";
                report_total = report_correct = 0;
                report_loss = 0.0;
            }
        }
        if (report_total) {
            std::cout << "hier_step epoch=" << epoch
                      << " step=" << global_step
                      << " train_loss=" << (report_loss / report_total)
                      << " train_accuracy="
                      << (100.0 * report_correct / report_total)
                      << "\n";
        }
        const double elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        std::cout << "hier_epoch epoch=" << epoch
                  << " samples=" << epoch_total
                  << " train_loss=" << (epoch_loss / std::max<std::size_t>(1, epoch_total))
                  << " train_accuracy="
                  << (100.0 * epoch_correct / std::max<std::size_t>(1, epoch_total))
                  << " seconds=" << elapsed
                  << " lr=" << lr
                  << "\n";
        if (eval_every && epoch % eval_every == 0) {
            const bool last = epoch == epochs;
            if (!evaluate(epoch, last)) return 7;
            final_evaluated = last;
        }
    }
    if (!final_evaluated && !evaluate(epochs, true)) return 7;
    return 0;
}

int context_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal context-train CORPUS [MAX_LINES] [EPOCHS]"
                     " [REPORT_EVERY] [BUCKETS] [CONTEXT_BYTES] [LR] [EVAL_EVERY] [TRAIN_FRACTION] [backoff|backoffcopy|guestbackoff] [EXACT_BUCKETS] [fallback=N] [eval=PATH]\n"
                  << "Trains a raw context-indexed 16x16 class-memory readout.\n"
                  << "TRAIN_FRACTION <1 holds out a random evaluation split.\n"
                  << "backoff uses exact high-frequency 4-byte contexts plus a 3-byte fallback.\n"
                  << "backoffcopy routes unseen 3-byte contexts to a copy/unigram table.\n"
                  << "guestbackoff builds the exact/compact k=4 table and k=3 fallback route in the raw guest.\n"
                  << "eval=PATH uses a separate held-out corpus instead of a random line split.\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, epochs = 3, report_every = 10000;
    std::size_t buckets = 8192, context_bytes = 3, eval_every = 1;
    float base_lr = 0.5f, train_fraction = 1.0f;
    bool backoff_mode = false;
    bool copy_backoff = false;
    bool guest_backoff = false;
    std::size_t exact_limit_arg = 10500;
    std::size_t fallback_bytes = 3;
    std::string load_path;
    std::string save_path;
    std::string eval_path;
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) epochs = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) report_every = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 6) buckets = static_cast<std::size_t>(std::stoull(argv[6]));
        if (argc > 7) context_bytes = static_cast<std::size_t>(std::stoull(argv[7]));
        if (argc > 8) base_lr = std::stof(argv[8]);
        if (argc > 9) eval_every = static_cast<std::size_t>(std::stoull(argv[9]));
        if (argc > 10) train_fraction = std::stof(argv[10]);
        if (argc > 11) {
            const std::string route = argv[11];
            backoff_mode = route == "backoff" || route == "backoffcopy" ||
                route == "guestbackoff";
            copy_backoff = route == "backoffcopy";
            guest_backoff = route == "guestbackoff";
        }
        if (argc > 12) exact_limit_arg = static_cast<std::size_t>(std::stoull(argv[12]));
        for (int i = 13; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg.rfind("load=", 0) == 0) load_path = arg.substr(5);
            else if (arg.rfind("save=", 0) == 0) save_path = arg.substr(5);
            else if (arg.rfind("eval=", 0) == 0) eval_path = arg.substr(5);
            else if (arg.rfind("fallback=", 0) == 0) {
                fallback_bytes = static_cast<std::size_t>(std::stoull(arg.substr(9)));
            }
        }
    } catch (...) { std::cerr << "invalid numeric argument\n"; return 2; }
    if (buckets == 0 || buckets > 16384 || context_bytes == 0 || context_bytes > 8 ||
        fallback_bytes == 0 || fallback_bytes > 8 ||
        base_lr <= 0.0f || train_fraction <= 0.0f || train_fraction > 1.0f) {
        std::cerr << "buckets 1..16384, context bytes 1..8, positive LR,"
                     " train fraction in (0,1] required\n";
        return 2;
    }
    if (guest_backoff && (context_bytes != 4 || fallback_bytes != 3 ||
                          buckets < 2)) {
        std::cerr << "guestbackoff requires 4-byte contexts, a 3-byte fallback,"
                     " and at least 2 buckets\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    std::string data((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    std::vector<std::string_view> lines;
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        if (end == std::string::npos) {
            if (begin < data.size()) lines.emplace_back(data.data() + begin,
                                                        data.size() - begin);
            break;
        }
        lines.emplace_back(data.data() + begin, end - begin);
        begin = end + 1;
        if (max_lines && lines.size() >= max_lines) break;
    }
    const std::size_t train_line_count = lines.size();
    std::string eval_data;
    if (!eval_path.empty()) {
        std::ifstream eval_in(eval_path, std::ios::binary);
        if (!eval_in) { std::cerr << "cannot open eval corpus\n"; return 3; }
        eval_data.assign(std::istreambuf_iterator<char>(eval_in),
                         std::istreambuf_iterator<char>());
        std::size_t eval_begin = 0;
        while (eval_begin <= eval_data.size()) {
            const auto eval_end = eval_data.find('\n', eval_begin);
            if (eval_end == std::string::npos) {
                if (eval_begin < eval_data.size()) {
                    lines.emplace_back(eval_data.data() + eval_begin,
                                       eval_data.size() - eval_begin);
                }
                break;
            }
            lines.emplace_back(eval_data.data() + eval_begin,
                               eval_end - eval_begin);
            eval_begin = eval_end + 1;
        }
    }
        std::vector<std::string_view> usable;
    usable.reserve(lines.size());
    std::size_t train_usable_count = 0;
    for (std::size_t line_index = 0; line_index < lines.size(); ++line_index) {
        const auto line = lines[line_index];
        if (line.size() >= 9 && static_cast<std::uint8_t>(line[8]) < 255) {
            usable.push_back(line);
            if (line_index < train_line_count) ++train_usable_count;
        }
    }
    std::vector<std::uint32_t> context_buckets;
    std::vector<std::uint32_t> context_keys;
    std::vector<std::uint8_t> targets(usable.size());
    if (guest_backoff) {
        context_keys.resize(usable.size());
        for (std::size_t i = 0; i < usable.size(); ++i) {
            const auto line = usable[i];
            targets[i] = static_cast<std::uint8_t>(line[8]);
            context_keys[i] =
                (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[4])) << 24) |
                (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[5])) << 16) |
                (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[6])) << 8) |
                static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[7]));
        }
    } else if (backoff_mode) {
        context_buckets.resize(usable.size());
        for (std::size_t i = 0; i < usable.size(); ++i) {
            const auto line = usable[i];
            targets[i] = static_cast<std::uint8_t>(line[8]);
            std::uint32_t hash = 2166136261u;
            for (std::size_t j = 0; j < context_bytes; ++j) {
                const auto byte = static_cast<std::uint8_t>(line[8 - context_bytes + j]);
                hash = (hash ^ byte) * 16777619u;
            }
            context_buckets[i] = hash % static_cast<std::uint32_t>(buckets);
        }
    } else {
        context_buckets.resize(usable.size());
        for (std::size_t i = 0; i < usable.size(); ++i) {
            const auto line = usable[i];
            targets[i] = static_cast<std::uint8_t>(line[8]);
            std::uint32_t hash = 2166136261u;
            for (std::size_t j = 0; j < context_bytes; ++j) {
                const auto byte = static_cast<std::uint8_t>(line[8 - context_bytes + j]);
                hash = (hash ^ byte) * 16777619u;
            }
            context_buckets[i] = hash % static_cast<std::uint32_t>(buckets);
        }
    }
    std::vector<std::size_t> all_indices(usable.size());
    for (std::size_t i = 0; i < all_indices.size(); ++i) all_indices[i] = i;
    std::vector<std::size_t> train_indices;
    std::vector<std::size_t> eval_indices;
    if (!eval_path.empty()) {
        const std::size_t train_count = std::min<std::size_t>(
            train_usable_count, all_indices.size());
        train_indices.assign(all_indices.begin(),
                             all_indices.begin() + static_cast<std::ptrdiff_t>(train_count));
        eval_indices.assign(all_indices.begin() + static_cast<std::ptrdiff_t>(train_count),
                            all_indices.end());
    } else if (train_fraction >= 1.0f) {
        train_indices = all_indices;
        eval_indices = all_indices;
    } else {
        std::mt19937 split_rng(99);
        std::shuffle(all_indices.begin(), all_indices.end(), split_rng);
        const std::size_t split = static_cast<std::size_t>(
            train_fraction * static_cast<float>(all_indices.size()));
        train_indices.assign(all_indices.begin(), all_indices.begin() + split);
        eval_indices.assign(all_indices.begin() + split, all_indices.end());
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    const auto reset_started = std::chrono::steady_clock::now();
    if (!load_path.empty()) {
        if (!vm.load_context_readout(load_path, buckets)) {
            std::cerr << "cannot load context readout: " << vm.error() << "\n";
            return 7;
        }
    } else if (!vm.reset_context_readout(buckets)) {
        std::cerr << "cannot reset context readout: " << vm.error() << "\n";
        return 7;
    }
    if (guest_backoff) {
        const auto build_started = std::chrono::steady_clock::now();
        if (!vm.reset_context_backoff()) {
            std::cerr << "cannot reset guest context backoff: " << vm.error() << "\n";
            return 7;
        }
        std::vector<std::uint32_t> build_keys;
        build_keys.reserve(train_indices.size());
        for (const std::size_t sample : train_indices) {
            build_keys.push_back(context_keys[sample]);
        }
        std::size_t inserted_keys = 0;
        if (!vm.context_backoff_build_batch(build_keys.data(), build_keys.size(),
                                            inserted_keys)) {
            std::cerr << "guest context backoff batch build failed: "
                      << vm.error() << "\n";
            return 7;
        }
        ContextBackoffSelection selection;
        if (!vm.context_backoff_select(buckets, exact_limit_arg, selection)) {
            std::cerr << "guest context backoff select failed: "
                      << vm.error() << "\n";
            return 7;
        }
        std::cout << "context_guest_backoff exact=" << selection.exact_count
                  << " fallback=" << selection.fallback
                  << " threshold=" << selection.threshold
                  << " unique=" << selection.unique
                  << " inserted=" << inserted_keys
                  << " build_seconds="
                  << std::chrono::duration<double>(
                         std::chrono::steady_clock::now() - build_started).count()
                  << "\n";
    }
    std::cout << "context_tables buckets=" << buckets
              << " train_samples=" << train_indices.size()
              << " eval_samples=" << eval_indices.size()
              << " reset_seconds="
              << std::chrono::duration<double>(
                     std::chrono::steady_clock::now() - reset_started).count()
              << "\n";
    const auto evaluate = [&](std::size_t epoch, bool final) -> bool {
        const auto started = std::chrono::steady_clock::now();
        std::size_t total = 0, correct_count = 0;
        double loss_sum = 0.0;
        for (const std::size_t sample : eval_indices) {
            bool correct = false;
            float loss = 0.0f;
            std::uint8_t ph = 0, pl = 0;
            bool ok = false;
            if (guest_backoff) {
                ContextBackoffStep step;
                ok = vm.readout_context_backoff(targets[sample], 0.0f,
                                                context_keys[sample], buckets,
                                                step);
                correct = step.correct;
                loss = step.loss;
                ph = step.predicted_high;
                pl = step.predicted_low;
            } else {
                ok = vm.readout_context(targets[sample], 0.0f,
                                        context_buckets[sample], buckets,
                                        correct, loss, ph, pl);
            }
            if (!ok) {
                std::cerr << "context eval failed: " << vm.error() << "\n";
                return false;
            }
            ++total;
            correct_count += correct ? 1u : 0u;
            loss_sum += loss;
        }
        const double seconds = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        const auto print = [&](const char* tag) {
            std::cout << tag << " samples=" << total
                      << " loss=" << (loss_sum / std::max<std::size_t>(1, total))
                      << " accuracy="
                      << (100.0 * correct_count / std::max<std::size_t>(1, total))
                      << " seconds=" << seconds;
            if (!final) std::cout << " epoch=" << epoch;
            std::cout << "\n";
        };
        print(final ? "ctx_full_eval" : "ctx_eval");
        return true;
    };

    std::vector<std::size_t> order = train_indices;
    std::mt19937 rng(1);
    std::size_t global_step = 0;
    bool final_evaluated = false;
    const auto started = std::chrono::steady_clock::now();
    for (std::size_t epoch = 1; epoch <= epochs; ++epoch) {
        std::shuffle(order.begin(), order.end(), rng);
        std::size_t epoch_total = 0, epoch_correct = 0;
        std::size_t report_total = 0, report_correct = 0;
        double epoch_loss = 0.0, report_loss = 0.0;
        for (std::size_t position = 0; position < order.size(); ++position) {
            const std::size_t sample = order[position];
            bool correct = false;
            float loss = 0.0f;
            std::uint8_t ph = 0, pl = 0;
            bool ok = false;
            if (guest_backoff) {
                ContextBackoffStep step;
                ok = vm.readout_context_backoff(targets[sample], base_lr,
                                                context_keys[sample], buckets,
                                                step);
                correct = step.correct;
                loss = step.loss;
                ph = step.predicted_high;
                pl = step.predicted_low;
            } else {
                ok = vm.readout_context(targets[sample], base_lr,
                                        context_buckets[sample], buckets,
                                        correct, loss, ph, pl);
            }
            if (!ok) {
                std::cerr << "context step failed: " << vm.error() << "\n";
                return 7;
            }
            ++global_step;
            ++epoch_total;
            ++report_total;
            epoch_correct += correct ? 1u : 0u;
            report_correct += correct ? 1u : 0u;
            epoch_loss += loss;
            report_loss += loss;
            if (report_every && report_total >= report_every) {
                std::cout << "ctx_step epoch=" << epoch
                          << " step=" << global_step
                          << " train_loss=" << (report_loss / report_total)
                          << " train_accuracy="
                          << (100.0 * report_correct / report_total)
                          << "\n";
                report_total = report_correct = 0;
                report_loss = 0.0;
            }
        }
        if (report_total) {
            std::cout << "ctx_step epoch=" << epoch
                      << " step=" << global_step
                      << " train_loss=" << (report_loss / report_total)
                      << " train_accuracy="
                      << (100.0 * report_correct / report_total)
                      << "\n";
        }
        const double elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - started).count();
        std::cout << "ctx_epoch epoch=" << epoch
                  << " samples=" << epoch_total
                  << " train_loss=" << (epoch_loss / std::max<std::size_t>(1, epoch_total))
                  << " train_accuracy="
                  << (100.0 * epoch_correct / std::max<std::size_t>(1, epoch_total))
                  << " seconds=" << elapsed
                  << " lr=" << base_lr
                  << "\n";
        if (eval_every && epoch % eval_every == 0) {
            const bool last = epoch == epochs;
            if (!evaluate(epoch, last)) return 7;
            final_evaluated = last;
        }
    }
    if (!final_evaluated && !evaluate(epochs, true)) return 7;
    if (!save_path.empty() && !vm.save_context_readout(save_path, buckets)) {
        std::cerr << "cannot save context readout: " << vm.error() << "\n";
        return 7;
    }
    return 0;
}

int context_hash_check_cli(int, char**) {
    std::cerr << "context-hash-check is available in the hash worktree; "
                 "this integration build uses the guest-backoff trainer.\n";
    return 2;
}


int phase_ingest_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal phase-ingest CORPUS [MAX_LINES] [WINDOW]"
                     " [DIM] [MAX_WINDOWS] [OUTPUT_PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, window = 8, dim = 128, max_windows = 0;
    std::string output_prefix = "state/phase_vectors";
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) window = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) dim = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 6) max_windows = static_cast<std::size_t>(std::stoull(argv[6]));
        if (argc > 7) output_prefix = argv[7];
    } catch (...) { std::cerr << "invalid numeric argument\n"; return 2; }
    if (window == 0 || window > 8 || dim == 0 || dim > 128) {
        std::cerr << "window 1..8 and dim 1..128 required\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    std::string data((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    std::vector<std::string_view> lines;
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        if (end == std::string::npos) {
            if (begin < data.size()) lines.emplace_back(data.data() + begin,
                                                        data.size() - begin);
            break;
        }
        lines.emplace_back(data.data() + begin, end - begin);
        begin = end + 1;
        if (max_lines && lines.size() >= max_lines) break;
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    std::error_code mkdir_error;
    std::filesystem::create_directories("state", mkdir_error);
    if (!vm.phase_table_init()) {
        std::cerr << "phase table init failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream out(output_prefix + ".bin", std::ios::binary);
    if (!out) { std::cerr << "cannot open phase vector output\n"; return 3; }
    std::array<std::size_t, 16> shard_counts{};
    std::size_t encoded = 0;
    constexpr std::size_t kPipelineSamples = 1024;
    std::vector<std::vector<std::int32_t>> samples;
    std::vector<std::uint8_t> batch_bytes;
    std::size_t batch_windows = 0;
    constexpr std::size_t kBatchWindows = 1024;
    const auto flush_batch = [&]() -> bool {
        if (batch_windows == 0) return true;
        std::vector<std::int32_t> vectors;
        if (!vm.phase_encode_batch(batch_bytes.data(), batch_windows,
                                   window, dim, vectors)) {
            std::cerr << "phase batch failed: " << vm.error() << "\n";
            return false;
        }
        out.write(reinterpret_cast<const char*>(vectors.data()),
                  static_cast<std::streamsize>(
                      vectors.size() * sizeof(std::int32_t)));
        const std::size_t stride = dim * 2;
        for (std::size_t w = 0; w < batch_windows; ++w) {
            std::int64_t sum = 0;
            for (std::size_t d = 0; d < dim; ++d) {
                sum += vectors[w * stride + d * 2];
            }
            ++shard_counts[static_cast<std::size_t>(sum) & 15u];
            if (samples.size() < kPipelineSamples) {
                samples.emplace_back(vectors.begin() + w * stride,
                                     vectors.begin() + (w + 1) * stride);
            }
        }
        encoded += batch_windows;
        batch_bytes.clear();
        batch_windows = 0;
        return true;
    };
    for (auto line : lines) {
        while (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty()) continue;
        if (max_windows && encoded + batch_windows >= max_windows) break;
        const auto bytes = make_window(line, window);
        batch_bytes.insert(batch_bytes.end(), bytes.begin(), bytes.end());
        ++batch_windows;
        if (batch_windows == kBatchWindows && !flush_batch()) return 7;
    }
    if (!flush_batch()) return 7;

    // Derive the raw PQ, sparse k-NN and spectral layers from the encoded
    // phase vectors. This is a first-stage pipeline: the codebook is trained
    // in-guest from the first pipeline window, and the sparse bank is the first
    // 256 windows. All quantization and graph arithmetic remains guest-side.
    std::size_t pq_codewords = 0;
    std::size_t knn_bank = 0;
    std::size_t pipeline_dim = 0;
    std::size_t matrix_updates = 0;
    std::size_t codebook_words = 0;
    std::size_t residual_values = 0;
    std::vector<std::int32_t> matrix_cells;
    std::int32_t probe_head = -1;
    std::int32_t probe_score = 0;
    std::uint16_t field_hot_heads = 0;
    std::uint16_t field_hot_triads = 0;
    bool field_accept = false;
    bool hodge_ok = false;
    double hodge_divergence_l1 = 0.0;
    double hodge_curl_l1 = 0.0;
    if (!samples.empty()) {
        pipeline_dim = std::min<std::size_t>(dim * 2, 256);
        pq_codewords = std::min<std::size_t>(samples.size(), 32);
        std::vector<std::int32_t> sample_bank;
        sample_bank.reserve(samples.size() * pipeline_dim);
        for (const auto& sample : samples)
            sample_bank.insert(sample_bank.end(), sample.begin(),
                               sample.begin() + pipeline_dim);
        std::vector<std::int32_t> codebook;
        constexpr std::size_t kPqIterations = 1;
        if (!vm.pq_train(sample_bank, samples.size(), pipeline_dim,
                         pq_codewords, kPqIterations, codebook)) {
            std::cerr << "phase PQ training failed: " << vm.error() << "\n";
            return 7;
        }
        {
            codebook_words = codebook.size();
            std::ofstream book(output_prefix + ".codebook.bin",
                               std::ios::binary);
            if (!book) {
                std::cerr << "cannot open phase codebook output\n";
                return 3;
            }
            book.write(reinterpret_cast<const char*>(codebook.data()),
                       static_cast<std::streamsize>(
                           codebook.size() * sizeof(codebook[0])));
        }
        std::vector<std::uint32_t> pq_codes;
        std::vector<std::int32_t> pq_distances;
        pq_codes.reserve(samples.size());
        pq_distances.reserve(samples.size());
        for (const auto& sample : samples) {
            std::vector<std::int32_t> query(sample.begin(),
                                             sample.begin() + pipeline_dim);
            std::uint32_t code = 0;
            std::int32_t distance = 0;
            if (!vm.pq_encode(query, codebook, pq_codewords, pipeline_dim,
                              code, distance)) {
                std::cerr << "phase PQ failed: " << vm.error() << "\n";
                return 7;
            }
            pq_codes.push_back(code);
            pq_distances.push_back(distance);
        }
        {
            std::ofstream codes(output_prefix + ".codes.bin", std::ios::binary);
            if (!codes) {
                std::cerr << "cannot open phase codes output\n";
                return 3;
            }
            for (std::size_t i = 0; i < pq_codes.size(); ++i) {
                codes.write(reinterpret_cast<const char*>(&pq_codes[i]),
                            sizeof(pq_codes[i]));
                codes.write(reinterpret_cast<const char*>(&pq_distances[i]),
                            sizeof(pq_distances[i]));
            }
        }
        std::vector<std::int32_t> residuals;
        if (!vm.pq_residuals(sample_bank, pq_codes, samples.size(),
                             pipeline_dim, codebook, residuals)) {
            std::cerr << "phase PQ residual failed: " << vm.error() << "\n";
            return 7;
        }
        {
            std::ofstream residual_file(output_prefix + ".residuals.bin",
                                        std::ios::binary);
            if (!residual_file) {
                std::cerr << "cannot open phase residual output\n";
                return 3;
            }
            residual_file.write(
                reinterpret_cast<const char*>(residuals.data()),
                static_cast<std::streamsize>(residuals.size() *
                                              sizeof(residuals[0])));
            residual_values = residuals.size();
        }

        // The C(256,2) observer is updated only in the guest. Consecutive
        // vector codes become a pair with one Q16 support increment.
        if (!vm.vector_matrix_reset()) {
            std::cerr << "vector matrix reset failed: " << vm.error() << "\n";
            return 7;
        }
        for (std::size_t i = 1; i < pq_codes.size(); ++i) {
            const std::uint8_t a = static_cast<std::uint8_t>(pq_codes[i - 1]);
            const std::uint8_t b = static_cast<std::uint8_t>(pq_codes[i]);
            if (a == b) continue;
            std::uint32_t pair = 0;
            std::int32_t value = 0;
            if (!vm.vector_matrix_accumulate(a, b, 65536, pair, value)) {
                std::cerr << "vector matrix update failed: " << vm.error() << "\n";
                return 7;
            }
            ++matrix_updates;
        }
        if (!vm.read_vector_matrix(matrix_cells)) {
            std::cerr << "vector matrix read failed: " << vm.error() << "\n";
            return 7;
        }
        {
            std::ofstream matrix(output_prefix + ".matrix.bin",
                                 std::ios::binary);
            if (!matrix) {
                std::cerr << "cannot open vector matrix output\n";
                return 3;
            }
            matrix.write(reinterpret_cast<const char*>(matrix_cells.data()),
                         static_cast<std::streamsize>(
                             matrix_cells.size() * sizeof(matrix_cells[0])));
        }
        if (!pq_codes.empty()) {
            if (!vm.vector_matrix_probe(
                    static_cast<std::uint8_t>(pq_codes.front()), 1,
                    probe_head, probe_score)) {
                std::cerr << "vector matrix probe failed: " << vm.error() << "\n";
                return 7;
            }
        }

        // Matrix -> 255 head credits -> existing raw hot-trihead mapping and
        // 43/85 field gate. No host score aggregation is used.
        std::vector<std::int32_t> matrix_credits;
        if (!vm.vector_matrix_credits(matrix_credits)) {
            std::cerr << "vector matrix credits failed: " << vm.error() << "\n";
            return 7;
        }
        std::array<std::int32_t, kTriadMemberCount> hot_credits{};
        std::copy(matrix_credits.begin(), matrix_credits.end(),
                  hot_credits.begin());
        HotTriheadResult hot_result;
        if (!vm.hot_triheads(hot_credits, 0, hot_result)) {
            std::cerr << "vector hot triheads failed: " << vm.error() << "\n";
            return 7;
        }
        field_hot_heads = hot_result.hot_heads;
        field_hot_triads = hot_result.hot_triads;
        field_accept = hot_result.field_hot;

        // Global 256-head Hodge over the Q16 vector-code matrix. The first 16
        // mapped triads are admitted as oriented faces.
        if (matrix_cells.size() == 32640) {
            std::vector<std::array<std::uint32_t, 3>> faces;
            const std::size_t face_count =
                std::min<std::size_t>(16, hot_result.members.size() / 3);
            for (std::size_t f = 0; f < face_count; ++f) {
                faces.push_back({hot_result.members[f * 3],
                                 hot_result.members[f * 3 + 1],
                                 hot_result.members[f * 3 + 2]});
            }
            std::array<float, 256> divergence{};
            std::array<float, 16> curl{};
            if (!vm.global_hodge_q16(matrix_cells, faces, divergence, curl)) {
                std::cerr << "global hodge failed: " << vm.error() << "\n";
                return 7;
            }
            hodge_ok = true;
            for (float value : divergence)
                hodge_divergence_l1 += std::fabs(value);
            for (float value : curl)
                hodge_curl_l1 += std::fabs(value);
        }
        {
            std::ofstream triads(output_prefix + ".triads.bin",
                                 std::ios::binary);
            if (!triads) {
                std::cerr << "cannot open vector triads output\n";
                return 3;
            }
            triads.write(reinterpret_cast<const char*>(hot_result.members.data()),
                         static_cast<std::streamsize>(hot_result.members.size()));
        }

        knn_bank = std::min<std::size_t>(samples.size(), 256);
        std::vector<std::int32_t> bank;
        bank.reserve(knn_bank * pipeline_dim);
        for (std::size_t i = 0; i < knn_bank; ++i)
            bank.insert(bank.end(), samples[i].begin(),
                        samples[i].begin() + pipeline_dim);
        std::ofstream neighbors(output_prefix + ".knn.bin", std::ios::binary);
        if (!neighbors) {
            std::cerr << "cannot open phase kNN output\n";
            return 3;
        }
        for (const auto& sample : samples) {
            std::vector<std::int32_t> query(sample.begin(),
                                             sample.begin() + pipeline_dim);
            std::vector<std::uint32_t> indices;
            std::vector<std::int32_t> scores;
            if (!vm.sparse_knn(query, bank, knn_bank, pipeline_dim, 1,
                               indices, scores)) {
                std::cerr << "phase kNN failed: " << vm.error() << "\n";
                return 7;
            }
            neighbors.write(reinterpret_cast<const char*>(indices.data()),
                            sizeof(indices[0]));
            neighbors.write(reinterpret_cast<const char*>(scores.data()),
                            sizeof(scores[0]));
        }

        std::array<std::int32_t, 64> adjacency{};
        for (std::size_t i = 0; i + 1 < std::min<std::size_t>(pq_codes.size(), 8);
             ++i) {
            const std::size_t a = pq_codes[i] & 7u;
            const std::size_t b = pq_codes[i + 1] & 7u;
            adjacency[a * 8 + b] = 65536;
        }
        std::array<std::int32_t, 8> spectral_in{}, spectral_out{};
        for (auto& value : spectral_in) value = 65536;
        if (!vm.spectral_iter(adjacency, spectral_in, spectral_out)) {
            std::cerr << "phase spectral iteration failed: " << vm.error() << "\n";
            return 7;
        }
        {
            std::ofstream spectral(output_prefix + ".spectral.bin",
                                   std::ios::binary);
            if (!spectral) {
                std::cerr << "cannot open phase spectral output\n";
                return 3;
            }
            spectral.write(reinterpret_cast<const char*>(spectral_out.data()),
                           sizeof(spectral_out));
        }
    }

    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.phase-vectors/1\",\n"
                 << "  \"samples\": " << encoded << ",\n"
                 << "  \"dim\": " << dim << ",\n"
                 << "  \"window\": " << window << ",\n"
                 << "  \"pipeline\": {\"samples\": " << samples.size()
                 << ", \"pq_codewords\": " << pq_codewords
                 << ", \"pq_iterations\": 1"
                 << ", \"codebook_words\": " << codebook_words
                 << ", \"residual_words\": " << residual_values
                 << ", \"knn_bank\": " << knn_bank
                 << ", \"dim\": " << pipeline_dim
                 << ", \"matrix_updates\": " << matrix_updates
                 << ", \"matrix_cells\": " << matrix_cells.size()
                 << ", \"probe_head\": " << probe_head
                 << ", \"probe_score\": " << probe_score
                 << ", \"hot_heads\": " << field_hot_heads
                 << ", \"hot_triads\": " << field_hot_triads
                 << ", \"field_hot\": " << (field_accept ? "true" : "false")
                 << ", \"hodge_ok\": " << (hodge_ok ? "true" : "false")
                 << ", \"hodge_divergence_l1\": " << hodge_divergence_l1
                 << ", \"hodge_curl_l1\": " << hodge_curl_l1
                 << "},\n"
                 << "  \"shards\": [";
        for (std::size_t i = 0; i < shard_counts.size(); ++i) {
            if (i) manifest << ",";
            manifest << shard_counts[i];
        }
        manifest << "]\n}\n";
    }
    std::cout << "phase_ingest samples=" << encoded << " dim=" << dim
              << " window=" << window << " output=" << output_prefix << ".bin\n";
    return 0;
}


int phase_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal phase-train CORPUS [MAX_LINES]"
                     " [WINDOW] [DIM] [MAX_WINDOWS] [OUTPUT_PREFIX] [eval=PATH]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, window = 8, dim = 128, max_windows = 0;
    std::string output_prefix = "state/phase_train";
    std::string eval_path;
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) window = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) dim = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 6) max_windows = static_cast<std::size_t>(std::stoull(argv[6]));
        if (argc > 7) output_prefix = argv[7];
        if (argc > 8) {
            const std::string eval_arg = argv[8];
            eval_path = eval_arg.rfind("eval=", 0) == 0
                ? eval_arg.substr(5) : eval_arg;
        }
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    if (window == 0 || window > 8 || dim == 0 || dim > 128) {
        std::cerr << "window 1..8 and dim 1..128 required\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    const std::string data((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    std::vector<std::vector<std::uint8_t>> windows;
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        std::string_view line;
        if (end == std::string::npos) {
            if (begin >= data.size()) break;
            line = std::string_view(data.data() + begin, data.size() - begin);
            begin = data.size() + 1;
        } else {
            line = std::string_view(data.data() + begin, end - begin);
            begin = end + 1;
        }
        while (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty()) continue;
        if (max_windows && windows.size() >= max_windows) break;
        windows.push_back(make_window(line, window));
        if (max_lines && windows.size() >= max_lines) break;
    }
    if (windows.size() < 4 && eval_path.empty()) {
        std::cerr << "phase-train needs at least four windows\n";
        return 3;
    }
    std::vector<std::vector<std::uint8_t>> eval_windows;
    std::size_t eval_count = 0;
    std::size_t train_count = 0;
    if (!eval_path.empty()) {
        std::ifstream eval_in(eval_path, std::ios::binary);
        if (!eval_in) {
            std::cerr << "cannot open eval corpus\n";
            return 3;
        }
        const std::string eval_data((std::istreambuf_iterator<char>(eval_in)),
                                    std::istreambuf_iterator<char>());
        std::size_t eval_begin = 0;
        while (eval_begin <= eval_data.size()) {
            const auto end = eval_data.find('\n', eval_begin);
            std::string_view line;
            if (end == std::string::npos) {
                if (eval_begin >= eval_data.size()) break;
                line = std::string_view(eval_data.data() + eval_begin,
                                        eval_data.size() - eval_begin);
                eval_begin = eval_data.size() + 1;
            } else {
                line = std::string_view(eval_data.data() + eval_begin,
                                        end - eval_begin);
                eval_begin = end + 1;
            }
            while (!line.empty() && line.back() == '\r')
                line.remove_suffix(1);
            if (line.empty()) continue;
            if (max_windows && eval_windows.size() >= max_windows) break;
            eval_windows.push_back(make_window(line, window));
            if (max_lines && eval_windows.size() >= max_lines) break;
        }
        train_count = windows.size();
        eval_count = eval_windows.size();
    } else {
        eval_count = std::max<std::size_t>(1, windows.size() / 5);
        train_count = windows.size() - eval_count;
    }
    if (train_count < 2 || eval_count < 1) {
        std::cerr << "phase-train train/eval split too small\n";
        return 3;
    }

    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.phase_table_init()) {
        std::cerr << "phase table init failed: " << vm.error() << "\n";
        return 7;
    }
    const std::size_t pipeline_dim = std::min<std::size_t>(dim * 2, 256);
    const auto encode_windows = [&](const std::vector<std::vector<std::uint8_t>>& source,
                                    std::vector<std::vector<std::int32_t>>& dest) {
        dest.clear();
        dest.reserve(source.size());
        constexpr std::size_t kEncodeBatch = 1024;
        for (std::size_t start = 0; start < source.size();
             start += kEncodeBatch) {
            const std::size_t count =
                std::min(kEncodeBatch, source.size() - start);
            std::vector<std::uint8_t> bytes;
            bytes.reserve(count * window);
            for (std::size_t i = 0; i < count; ++i)
                bytes.insert(bytes.end(), source[start + i].begin(),
                             source[start + i].end());
            std::vector<std::int32_t> encoded;
            if (!vm.phase_encode_batch(bytes.data(), count, window, dim,
                                       encoded)) {
                std::cerr << "phase-train encode failed: " << vm.error() << "\n";
                return false;
            }
            for (std::size_t i = 0; i < count; ++i)
                dest.emplace_back(encoded.begin() + i * pipeline_dim,
                                  encoded.begin() + (i + 1) * pipeline_dim);
        }
        return true;
    };
    std::vector<std::vector<std::int32_t>> vectors;
    std::vector<std::vector<std::int32_t>> eval_vectors;
    if (!encode_windows(windows, vectors)) return 7;
    if (!eval_path.empty()) {
        if (!encode_windows(eval_windows, eval_vectors)) return 7;
    } else {
        eval_vectors.assign(vectors.begin() + train_count, vectors.end());
        vectors.resize(train_count);
    }

    const std::size_t codewords = std::min<std::size_t>(train_count, 160);
    const std::size_t init_count = std::min<std::size_t>(train_count, 256);
    std::vector<std::int32_t> train_bank;
    train_bank.reserve(init_count * pipeline_dim);
    for (std::size_t i = 0; i < init_count; ++i)
        train_bank.insert(train_bank.end(), vectors[i].begin(),
                          vectors[i].end());
    std::vector<std::int32_t> codebook;
    bool resumed = false;
    {
        std::ifstream checkpoint(output_prefix + ".ckpt", std::ios::binary);
        if (checkpoint) {
            char magic[8] = {};
            std::uint32_t codebook_words = 0, matrix_words = 0;
            std::uint32_t codebook_digest = 0, matrix_digest = 0;
            checkpoint.read(magic, sizeof(magic));
            checkpoint.read(reinterpret_cast<char*>(&codebook_words), 4);
            checkpoint.read(reinterpret_cast<char*>(&matrix_words), 4);
            checkpoint.read(reinterpret_cast<char*>(&codebook_digest), 4);
            checkpoint.read(reinterpret_cast<char*>(&matrix_digest), 4);
            if (checkpoint && std::string(magic, 8) == "NANCKPT1" &&
                codebook_words == codewords * pipeline_dim &&
                matrix_words == 32640) {
                std::vector<std::int32_t> saved_codebook(codebook_words);
                std::vector<std::int32_t> saved_matrix(matrix_words);
                checkpoint.read(reinterpret_cast<char*>(saved_codebook.data()),
                                static_cast<std::streamsize>(
                                    saved_codebook.size() * sizeof(saved_codebook[0])));
                checkpoint.read(reinterpret_cast<char*>(saved_matrix.data()),
                                static_cast<std::streamsize>(
                                    saved_matrix.size() * sizeof(saved_matrix[0])));
                std::uint32_t check_codebook = 0, check_matrix = 0;
                if (checkpoint && vm.raw_hash(saved_codebook, check_codebook) &&
                    vm.raw_hash(saved_matrix, check_matrix) &&
                    check_codebook == codebook_digest &&
                    check_matrix == matrix_digest &&
                    vm.load_vector_matrix(saved_matrix)) {
                    codebook = std::move(saved_codebook);
                    resumed = true;
                }
            }
        }
    }
    if (!resumed) {
        if (!vm.pq_train(train_bank, init_count, pipeline_dim, codewords, 1,
                         codebook)) {
            std::cerr << "phase-train codebook init failed: " << vm.error() << "\n";
            return 7;
        }
        if (!vm.vector_matrix_reset()) {
            std::cerr << "phase-train matrix reset failed: " << vm.error() << "\n";
            return 7;
        }
    }

    std::error_code mkdir_error;
    std::filesystem::create_directories("state", mkdir_error);
    std::ofstream metrics(output_prefix + ".metrics.jsonl", std::ios::binary);
    if (!metrics) {
        std::cerr << "cannot open phase metrics output\n";
        return 3;
    }
    std::uint32_t previous_code = 0;
    bool have_previous_code = false;
    std::size_t processed = 0;
    std::uint64_t train_distance = 0;
    std::size_t train_distance_count = 0;
    std::uint16_t last_hot_heads = 0;
    std::uint16_t last_hot_triads = 0;
    bool last_field = false;
    double best_eval_l1 = 1e300;
    std::size_t best_step = 0;
    std::vector<std::int32_t> best_codebook;
    std::vector<std::int32_t> best_matrix;
    std::uint16_t best_hot_heads = 0;
    std::uint16_t best_hot_triads = 0;
    bool best_field = false;

    constexpr std::size_t kTrainProbeAnchors = 256;
    const std::size_t train_probe_count =
        std::min<std::size_t>(train_count, kTrainProbeAnchors);
    std::vector<std::int32_t> train_probe_bank;
    train_probe_bank.reserve(train_probe_count * pipeline_dim);
    for (std::size_t a = 0; a < train_probe_count; ++a) {
        const std::size_t index =
            (a * train_count) / std::max<std::size_t>(1, train_probe_count);
        train_probe_bank.insert(train_probe_bank.end(), vectors[index].begin(),
                                vectors[index].end());
    }

    std::size_t rollbacks = 0;
    const auto emit_metrics = [&](std::size_t step, bool final,
                                  double& eval_value) -> bool {
        std::uint64_t eval_distance = 0;
        std::size_t probe_hits = 0;
        std::uint64_t probe_score_sum = 0;
        std::size_t probe_count = 0;
        std::uint32_t prev_eval_code = 0;
        bool have_prev_eval = false;
        std::uint64_t eval_magnitude = 0;
        std::size_t pair_top1 = 0;
        std::vector<std::int32_t> eval_bank;
        std::vector<std::uint32_t> eval_codes;
        eval_bank.reserve(eval_vectors.size() * pipeline_dim);
        eval_codes.reserve(eval_vectors.size());
        for (const auto& eval_sample : eval_vectors) {
            std::uint32_t code = 0;
            std::int32_t distance = 0;
            if (!vm.pq_encode(eval_sample, codebook, codewords, pipeline_dim,
                              code, distance)) {
                std::cerr << "phase-train eval encode failed: " << vm.error() << "\n";
                return false;
            }
            eval_distance += static_cast<std::uint64_t>(distance);
            for (std::int32_t value : eval_sample)
                eval_magnitude += static_cast<std::uint64_t>(
                    value < 0 ? -static_cast<std::int64_t>(value) : value);
            eval_bank.insert(eval_bank.end(), eval_sample.begin(),
                             eval_sample.end());
            eval_codes.push_back(code);
            if (have_prev_eval && prev_eval_code != code) {
                std::int32_t best_head = -1;
                std::int32_t best_score = 0;
                if (!vm.vector_matrix_probe(
                        static_cast<std::uint8_t>(prev_eval_code), 1,
                        best_head, best_score)) {
                    std::cerr << "phase-train probe failed: " << vm.error() << "\n";
                    return false;
                }
                ++probe_count;
                if (best_head >= 0 && best_score > 0) {
                    ++probe_hits;
                    probe_score_sum += static_cast<std::uint64_t>(best_score);
                }
                if (best_head == static_cast<std::int32_t>(code)) ++pair_top1;
            }
            prev_eval_code = code;
            have_prev_eval = true;
        }
        std::vector<std::int32_t> eval_residuals;
        if (!vm.pq_residuals(eval_bank, eval_codes, eval_vectors.size(),
                             pipeline_dim, codebook, eval_residuals)) {
            std::cerr << "phase-train eval residual failed: " << vm.error() << "\n";
            return false;
        }
        std::size_t leaf_verified = 0;
        std::uint64_t leaf_error_sum = 0;
        for (std::size_t i = 0; i < eval_vectors.size(); ++i) {
            std::vector<std::int32_t> residual(
                eval_residuals.begin() + i * pipeline_dim,
                eval_residuals.begin() + (i + 1) * pipeline_dim);
            bool accepted = false;
            std::int32_t error = 0;
            if (!vm.leaf_verify(eval_vectors[i], codebook, residual,
                                eval_codes[i], pipeline_dim, 0, accepted,
                                error)) {
                std::cerr << "phase-train leaf verify failed: " << vm.error() << "\n";
                return false;
            }
            if (accepted) ++leaf_verified;
            leaf_error_sum += static_cast<std::uint64_t>(error);
        }
        const double leaf_rate = eval_vectors.empty()
            ? 0.0
            : static_cast<double>(leaf_verified) /
                  static_cast<double>(eval_vectors.size());
        const double leaf_mean_error = eval_vectors.empty()
            ? 0.0
            : static_cast<double>(leaf_error_sum) /
                  static_cast<double>(eval_vectors.size());

        std::vector<std::int32_t> matrix_cells;
        if (!vm.read_vector_matrix(matrix_cells)) return false;
        std::size_t matrix_nonzero = 0;
        for (std::int32_t cell : matrix_cells) matrix_nonzero += cell != 0;
        std::vector<std::int32_t> credits;
        if (!vm.vector_matrix_credits(credits)) return false;
        std::array<std::int32_t, kTriadMemberCount> hot_credits{};
        std::copy(credits.begin(), credits.end(), hot_credits.begin());
        HotTriheadResult hot;
        if (!vm.hot_triheads(hot_credits, 0, hot)) return false;
        last_hot_heads = hot.hot_heads;
        last_hot_triads = hot.hot_triads;
        last_field = hot.field_hot;
        std::uint64_t train_current_distance = 0;
        for (std::size_t a = 0; a < train_probe_count; ++a) {
            std::vector<std::int32_t> probe(
                train_probe_bank.begin() + a * pipeline_dim,
                train_probe_bank.begin() + (a + 1) * pipeline_dim);
            std::uint32_t probe_code = 0;
            std::int32_t probe_distance = 0;
            if (!vm.pq_encode(probe, codebook, codewords, pipeline_dim,
                              probe_code, probe_distance)) {
                std::cerr << "phase-train current probe failed: "
                          << vm.error() << "\n";
                return false;
            }
            train_current_distance +=
                static_cast<std::uint64_t>(probe_distance);
        }
        const double train_current_mean = train_probe_count
            ? static_cast<double>(train_current_distance) /
                  static_cast<double>(train_probe_count)
            : 0.0;
        const double train_mean = train_distance_count
            ? static_cast<double>(train_distance) /
                  static_cast<double>(train_distance_count)
            : 0.0;
        const double eval_mean = eval_count
            ? static_cast<double>(eval_distance) / static_cast<double>(eval_count)
            : 0.0;
        eval_value = eval_mean;
        const double eval_per_dim = pipeline_dim
            ? eval_mean / static_cast<double>(pipeline_dim) : 0.0;
        const double eval_relative = eval_magnitude
            ? eval_mean / (static_cast<double>(eval_magnitude) /
                           static_cast<double>(std::max<std::size_t>(1, eval_count)))
            : 0.0;
        const double hit_rate = probe_count
            ? static_cast<double>(probe_hits) / static_cast<double>(probe_count)
            : 0.0;
        const double pair_top1_rate = probe_count
            ? static_cast<double>(pair_top1) / static_cast<double>(probe_count)
            : 0.0;
        const double score_mean = probe_hits
            ? static_cast<double>(probe_score_sum) /
                  static_cast<double>(probe_hits)
            : 0.0;
        const bool better_eval = eval_mean < best_eval_l1 - 1e-9;
        const bool tie_better_field =
            std::abs(eval_mean - best_eval_l1) <= 1e-9 &&
            hot.hot_triads > best_hot_triads;
        if (eval_count > 0 && (better_eval || tie_better_field)) {
            best_eval_l1 = eval_mean;
            best_step = step;
            best_codebook = codebook;
            best_matrix = matrix_cells;
            best_hot_heads = hot.hot_heads;
            best_hot_triads = hot.hot_triads;
            best_field = hot.field_hot;
        }
        metrics << "{\"step\": " << step
                << ", \"train_windows\": " << processed
                << ", \"eval_windows\": " << eval_count
                << ", \"codewords\": " << codewords
                << ", \"train_mean_l1_q16\": " << train_mean
                << ", \"train_current_l1_q16\": " << train_current_mean
                << ", \"eval_mean_l1_q16\": " << eval_mean
                << ", \"eval_per_dim_l1_q16\": " << eval_per_dim
                << ", \"eval_relative_l1\": " << eval_relative
                << ", \"probe_hit_rate\": " << hit_rate
                << ", \"pair_top1_rate\": " << pair_top1_rate
                << ", \"probe_mean_score_q16\": " << score_mean
                << ", \"leaf_verify_rate\": " << leaf_rate
                << ", \"leaf_mean_error_q16\": " << leaf_mean_error
                << ", \"codebook_rollbacks\": " << rollbacks
                << ", \"matrix_nonzero\": " << matrix_nonzero
                << ", \"hot_heads\": " << hot.hot_heads
                << ", \"hot_triads\": " << hot.hot_triads
                << ", \"field_hot\": " << (hot.field_hot ? "true" : "false")
                << "}\n";
        metrics.flush();
        std::cout << "phase_train step=" << step
                  << " train_windows=" << processed
                  << " eval_windows=" << eval_count
                  << " train_l1=" << train_mean
                  << " train_current_l1=" << train_current_mean
                  << " eval_l1=" << eval_mean
                  << " eval_per_dim=" << eval_per_dim
                  << " pair_top1=" << pair_top1_rate
                  << " probe_hit=" << hit_rate
                  << " leaf_verify=" << leaf_rate
                  << " field_hot=" << (hot.field_hot ? "true" : "false")
                  << (final ? " final=1\n" : "\n");
        return true;
    };

    constexpr std::size_t kTrainChunk = 64;
    constexpr std::size_t kReplayAnchors = 256;
    const std::size_t anchor_count =
        std::min<std::size_t>(train_count, kReplayAnchors);
    std::vector<std::int32_t> anchor_bank;
    anchor_bank.reserve(anchor_count * pipeline_dim);
    for (std::size_t a = 0; a < anchor_count; ++a) {
        const std::size_t index =
            (a * train_count) / std::max<std::size_t>(1, anchor_count);
        anchor_bank.insert(anchor_bank.end(), vectors[index].begin(),
                           vectors[index].end());
    }
    std::size_t step = 0;
    for (std::size_t start = 0; start < train_count; start += kTrainChunk) {
        const std::size_t count = std::min(kTrainChunk, train_count - start);
        std::vector<std::int32_t> chunk_bank;
        chunk_bank.reserve(count * pipeline_dim);
        for (std::size_t i = 0; i < count; ++i) {
            const auto& sample = vectors[start + i];
            chunk_bank.insert(chunk_bank.end(), sample.begin(), sample.end());
            std::uint32_t code = 0;
            std::int32_t distance = 0;
            if (!vm.pq_encode(sample, codebook, codewords, pipeline_dim, code,
                              distance)) {
                std::cerr << "phase-train encode failed: " << vm.error() << "\n";
                return 7;
            }
            train_distance += static_cast<std::uint64_t>(distance);
            ++train_distance_count;
            if (have_previous_code && previous_code != code) {
                std::uint32_t pair = 0;
                std::int32_t value = 0;
                if (!vm.vector_matrix_accumulate(previous_code, code, 65536,
                                                 pair, value)) {
                    std::cerr << "phase-train matrix update failed: " << vm.error() << "\n";
                    return 7;
                }
            }
            previous_code = code;
            have_previous_code = true;
        }
        std::vector<std::int32_t> update_bank = anchor_bank;
        update_bank.insert(update_bank.end(), chunk_bank.begin(),
                           chunk_bank.end());
        if (!vm.pq_update(update_bank, anchor_count + count, pipeline_dim,
                          codewords, 1, codebook, 0)) {
            std::cerr << "phase-train codebook update failed: " << vm.error() << "\n";
            return 7;
        }
        processed = start + count;
        ++step;
        double candidate_eval = 0.0;
        if (!emit_metrics(step, false, candidate_eval)) return 7;
        if (candidate_eval > best_eval_l1 + 1e-9 &&
            !best_codebook.empty()) {
            codebook = best_codebook;
            ++rollbacks;
        }
    }
    double final_eval = 0.0;
    if (!emit_metrics(step + 1, true, final_eval)) return 7;
    const auto& selected_codebook = best_codebook.empty() ? codebook : best_codebook;
    {
        std::ofstream book(output_prefix + ".codebook.bin", std::ios::binary);
        if (book) {
            book.write(reinterpret_cast<const char*>(selected_codebook.data()),
                       static_cast<std::streamsize>(
                           selected_codebook.size() * sizeof(selected_codebook[0])));
        }
        std::vector<std::int32_t> matrix_cells = best_matrix;
        if (matrix_cells.empty()) vm.read_vector_matrix(matrix_cells);
        std::ofstream matrix(output_prefix + ".matrix.bin", std::ios::binary);
        if (matrix) {
            matrix.write(reinterpret_cast<const char*>(matrix_cells.data()),
                         static_cast<std::streamsize>(
                             matrix_cells.size() * sizeof(matrix_cells[0])));
        }
    }
    if (!selected_codebook.empty() && !best_matrix.empty()) {
        std::uint32_t codebook_digest = 0, matrix_digest = 0;
        if (vm.raw_hash(selected_codebook, codebook_digest) &&
            vm.raw_hash(best_matrix, matrix_digest)) {
            std::ofstream checkpoint(output_prefix + ".ckpt", std::ios::binary);
            if (checkpoint) {
                checkpoint.write("NANCKPT1", 8);
                const std::uint32_t codebook_words =
                    static_cast<std::uint32_t>(selected_codebook.size());
                const std::uint32_t matrix_words =
                    static_cast<std::uint32_t>(best_matrix.size());
                checkpoint.write(reinterpret_cast<const char*>(&codebook_words), 4);
                checkpoint.write(reinterpret_cast<const char*>(&matrix_words), 4);
                checkpoint.write(reinterpret_cast<const char*>(&codebook_digest), 4);
                checkpoint.write(reinterpret_cast<const char*>(&matrix_digest), 4);
                checkpoint.write(
                    reinterpret_cast<const char*>(selected_codebook.data()),
                    static_cast<std::streamsize>(
                        selected_codebook.size() * sizeof(selected_codebook[0])));
                checkpoint.write(
                    reinterpret_cast<const char*>(best_matrix.data()),
                    static_cast<std::streamsize>(
                        best_matrix.size() * sizeof(best_matrix[0])));
            }
        }
    }
    {
        std::ofstream summary(output_prefix + ".metrics.json");
        if (summary) {
            summary << "{\n  \"schema\": \"nanlm.phase-train-metrics/1\",\n"
                    << "  \"train_windows\": " << processed << ",\n"
                    << "  \"eval_windows\": " << eval_count << ",\n"
                    << "  \"codewords\": " << codewords << ",\n"
                    << "  \"codebook_words\": " << selected_codebook.size() << ",\n"
                    << "  \"matrix_words\": " << best_matrix.size() << ",\n"
                    << "  \"resumed\": " << (resumed ? "true" : "false") << ",\n"
                    << "  \"replay_anchors\": " << anchor_count << ",\n"
                    << "  \"codebook_rollbacks\": " << rollbacks << ",\n"
                    << "  \"best_step\": " << best_step << ",\n"
                    << "  \"best_eval_mean_l1_q16\": " << best_eval_l1 << ",\n"
                    << "  \"best_hot_heads\": " << best_hot_heads << ",\n"
                    << "  \"best_hot_triads\": " << best_hot_triads << ",\n"
                    << "  \"best_field_hot\": "
                    << (best_field ? "true" : "false") << "\n}\n";
        }
    }
    std::cout << "phase_train complete steps=" << step
              << " train_windows=" << processed
              << " eval_windows=" << eval_count
              << " codewords=" << codewords
              << " best_step=" << best_step
              << " best_eval_l1=" << best_eval_l1
              << " best_hot_heads=" << best_hot_heads
              << " best_hot_triads=" << best_hot_triads
              << " codebook_rollbacks=" << rollbacks
              << " best_field_hot=" << (best_field ? "true" : "false")
              << " resumed=" << (resumed ? "true" : "false")
              << " output=" << output_prefix << "\n";
    return 0;
}


int phase_codebook_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal phase-codebook CORPUS [MAX_LINES]"
                     " [WINDOW] [DIM] [CODEWORDS] [MAX_WINDOWS] [OUTPUT_PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, window = 8, dim = 128, codewords = 256;
    std::size_t max_windows = 4096;
    std::string output_prefix = "state/phase_codebook";
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) window = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) dim = static_cast<std::size_t>(std::stoull(argv[5]));
        if (argc > 6) codewords = static_cast<std::size_t>(std::stoull(argv[6]));
        if (argc > 7) max_windows = static_cast<std::size_t>(std::stoull(argv[7]));
        if (argc > 8) output_prefix = argv[8];
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    if (window == 0 || window > 8 || dim == 0 || dim > 128 ||
        codewords == 0 || codewords > 256 || max_windows < 64) {
        std::cerr << "window 1..8, dim 1..128, codewords 1..256,"
                     " max_windows >=64 required\n";
        return 2;
    }
    const std::size_t pipeline_dim = std::min<std::size_t>(dim * 2, 256);
    constexpr std::size_t kSubvectors = 8;
    if (pipeline_dim % kSubvectors != 0) {
        std::cerr << "pipeline dimension must divide into 8 subvectors\n";
        return 2;
    }
    const std::size_t subdim = pipeline_dim / kSubvectors;
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    const std::string data((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    std::vector<std::array<std::uint8_t, 8>> windows;
    windows.reserve(std::min<std::size_t>(max_windows, 4096));
    std::size_t begin = 0;
    while (begin <= data.size()) {
        const auto end = data.find('\n', begin);
        std::string_view line;
        if (end == std::string::npos) {
            if (begin >= data.size()) break;
            line = std::string_view(data.data() + begin, data.size() - begin);
            begin = data.size() + 1;
        } else {
            line = std::string_view(data.data() + begin, end - begin);
            begin = end + 1;
        }
        while (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        if (line.empty()) continue;
        const auto packed = make_window(line, window);
        std::array<std::uint8_t, 8> bytes{};
        for (std::size_t i = 0; i < window; ++i) bytes[i] = packed[i];
        windows.push_back(bytes);
        if (max_lines && windows.size() >= max_lines) break;
    }
    if (windows.size() > max_windows) {
        std::vector<std::array<std::uint8_t, 8>> sampled;
        sampled.reserve(max_windows);
        for (std::size_t i = 0; i < max_windows; ++i) {
            const std::size_t index =
                max_windows == 1 ? 0 :
                (i * (windows.size() - 1)) / (max_windows - 1);
            sampled.push_back(windows[index]);
        }
        windows.swap(sampled);
    }
    if (windows.size() < 64) {
        std::cerr << "phase-codebook needs at least 64 windows\n";
        return 3;
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.phase_table_init()) {
        std::cerr << "phase table init failed: " << vm.error() << "\n";
        return 7;
    }
    std::vector<std::vector<std::int32_t>> vectors;
    vectors.reserve(windows.size());
    constexpr std::size_t kEncodeBatch = 1024;
    for (std::size_t start = 0; start < windows.size(); start += kEncodeBatch) {
        const std::size_t count = std::min(kEncodeBatch, windows.size() - start);
        std::vector<std::uint8_t> bytes;
        bytes.reserve(count * window);
        for (std::size_t i = 0; i < count; ++i)
            bytes.insert(bytes.end(), windows[start + i].begin(),
                         windows[start + i].end());
        std::vector<std::int32_t> encoded;
        if (!vm.phase_encode_batch(bytes.data(), count, window, dim, encoded)) {
            std::cerr << "phase-codebook encode failed: " << vm.error() << "\n";
            return 7;
        }
        for (std::size_t i = 0; i < count; ++i)
            vectors.emplace_back(encoded.begin() + i * pipeline_dim,
                                 encoded.begin() + (i + 1) * pipeline_dim);
    }

    std::vector<std::int32_t> all_codebooks;
    all_codebooks.reserve(kSubvectors * codewords * subdim);
    std::size_t trained = 0;
    for (std::size_t sub = 0; sub < kSubvectors; ++sub) {
        std::vector<std::int32_t> codebook;
        constexpr std::size_t kTrainBatch = 512;
        for (std::size_t start = 0; start < vectors.size(); start += kTrainBatch) {
            const std::size_t count = std::min(kTrainBatch, vectors.size() - start);
            std::vector<std::int32_t> bank;
            bank.reserve(count * subdim);
            for (std::size_t i = 0; i < count; ++i)
                bank.insert(bank.end(),
                            vectors[start + i].begin() + sub * subdim,
                            vectors[start + i].begin() + (sub + 1) * subdim);
            if (codebook.empty()) {
                if (!vm.pq_train(bank, count, subdim, codewords, 1, codebook)) {
                    std::cerr << "phase-codebook train failed: " << vm.error() << "\n";
                    return 7;
                }
            } else if (!vm.pq_update(bank, count, subdim, codewords, 1,
                                     codebook)) {
                std::cerr << "phase-codebook update failed: " << vm.error() << "\n";
                return 7;
            }
        }
        all_codebooks.insert(all_codebooks.end(), codebook.begin(), codebook.end());
        trained += codebook.size();
    }
    const auto put32 = [](std::ofstream& out, std::uint32_t value) {
        const std::uint8_t bytes[4] = {
            static_cast<std::uint8_t>(value),
            static_cast<std::uint8_t>(value >> 8),
            static_cast<std::uint8_t>(value >> 16),
            static_cast<std::uint8_t>(value >> 24)};
        out.write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
    };
    std::ofstream book(output_prefix + ".codebook.bin", std::ios::binary);
    if (!book) { std::cerr << "cannot open phase codebook output\n"; return 3; }
    const char magic[8] = {'N', 'A', 'N', 'P', 'Q', '2', '\0', '\0'};
    book.write(magic, sizeof(magic));
    put32(book, 1);
    put32(book, static_cast<std::uint32_t>(pipeline_dim));
    put32(book, static_cast<std::uint32_t>(kSubvectors));
    put32(book, static_cast<std::uint32_t>(subdim));
    put32(book, static_cast<std::uint32_t>(codewords));
    put32(book, static_cast<std::uint32_t>(window));
    put32(book, static_cast<std::uint32_t>(vectors.size()));
    put32(book, 0);
    for (std::int32_t value : all_codebooks)
        put32(book, static_cast<std::uint32_t>(value));
    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.phase-codebook/1\",\n"
                 << "  \"context_bytes\": " << window << ",\n"
                 << "  \"context_words\": 0,\n"
                 << "  \"context_description\": \"last N bytes per line; no word tokenization\",\n"
                 << "  \"dim\": " << dim << ",\n"
                 << "  \"pipeline_dim\": " << pipeline_dim << ",\n"
                 << "  \"subvectors\": " << kSubvectors << ",\n"
                 << "  \"subdim\": " << subdim << ",\n"
                 << "  \"codewords\": " << codewords << ",\n"
                 << "  \"training_windows\": " << vectors.size() << ",\n"
                 << "  \"codebook_words\": " << trained << ",\n"
                 << "  \"output\": \"" << output_prefix << ".codebook.bin\"\n}\n";
    }
    std::cout << "phase_codebook windows=" << vectors.size()
              << " context_bytes=" << window
              << " dim=" << dim << " pipeline_dim=" << pipeline_dim
              << " subvectors=" << kSubvectors << " subdim=" << subdim
              << " codewords=" << codewords
              << " words=" << trained << " output=" << output_prefix
              << ".codebook.bin\n";
    return 0;
}


int meta_tokenize_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal meta-tokenize CORPUS [MAX_LINES]"
                     " [MAX_WORDS] [PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, max_words = 4096;
    std::string output_prefix = "state/meta_tokens";
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) max_words = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) output_prefix = argv[5];
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    if (max_words == 0 || max_words > 4096) {
        std::cerr << "max_words 1..4096 required\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    const std::string data((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.meta_trihead_reset()) {
        std::cerr << "meta trihead reset failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream words_out(output_prefix + ".words.bin", std::ios::binary);
    std::ofstream subwords_out(output_prefix + ".subwords.bin", std::ios::binary);
    std::ofstream meta_out(output_prefix + ".meta.bin", std::ios::binary);
    if (!words_out || !subwords_out || !meta_out) {
        std::cerr << "cannot open meta token artifacts\n";
        return 3;
    }
    std::size_t total_words = 0, total_subwords = 0, total_contexts = 0;
    std::size_t lines_seen = 0;
    std::size_t begin = 0;
    while (begin < data.size()) {
        const auto end = data.find('\n', begin);
        const std::size_t line_end = end == std::string::npos ? data.size() : end;
        if (max_lines && lines_seen >= max_lines) break;
        std::string line = data.substr(begin, line_end - begin);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        begin = end == std::string::npos ? data.size() : end + 1;
        ++lines_seen;
        if (line.empty()) continue;
        std::vector<std::uint32_t> words, subwords, meta;
        std::size_t word_count = 0, subword_count = 0;
        if (!vm.tokenize(line, max_words, words, subwords, meta,
                         word_count, subword_count)) {
            std::cerr << "tokenize failed: " << vm.error() << "\n";
            return 7;
        }
        if (word_count == 0) continue;
        std::size_t contexts = 0;
        if (!vm.meta_trihead_observe_batch(words, contexts)) {
            std::cerr << "meta trihead observe failed: " << vm.error() << "\n";
            return 7;
        }
        words_out.write(reinterpret_cast<const char*>(words.data()),
                        static_cast<std::streamsize>(words.size() * sizeof(words[0])));
        subwords_out.write(reinterpret_cast<const char*>(subwords.data()),
                           static_cast<std::streamsize>(subwords.size() * sizeof(subwords[0])));
        meta_out.write(reinterpret_cast<const char*>(meta.data()),
                       static_cast<std::streamsize>(meta.size() * sizeof(meta[0])));
        total_words += word_count;
        total_subwords += subword_count;
        total_contexts += contexts;
    }
    std::vector<std::int32_t> votes, credits;
    if (!vm.read_meta_trihead(votes, credits)) {
        std::cerr << "meta trihead read failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::uint8_t, kTriadCount> masks{};
    for (std::size_t i = 0; i < masks.size(); ++i)
        masks[i] = static_cast<std::uint8_t>(votes[i] & 7);
    std::uint16_t accepted = 0;
    bool field_accepted = false;
    if (!vm.field_vote(masks, accepted, field_accepted)) {
        std::cerr << "meta field vote failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::int32_t, kTriadMemberCount> head_credits{};
    std::copy(credits.begin(), credits.end(), head_credits.begin());
    HotTriheadResult hot;
    if (!vm.hot_triheads(head_credits, 0, hot)) {
        std::cerr << "meta hot trihead failed: " << vm.error() << "\n";
        return 7;
    }
    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.meta-tokenizer/1\",\n"
                 << "  \"context_words\": 3,\n"
                 << "  \"phase_window_bytes\": 8,\n"
                 << "  \"lines\": " << lines_seen << ",\n"
                 << "  \"words\": " << total_words << ",\n"
                 << "  \"subwords\": " << total_subwords << ",\n"
                 << "  \"contexts\": " << total_contexts << ",\n"
                 << "  \"accepted_triads\": " << accepted << ",\n"
                 << "  \"field_hot\": " << (field_accepted ? "true" : "false") << ",\n"
                 << "  \"hot_heads\": " << hot.hot_heads << ",\n"
                 << "  \"hot_triads\": " << hot.hot_triads << "\n}\n";
    }
    std::cout << "meta_tokenize lines=" << lines_seen
              << " words=" << total_words
              << " subwords=" << total_subwords
              << " contexts=" << total_contexts
              << " accepted_triads=" << accepted
              << " field_hot=" << (field_accepted ? "true" : "false")
              << " hot_heads=" << hot.hot_heads
              << " hot_triads=" << hot.hot_triads
              << " output=" << output_prefix << "\n";
    return 0;
}


int temporal_tokenize_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal temporal-tokenize CORPUS [MAX_LINES]"
                     " [MAX_WORDS] [PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, max_words = 4096;
    std::string output_prefix = "state/temporal_tokens";
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) max_words = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) output_prefix = argv[5];
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    if (max_words == 0 || max_words > 4096) {
        std::cerr << "max_words 1..4096 required\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    const std::string data((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.phase_table_init() || !vm.temporal_slots_reset()) {
        std::cerr << "temporal init failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream words_out(output_prefix + ".words.bin", std::ios::binary);
    std::ofstream subwords_out(output_prefix + ".subwords.bin", std::ios::binary);
    std::ofstream meta_out(output_prefix + ".meta.bin", std::ios::binary);
    std::ofstream slots_out(output_prefix + ".slots.bin", std::ios::binary);
    if (!words_out || !subwords_out || !meta_out || !slots_out) {
        std::cerr << "cannot open temporal token artifacts\n";
        return 3;
    }
    std::size_t total_words = 0, total_subwords = 0, total_contexts = 0;
    std::size_t lines_seen = 0;
    std::array<std::int32_t, 4> head255{};
    std::size_t begin = 0;
    while (begin < data.size()) {
        const auto end = data.find('\n', begin);
        const std::size_t line_end = end == std::string::npos ? data.size() : end;
        if (max_lines && lines_seen >= max_lines) break;
        std::string line = data.substr(begin, line_end - begin);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        begin = end == std::string::npos ? data.size() : end + 1;
        ++lines_seen;
        if (line.empty()) continue;
        std::vector<std::uint32_t> words, subwords, meta;
        std::size_t word_count = 0, subword_count = 0;
        if (!vm.tokenize(line, max_words, words, subwords, meta,
                         word_count, subword_count)) {
            std::cerr << "temporal tokenize failed: " << vm.error() << "\n";
            return 7;
        }
        if (word_count == 0) continue;
        std::size_t contexts = 0;
        if (!vm.temporal_slots_observe_batch(words, contexts)) {
            std::cerr << "temporal observe failed: " << vm.error() << "\n";
            return 7;
        }
        std::vector<std::int32_t> pv, pc, fv, fc, slots;
        std::vector<std::uint32_t> current;
        if (!vm.read_temporal_slots(word_count, pv, pc, fv, fc,
                                    current, head255, slots)) {
            std::cerr << "temporal read failed: " << vm.error() << "\n";
            return 7;
        }
        words_out.write(reinterpret_cast<const char*>(words.data()),
                        static_cast<std::streamsize>(words.size() * sizeof(words[0])));
        subwords_out.write(reinterpret_cast<const char*>(subwords.data()),
                           static_cast<std::streamsize>(subwords.size() * sizeof(subwords[0])));
        meta_out.write(reinterpret_cast<const char*>(meta.data()),
                       static_cast<std::streamsize>(meta.size() * sizeof(meta[0])));
        slots_out.write(reinterpret_cast<const char*>(slots.data()),
                        static_cast<std::streamsize>(slots.size() * sizeof(slots[0])));
        total_words += word_count;
        total_subwords += subword_count;
        total_contexts += contexts;
    }
    if (!vm.temporal_slots_project()) {
        std::cerr << "temporal project failed: " << vm.error() << "\n";
        return 7;
    }
    std::vector<std::int32_t> votes, credits;
    if (!vm.read_meta_trihead(votes, credits)) {
        std::cerr << "temporal projected read failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::uint8_t, kTriadCount> masks{};
    for (std::size_t i = 0; i < masks.size(); ++i)
        masks[i] = static_cast<std::uint8_t>(votes[i] & 7);
    std::uint16_t accepted = 0;
    bool field_accepted = false;
    if (!vm.field_vote(masks, accepted, field_accepted)) {
        std::cerr << "temporal field vote failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::int32_t, kTriadMemberCount> head_credits{};
    std::copy(credits.begin(), credits.end(), head_credits.begin());
    HotTriheadResult hot;
    if (!vm.hot_triheads(head_credits, 0, hot)) {
        std::cerr << "temporal hot trihead failed: " << vm.error() << "\n";
        return 7;
    }
    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.temporal-tokenizer/1\",\n"
                 << "  \"preceding_context_words\": 3,\n"
                 << "  \"anticipatory_context_words\": 3,\n"
                 << "  \"current_slot_head\": -1,\n"
                 << "  \"head255_policy\": \"void; current slot is a separate field register\",\n"
                 << "  \"phase_window_bytes\": 8,\n"
                 << "  \"lines\": " << lines_seen << ",\n"
                 << "  \"words\": " << total_words << ",\n"
                 << "  \"subwords\": " << total_subwords << ",\n"
                 << "  \"temporal_contexts\": " << total_contexts << ",\n"
                 << "  \"current_word\": " << head255[0] << ",\n"
                 << "  \"current_slot\": " << head255[1] << ",\n"
                 << "  \"accepted_triads\": " << accepted << ",\n"
                 << "  \"field_hot\": " << (field_accepted ? "true" : "false") << ",\n"
                 << "  \"hot_heads\": " << hot.hot_heads << ",\n"
                 << "  \"hot_triads\": " << hot.hot_triads << "\n}\n";
    }
    std::cout << "temporal_tokenize lines=" << lines_seen
              << " words=" << total_words
              << " subwords=" << total_subwords
              << " contexts=" << total_contexts
              << " current_word=" << head255[0]
              << " current_head=" << head255[1]
              << " accepted_triads=" << accepted
              << " field_hot=" << (field_accepted ? "true" : "false")
              << " hot_heads=" << hot.hot_heads
              << " hot_triads=" << hot.hot_triads
              << " output=" << output_prefix << "\n";
    return 0;
}


int ngram_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal ngram-train CORPUS [MAX_BYTES]"
                     " [PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_bytes = 1u << 20;
    std::string output_prefix = "state/ngrams";
    try {
        if (argc > 3) max_bytes = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) output_prefix = argv[4];
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    std::string data((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    if (max_bytes && data.size() > max_bytes) data.resize(max_bytes);
    if (data.empty()) { std::cerr << "empty ngram input\n"; return 3; }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.ngram_reset()) {
        std::cerr << "ngram reset failed: " << vm.error() << "\n";
        return 7;
    }
    std::size_t trained = 0;
    constexpr std::size_t kChunk = 65536;
    for (std::size_t start = 0; start < data.size(); start += kChunk) {
        const std::size_t count = std::min(kChunk, data.size() - start);
        std::size_t processed = 0;
        if (!vm.ngram_train(data.substr(start, count), processed)) {
            std::cerr << "ngram train failed: " << vm.error() << "\n";
            return 7;
        }
        trained += processed;
    }
    std::array<std::vector<std::uint32_t>, 4> keys, counts;
    if (!vm.ngram_topk(keys, counts)) {
        std::cerr << "ngram topk failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream out(output_prefix + ".ngrams.bin", std::ios::binary);
    if (!out) { std::cerr << "cannot open ngram output\n"; return 3; }
    for (std::size_t order = 0; order < 4; ++order) {
        for (std::size_t i = 0; i < keys[order].size(); ++i) {
            const std::uint32_t record[3] = {
                static_cast<std::uint32_t>(order + 1),
                keys[order][i], counts[order][i]};
            out.write(reinterpret_cast<const char*>(record), sizeof(record));
        }
    }
    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.byte-ngrams/1\",\n"
                 << "  \"orders\": [1,2,3,4],\n"
                 << "  \"top_k_per_order\": 64,\n"
                 << "  \"bytes_trained\": " << trained << ",\n"
                 << "  \"chunk_bytes\": " << kChunk << ",\n"
                 << "  \"boundary_ngrams\": \"chunk-local; cross-chunk ngrams are not counted\",\n"
                 << "  \"output\": \"" << output_prefix << ".ngrams.bin\"\n}\n";
    }
    std::size_t total = 0;
    for (const auto& list : keys) total += list.size();
    std::cout << "ngram_train bytes=" << trained
              << " orders=1,2,3,4 top_k=64 words=" << total
              << " output=" << output_prefix << ".ngrams.bin\n";
    return 0;
}


int stream_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal stream-train CORPUS [MAX_LINES]"
                     " [MAX_BYTES] [PREFIX]\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, max_bytes = 0;
    std::string output_prefix = "state/stream_train";
    try {
        if (argc > 3) max_lines = static_cast<std::size_t>(std::stoull(argv[3]));
        if (argc > 4) max_bytes = static_cast<std::size_t>(std::stoull(argv[4]));
        if (argc > 5) output_prefix = argv[5];
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    std::ifstream in(corpus_path, std::ios::binary);
    if (!in) { std::cerr << "cannot open corpus\n"; return 3; }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.phase_table_init() || !vm.ngram_reset() ||
        !vm.temporal_slots_reset() || !vm.triangle_model_reset() ||
        !vm.shape_field_reset()) {
        std::cerr << "stream init failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream words_out(output_prefix + ".words.bin", std::ios::binary);
    std::ofstream subwords_out(output_prefix + ".subwords.bin", std::ios::binary);
    std::ofstream meta_out(output_prefix + ".meta.bin", std::ios::binary);
    std::ofstream slots_out(output_prefix + ".slots.bin", std::ios::binary);
    if (!words_out || !subwords_out || !meta_out || !slots_out) {
        std::cerr << "cannot open stream token artifacts\n";
        return 3;
    }
    std::string carry;
    std::vector<std::int32_t> sample_bank;
    constexpr std::size_t kSampleLimit = 1024;
    constexpr std::size_t kMaxWordsPerLine = 4096;
    std::size_t lines = 0, bytes_seen = 0, words_total = 0, subwords_total = 0;
    std::size_t contexts_total = 0;
    std::array<std::int32_t, 4> head255{};
    std::size_t word_vector_count = 0, word_triangle_count = 0;
    std::size_t word_negative_triangle_count = 0;
    std::int64_t word_negative_score_sum = 0;
    std::int32_t word_negative_example_score = 0;
    std::int64_t word_tri_area_sum = 0, word_tri_tight_sum = 0;
    std::size_t word_tri_positive = 0, word_tri_negative = 0;
    std::int32_t word_path_length = 0, word_path_closure = 0;
    std::int32_t word_path_turn = 0, word_path_curvature = 0;
    std::int32_t word_phase_energy = 0, word_phase_radial = 0;
    std::uint32_t word_rotation_turn = 0;
    std::int32_t word_field_value = 0;
    std::size_t word_field_hot_heads = 0, word_field_hot_triads = 0;
    std::vector<std::int32_t> first_head255_vector, last_head255_vector;
    std::int32_t first_head255_word = 0, last_head255_word = 0;
    bool word_field_hot = false;
    std::array<std::int32_t, 3> word_tri_sides{};
    std::int32_t word_tri_area = 0, word_tri_tight = 0;
    std::vector<std::array<std::int32_t, 7>> word_triangle_records;
    std::array<std::array<std::uint32_t, 3>, 16> hodge_triads{};
    std::size_t hodge_triad_count = 0;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (max_lines && lines >= max_lines) break;
        if (max_bytes && bytes_seen + line.size() > max_bytes) {
            if (bytes_seen >= max_bytes) break;
        }
        ++lines;
        bytes_seen += line.size();
        auto feed_ngram = [&](const std::string& piece) -> bool {
            std::size_t offset = 0;
            while (offset < piece.size()) {
                const std::size_t count = std::min<std::size_t>(
                    65536 - carry.size(), piece.size() - offset);
                std::string combined = carry + piece.substr(offset, count);
                std::size_t processed = 0;
                if (!vm.ngram_train(combined, processed, carry.size())) {
                    std::cerr << "stream ngram failed: " << vm.error() << "\n";
                    return false;
                }
                offset += count;
                if (combined.size() >= 3)
                    carry = combined.substr(combined.size() - 3);
                else
                    carry = combined;
            }
            return true;
        };
        if (!feed_ngram(line + "\n")) return 7;
        if (line.empty()) continue;
        std::vector<std::uint32_t> words, subwords, meta;
        std::size_t word_count = 0, subword_count = 0;
        if (!vm.tokenize(line, kMaxWordsPerLine, words, subwords, meta,
                         word_count, subword_count)) {
            std::cerr << "stream tokenize failed: " << vm.error() << "\n";
            return 7;
        }
        if (word_count == 0) continue;
        std::size_t contexts = 0;
        if (!vm.temporal_slots_observe_batch(words, contexts)) {
            std::cerr << "stream temporal failed: " << vm.error() << "\n";
            return 7;
        }
        std::vector<std::int32_t> pv, pc, fv, fc, slots;
        std::vector<std::uint32_t> current;
        if (!vm.read_temporal_slots(word_count, pv, pc, fv, fc,
                                    current, head255, slots)) {
            std::cerr << "stream temporal read failed: " << vm.error() << "\n";
            return 7;
        }
        words_out.write(reinterpret_cast<const char*>(words.data()),
                        static_cast<std::streamsize>(words.size() * sizeof(words[0])));
        subwords_out.write(reinterpret_cast<const char*>(subwords.data()),
                           static_cast<std::streamsize>(subwords.size() * sizeof(subwords[0])));
        meta_out.write(reinterpret_cast<const char*>(meta.data()),
                       static_cast<std::streamsize>(meta.size() * sizeof(meta[0])));
        slots_out.write(reinterpret_cast<const char*>(slots.data()),
                        static_cast<std::streamsize>(slots.size() * sizeof(slots[0])));
        words_total += word_count;
        subwords_total += subword_count;
        contexts_total += contexts;

        // Explicit word-level triangle/path basis: tokenizer spans -> phase
        // vectors -> raw triangle/path geometry.
        std::vector<std::vector<std::int32_t>> word_vectors;
        const std::size_t word_geom_limit =
            std::min<std::size_t>(word_count, 32);
        const std::uint32_t line_turn =
            words.empty() ? 0u : (words[0] & 0xFFFFu);
        for (std::size_t wi = 0; wi < word_geom_limit; ++wi) {
            const std::size_t mbase = wi * 6;
            if (mbase + 5 >= meta.size()) break;
            const std::size_t wstart = meta[mbase + 4];
            const std::size_t wlen = meta[mbase + 5];
            if (wlen == 0 || wstart + wlen > line.size()) continue;
            std::array<std::uint8_t, 8> window{};
            const std::size_t take = std::min<std::size_t>(8, wlen);
            for (std::size_t k = 0; k < take; ++k)
                window[8 - take + k] = static_cast<std::uint8_t>(
                    line[wstart + wlen - take + k]);
            std::vector<std::int32_t> vector;
            std::uint32_t shard = 0;
            if (!vm.phase_encode_wide(window.data(), 8, 128, vector, shard)) {
                std::cerr << "word phase encode failed: " << vm.error() << "\n";
                return 7;
            }
            std::vector<std::int32_t> rotated;
            if (!vm.phase_rotate(vector, line_turn, rotated)) {
                std::cerr << "word phase rotation failed: " << vm.error() << "\n";
                return 7;
            }
            word_vectors.push_back(std::move(rotated));
        }
        word_vector_count += word_vectors.size();
        if (!word_vectors.empty()) {
            if (first_head255_vector.empty()) {
                first_head255_vector = word_vectors.back();
                first_head255_word = head255[0];
            }
            last_head255_vector = word_vectors.back();
            last_head255_word = head255[0];
        }
        if (word_vectors.size() >= 2) {
            std::vector<std::int32_t> wbank;
            wbank.reserve(word_vectors.size() * 256);
            for (const auto& v : word_vectors)
                wbank.insert(wbank.end(), v.begin(), v.end());
            if (!vm.path_geometry(wbank, word_vectors.size(), 256,
                                  word_path_length, word_path_closure,
                                  word_path_turn, word_path_curvature)) {
                std::cerr << "word path geometry failed: " << vm.error() << "\n";
                return 7;
            }
            std::vector<std::int32_t> last = word_vectors.back();
            word_rotation_turn = line_turn;
            if (!vm.phase_hyperbolic(last, 128, word_phase_energy,
                                     word_phase_radial)) {
                std::cerr << "word phase hyperbolic failed: " << vm.error() << "\n";
                return 7;
            }
            std::vector<std::int32_t> fcredits, fvotes;
            if (!vm.field_perturb(last, 256, fcredits, fvotes,
                                  word_field_value)) {
                std::cerr << "word field perturb failed: " << vm.error() << "\n";
                return 7;
            }
            std::array<std::int32_t, kTriadMemberCount> wc{};
            std::copy(fcredits.begin(), fcredits.end(), wc.begin());
            HotTriheadResult word_hot;
            if (!vm.hot_triheads(wc, 0, word_hot)) {
                std::cerr << "word field trihead failed: " << vm.error() << "\n";
                return 7;
            }
            word_field_hot_heads = word_hot.hot_heads;
            word_field_hot_triads = word_hot.hot_triads;
            word_field_hot = word_hot.field_hot;
        }
        for (std::size_t ti = 0; ti + 2 < word_vectors.size(); ++ti) {
            std::vector<std::int32_t> tri;
            tri.insert(tri.end(), word_vectors[ti].begin(), word_vectors[ti].end());
            tri.insert(tri.end(), word_vectors[ti + 1].begin(), word_vectors[ti + 1].end());
            tri.insert(tri.end(), word_vectors[ti + 2].begin(), word_vectors[ti + 2].end());
            std::array<std::int32_t, 3> sides{};
            std::int32_t area = 0, tight = 0, orient = 0;
            if (!vm.triangle_geometry(tri, 256, sides, area, tight, orient)) {
                std::cerr << "word triangle failed: " << vm.error() << "\n";
                return 7;
            }
            std::int32_t model_count = 0;
            if (!vm.triangle_model_observe(sides, area, tight, orient,
                                           model_count)) {
                std::cerr << "word triangle observe failed: " << vm.error() << "\n";
                return 7;
            }
            std::int32_t shape_score = 0;
            if (!vm.triangle_model_score(sides, area, tight, shape_score)) {
                std::cerr << "word triangle score failed: " << vm.error() << "\n";
                return 7;
            }
            word_triangle_records.push_back({sides[0], sides[1], sides[2],
                                             area, tight, orient, shape_score});
            const std::size_t triad_index =
                (ti + 2 < word_count && (ti + 2) * 6 + 2 < meta.size())
                    ? static_cast<std::uint32_t>(meta[(ti + 2) * 6 + 2] % 85)
                    : static_cast<std::uint32_t>(shape_score % 85);
            if (!vm.shape_field_observe(triad_index, tight, orient, area)) {
                std::cerr << "shape field observe failed: " << vm.error() << "\n";
                return 7;
            }
            if (hodge_triad_count < hodge_triads.size()) {
                hodge_triads[hodge_triad_count++] = {
                    static_cast<std::uint32_t>(triad_index * 3),
                    static_cast<std::uint32_t>(triad_index * 3 + 1),
                    static_cast<std::uint32_t>(triad_index * 3 + 2)};
            }
            ++word_triangle_count;
            word_tri_area_sum += area;
            word_tri_tight_sum += tight;
            if (orient > 0) ++word_tri_positive;
            if (orient < 0) ++word_tri_negative;
            if (word_triangle_count == 1) {
                word_tri_sides = sides;
                word_tri_area = area;
                word_tri_tight = tight;
            }

            // Contrastive negative: three non-adjacent words from the same
            // line. Raw geometry and the negative shape bank do the rest.
            if (ti + 5 < word_vectors.size()) {
                std::vector<std::int32_t> ntri;
                ntri.insert(ntri.end(), word_vectors[ti + 3].begin(),
                            word_vectors[ti + 3].end());
                ntri.insert(ntri.end(), word_vectors[ti + 4].begin(),
                            word_vectors[ti + 4].end());
                ntri.insert(ntri.end(), word_vectors[ti + 5].begin(),
                            word_vectors[ti + 5].end());
                std::array<std::int32_t, 3> nsides{};
                std::int32_t narea = 0, ntight = 0, norient = 0;
                if (!vm.triangle_geometry(ntri, 256, nsides, narea, ntight,
                                          norient)) {
                    std::cerr << "negative triangle geometry failed: "
                              << vm.error() << "\n";
                    return 7;
                }
                std::int32_t negative_count = 0;
                if (!vm.triangle_model_observe_negative(
                        nsides, narea, ntight, norient, negative_count)) {
                    std::cerr << "negative triangle observe failed: "
                              << vm.error() << "\n";
                    return 7;
                }
                std::int32_t negative_score = 0;
                if (!vm.triangle_model_score_contrastive(
                        nsides, narea, ntight, negative_score)) {
                    std::cerr << "negative contrast score failed: "
                              << vm.error() << "\n";
                    return 7;
                }
                ++word_negative_triangle_count;
                word_negative_score_sum += negative_score;
                if (word_negative_triangle_count == 1)
                    word_negative_example_score = negative_score;
            }
        }
        if (sample_bank.size() < kSampleLimit * 256 && line.size() >= 8) {
            std::array<std::uint8_t, 8> window{};
            const std::size_t start = line.size() - 8;
            for (std::size_t i = 0; i < 8; ++i)
                window[i] = static_cast<std::uint8_t>(line[start + i]);
            std::vector<std::int32_t> vector;
            std::uint32_t shard = 0;
            if (!vm.phase_encode_wide(window.data(), 8, 128, vector, shard)) {
                std::cerr << "stream phase sample failed: " << vm.error() << "\n";
                return 7;
            }
            sample_bank.insert(sample_bank.end(), vector.begin(), vector.end());
        }
    }
    std::array<std::vector<std::uint32_t>, 4> ngram_keys, ngram_counts;
    if (!vm.ngram_topk(ngram_keys, ngram_counts)) {
        std::cerr << "stream ngram topk failed: " << vm.error() << "\n";
        return 7;
    }
    std::ofstream ngram_out(output_prefix + ".ngrams.bin", std::ios::binary);
    if (ngram_out) {
        for (std::size_t order = 0; order < 4; ++order)
            for (std::size_t i = 0; i < ngram_keys[order].size(); ++i) {
                const std::uint32_t rec[3] = {
                    static_cast<std::uint32_t>(order + 1),
                    ngram_keys[order][i], ngram_counts[order][i]};
                ngram_out.write(reinterpret_cast<const char*>(rec), sizeof(rec));
            }
    }
    std::size_t codebook_words = 0;
    std::size_t codebook_codewords = 0;
    if (sample_bank.size() >= 64 * 256) {
        const std::size_t samples = sample_bank.size() / 256;
        codebook_codewords = std::min<std::size_t>(samples, 32);
        std::vector<std::int32_t> codebook;
        if (!vm.pq_train(sample_bank, samples, 256, codebook_codewords, 1,
                         codebook)) {
            std::cerr << "stream codebook failed: " << vm.error() << "\n";
            return 7;
        }
        std::ofstream book(output_prefix + ".codebook.bin", std::ios::binary);
        if (book) {
            book.write(reinterpret_cast<const char*>(codebook.data()),
                       static_cast<std::streamsize>(
                           codebook.size() * sizeof(codebook[0])));
            codebook_words = codebook.size();
        }
    }
    std::array<std::int32_t, 3> triangle_shape{};
    std::array<std::int32_t, 2> triangle_orient_counts{};
    std::int32_t triangle_shape_score = 0;
    if (word_triangle_count > 0) {
        if (!vm.read_triangle_model(triangle_shape, triangle_orient_counts)) {
            std::cerr << "triangle model read failed: " << vm.error() << "\n";
            return 7;
        }
        if (!vm.triangle_model_score(word_tri_sides, word_tri_area,
                                     word_tri_tight, triangle_shape_score)) {
            std::cerr << "triangle model score failed: " << vm.error() << "\n";
            return 7;
        }
    }
    if (!word_triangle_records.empty()) {
        std::ofstream tri_out(output_prefix + ".triangles.bin", std::ios::binary);
        if (tri_out) {
            for (const auto& record : word_triangle_records)
                tri_out.write(reinterpret_cast<const char*>(record.data()),
                              static_cast<std::streamsize>(record.size() *
                                                           sizeof(record[0])));
        }
    }
    std::int32_t head255_closure = word_path_closure;
    if (!first_head255_vector.empty() && !last_head255_vector.empty()) {
        std::vector<std::int32_t> endpoints;
        endpoints.insert(endpoints.end(), first_head255_vector.begin(),
                         first_head255_vector.end());
        endpoints.insert(endpoints.end(), last_head255_vector.begin(),
                         last_head255_vector.end());
        std::int32_t head_len = 0, head_turn = 0, head_curvature = 0;
        if (!vm.path_geometry(endpoints, 2, 256, head_len, head255_closure,
                              head_turn, head_curvature)) {
            std::cerr << "head255 closure failed: " << vm.error() << "\n";
            return 7;
        }
    }
    std::uint16_t shape_field_accepted = 0;
    bool shape_field_hot = false;
    std::int32_t shape_field_mean = 0;
    if (word_triangle_count > 0) {
        if (!vm.shape_field_gate(head255_closure, word_path_length, 0,
                                 shape_field_accepted, shape_field_hot,
                                 shape_field_mean)) {
            std::cerr << "shape field gate failed: " << vm.error() << "\n";
            return 7;
        }
    }
    bool hodge_ok = false;
    float hodge_divergence_l1 = 0.0f, hodge_curl_l1 = 0.0f;
    if (hodge_triad_count > 0) {
        std::vector<float> divergence, curl;
        if (!vm.global_hodge_from_triads(hodge_triads, hodge_triad_count,
                                          divergence, curl)) {
            std::cerr << "stream hodge failed: " << vm.error() << "\n";
            return 7;
        }
        hodge_ok = true;
        for (float value : divergence)
            hodge_divergence_l1 += value < 0.0f ? -value : value;
        for (float value : curl)
            hodge_curl_l1 += value < 0.0f ? -value : value;
    }
    const bool global_field_hot = shape_field_hot && hodge_ok;
    const std::size_t geometry_samples = sample_bank.size() / 256;
    std::int32_t path_length = 0, path_closure = 0, path_turn = 0;
    std::int32_t path_curvature = 0;
    std::int32_t hyper_mean = 0, hyper_radial = 0;
    std::int32_t tri_area = 0, tri_tight = 0, tri_orientation = 0;
    std::array<std::int32_t, 3> tri_sides{};
    std::int32_t field_value = 0;
    std::vector<std::int32_t> field_credits, field_votes;
    if (geometry_samples >= 2) {
        if (!vm.path_geometry(sample_bank, geometry_samples, 256,
                              path_length, path_closure, path_turn,
                              path_curvature)) {
            std::cerr << "stream path geometry failed: " << vm.error() << "\n";
            return 7;
        }
        std::vector<std::int32_t> last(sample_bank.end() - 256,
                                       sample_bank.end());
        if (!vm.hyperbolic_measure(last, 256, hyper_mean, hyper_radial)) {
            std::cerr << "stream hyperbolic failed: " << vm.error() << "\n";
            return 7;
        }
        if (!vm.field_perturb(last, 256, field_credits, field_votes,
                              field_value)) {
            std::cerr << "stream field perturb failed: " << vm.error() << "\n";
            return 7;
        }
    }
    if (geometry_samples >= 3) {
        std::vector<std::int32_t> tri(sample_bank.begin(),
                                      sample_bank.begin() + 3 * 256);
        if (!vm.triangle_geometry(tri, 256, tri_sides, tri_area, tri_tight,
                                  tri_orientation)) {
            std::cerr << "stream triangle failed: " << vm.error() << "\n";
            return 7;
        }
    }
    HotTriheadResult geometry_hot;
    bool geometry_hot_valid = false;
    if (geometry_samples >= 2 && field_credits.size() == 255) {
        std::array<std::int32_t, kTriadMemberCount> gc{};
        std::copy(field_credits.begin(), field_credits.end(), gc.begin());
        if (!vm.hot_triheads(gc, 0, geometry_hot)) {
            std::cerr << "stream geometry trihead failed: " << vm.error() << "\n";
            return 7;
        }
        geometry_hot_valid = true;
    }
    if (!vm.temporal_slots_project()) {
        std::cerr << "stream temporal project failed: " << vm.error() << "\n";
        return 7;
    }
    std::vector<std::int32_t> votes, credits;
    if (!vm.read_meta_trihead(votes, credits)) {
        std::cerr << "stream temporal read failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::uint8_t, kTriadCount> masks{};
    for (std::size_t i = 0; i < masks.size(); ++i)
        masks[i] = static_cast<std::uint8_t>(votes[i] & 7);
    std::uint16_t accepted = 0;
    bool field_accepted = false;
    if (!vm.field_vote(masks, accepted, field_accepted)) {
        std::cerr << "stream field vote failed: " << vm.error() << "\n";
        return 7;
    }
    std::array<std::int32_t, kTriadMemberCount> head_credits{};
    std::copy(credits.begin(), credits.end(), head_credits.begin());
    HotTriheadResult hot;
    if (!vm.hot_triheads(head_credits, 0, hot)) {
        std::cerr << "stream hot trihead failed: " << vm.error() << "\n";
        return 7;
    }
    auto manifest = std::ofstream(output_prefix + ".json");
    if (manifest) {
        manifest << "{\n  \"schema\": \"nanlm.stream-train/1\",\n"
                 << "  \"lines\": " << lines << ",\n"
                 << "  \"bytes\": " << bytes_seen << ",\n"
                 << "  \"words\": " << words_total << ",\n"
                 << "  \"subwords\": " << subwords_total << ",\n"
                 << "  \"temporal_contexts\": " << contexts_total << ",\n"
                 << "  \"phase_window_bytes\": 8,\n"
                 << "  \"preceding_context_words\": 3,\n"
                 << "  \"anticipatory_context_words\": 3,\n"
                 << "  \"current_slot_head\": -1,\n"
                 << "  \"head255_policy\": \"void; current slot is a separate field register\",\n"
                 << "  \"current_word\": " << head255[0] << ",\n"
                 << "  \"current_slot\": " << head255[1] << ",\n"
                 << "  \"ngram_orders\": [1,2,3,4],\n"
                 << "  \"ngram_top_k\": 64,\n"
                 << "  \"codebook_codewords\": " << codebook_codewords << ",\n"
                 << "  \"codebook_words\": " << codebook_words << ",\n"
                 << "  \"geometry\": {\"samples\": " << geometry_samples
                 << ", \"path_length\": " << path_length
                 << ", \"path_closure\": " << path_closure
                 << ", \"path_turn\": " << path_turn
                 << ", \"path_curvature\": " << path_curvature
                 << ", \"hyperbolic_radius\": " << hyper_radial
                 << ", \"triangle_area\": " << tri_area
                 << ", \"triangle_tightness\": " << tri_tight
                 << ", \"triangle_orientation\": " << tri_orientation
                 << ", \"field_perturbation\": " << field_value
                 << ", \"geometry_hot_heads\": "
                 << (geometry_hot_valid ? geometry_hot.hot_heads : 0)
                 << ", \"geometry_hot_triads\": "
                 << (geometry_hot_valid ? geometry_hot.hot_triads : 0)
                 << ", \"geometry_field_hot\": "
                 << (geometry_hot_valid && geometry_hot.field_hot ? "true" : "false")
                 << "},\n"
                 << "  \"word_geometry\": {\"vectors\": " << word_vector_count
                 << ", \"triangles\": " << word_triangle_count
                 << ", \"triangle_area_sum\": " << word_tri_area_sum
                 << ", \"triangle_tightness_sum\": " << word_tri_tight_sum
                 << ", \"triangle_positive\": " << word_tri_positive
                 << ", \"triangle_negative\": " << word_tri_negative
                 << ", \"example_area\": " << word_tri_area
                 << ", \"example_tightness\": " << word_tri_tight
                 << ", \"example_sides\": [" << word_tri_sides[0]
                 << "," << word_tri_sides[1] << "," << word_tri_sides[2] << "]"
                 << ", \"path_length\": " << word_path_length
                 << ", \"path_closure\": " << word_path_closure
                 << ", \"path_turn\": " << word_path_turn
                 << ", \"path_curvature\": " << word_path_curvature
                 << ", \"phase_energy\": " << word_phase_energy
                 << ", \"phase_radial\": " << word_phase_radial
                 << ", \"rotation_turn\": " << word_rotation_turn
                 << ", \"field_perturbation\": " << word_field_value
                 << ", \"field_hot_heads\": " << word_field_hot_heads
                 << ", \"field_hot_triads\": " << word_field_hot_triads
                 << ", \"field_hot\": " << (word_field_hot ? "true" : "false")
                 << ", \"shape_count\": " << triangle_shape[2]
                 << ", \"shape_tightness_sum\": " << triangle_shape[0]
                 << ", \"shape_area_sum\": " << triangle_shape[1]
                 << ", \"shape_positive\": " << triangle_orient_counts[0]
                 << ", \"shape_negative\": " << triangle_orient_counts[1]
                 << ", \"contrastive_triangles\": "
                 << word_negative_triangle_count
                 << ", \"contrastive_score_sum\": "
                 << word_negative_score_sum
                 << ", \"contrastive_example_score\": "
                 << word_negative_example_score
                 << ", \"example_score\": " << triangle_shape_score
                 << ", \"triangle_records\": " << word_triangle_records.size()
                 << ", \"first_triangle_score\": "
                 << (word_triangle_records.empty() ? 0 :
                     word_triangle_records.front()[6])
                 << ", \"last_triangle_score\": "
                 << (word_triangle_records.empty() ? 0 :
                     word_triangle_records.back()[6])
                 << ", \"shape_field_accepted\": " << shape_field_accepted
                 << ", \"shape_field_hot\": "
                 << (shape_field_hot ? "true" : "false")
                 << ", \"shape_field_mean\": " << shape_field_mean
                 << ", \"hodge_ok\": " << (hodge_ok ? "true" : "false")
                 << ", \"hodge_divergence_l1\": " << hodge_divergence_l1
                 << ", \"hodge_curl_l1\": " << hodge_curl_l1
                 << ", \"global_field_hot\": " << (global_field_hot ? "true" : "false")
                 << ", \"current_field_first_word\": " << first_head255_word
                 << ", \"current_field_last_word\": " << last_head255_word
                 << ", \"current_field_closure\": " << head255_closure
                 << "},\n"
                 << "  \"accepted_triads\": " << accepted << ",\n"
                 << "  \"field_hot\": " << (field_accepted ? "true" : "false") << "\n}\n";
    }
    std::cout << "stream_train lines=" << lines
              << " bytes=" << bytes_seen
              << " words=" << words_total
              << " subwords=" << subwords_total
              << " contexts=" << contexts_total
              << " current_word=" << head255[0]
              << " codebook_words=" << codebook_words
              << " accepted_triads=" << accepted
              << " field_hot=" << (field_accepted ? "true" : "false")
              << " global_field_hot=" << (global_field_hot ? "true" : "false")
              << " output=" << output_prefix << "\n";
    return 0;
}

// ---------------------------------------------------------------------------
// Relation-triangle contrast trainer
//
// N16TRI/1 rows carry role text, not precomputed vectors.  This trainer
// phase-encodes each role in the raw guest, computes the raw triangle shape,
// trains the positive and negative shape banks, selects a threshold on the
// valid split, and reports held-out test metrics.  Host code never computes a
// triangle score itself.
// ---------------------------------------------------------------------------
namespace {

constexpr std::size_t kTriDim = 256;
constexpr std::size_t kTriComponents = 3 * kTriDim;
constexpr std::size_t kTriRelationCount = 6;

constexpr std::array<const char*, kTriRelationCount> kTriRelationNames = {
    "ISA", "HAS_SUBTYPE", "PART_OF", "HAS_PART", "CONTRADICTS", "ASSOCIATED"};
constexpr std::array<const char*, 3> kTriSplitNames = {"train", "valid", "test"};
constexpr std::array<const char*, 5> kTriLabelNames = {
    "positive", "inverse", "hard_negative", "negative", "self_negative"};

enum TriSplit : std::uint8_t { kTriTrain = 0, kTriValid = 1, kTriTest = 2 };
enum TriLabel : std::uint8_t {
    kTriPositive = 0,
    kTriInverse = 1,
    kTriHardNegative = 2,
    kTriNegative = 3,
    kTriSelfNegative = 4,
};

bool tri_positive_label(TriLabel label) {
    return label == kTriPositive || label == kTriInverse;
}

struct TriFeature {
    TriSplit split = kTriTrain;
    std::uint8_t relation = 0;
    TriLabel label = kTriPositive;
    std::uint32_t confidence = 0;
    std::int32_t score = 0;
    std::int32_t global_score = 0;
    std::int32_t shape_score = 0;
    std::int32_t global_shape_score = 0;
    std::array<std::int32_t, 3> sides{};
    std::int32_t area = 0;
    std::int32_t tightness = 0;
    std::int32_t orientation = 0;
};

struct TriBank {
    std::array<std::int32_t, 3> positive_shape{};
    std::array<std::int32_t, 2> positive_orientation{};
    std::array<std::int32_t, 3> negative_shape{};
    std::array<std::int32_t, 2> negative_orientation{};
};

struct TriMetrics {
    std::size_t n = 0;
    std::size_t positives = 0;
    std::size_t negatives = 0;
    std::size_t tp = 0;
    std::size_t fp = 0;
    std::size_t tn = 0;
    std::size_t fn = 0;
    double auc = 0.5;
    double balanced_accuracy = 0.0;
    double precision = 0.0;
    double recall = 0.0;
    double f1 = 0.0;
    double mean_score_positive = 0.0;
    double mean_score_negative = 0.0;
    std::int32_t threshold = 0;
};

std::vector<std::string> tri_split_tabs(const std::string& line) {
    std::vector<std::string> out;
    std::size_t start = 0;
    while (true) {
        const std::size_t pos = line.find('\t', start);
        if (pos == std::string::npos) {
            out.push_back(line.substr(start));
            break;
        }
        out.push_back(line.substr(start, pos - start));
        start = pos + 1;
    }
    return out;
}

bool tri_parse_uint(const std::string& text, std::uint32_t& value) {
    if (text.empty()) return false;
    std::uint64_t acc = 0;
    for (char c : text) {
        if (c < '0' || c > '9') return false;
        acc = acc * 10 + static_cast<std::uint64_t>(c - '0');
        if (acc > 0xFFFFFFFFull) return false;
    }
    value = static_cast<std::uint32_t>(acc);
    return true;
}

bool tri_unhex(const std::string& text, std::string& out) {
    if (text.empty() || (text.size() & 1u)) return false;
    auto nibble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    out.clear();
    out.reserve(text.size() / 2);
    for (std::size_t i = 0; i < text.size(); i += 2) {
        const int hi = nibble(text[i]);
        const int lo = nibble(text[i + 1]);
        if (hi < 0 || lo < 0) return false;
        out.push_back(static_cast<char>((hi << 4) | lo));
    }
    return true;
}

bool tri_is_sha256_hex(const std::string& text) {
    if (text.size() != 64) return false;
    for (char c : text) {
        const bool digit = c >= '0' && c <= '9';
        const bool lower = c >= 'a' && c <= 'f';
        const bool upper = c >= 'A' && c <= 'F';
        if (!digit && !lower && !upper) return false;
    }
    return true;
}

bool tri_parse_split(const std::string& text, TriSplit& split) {
    for (std::size_t i = 0; i < kTriSplitNames.size(); ++i) {
        if (text == kTriSplitNames[i]) {
            split = static_cast<TriSplit>(i);
            return true;
        }
    }
    return false;
}

bool tri_parse_relation(const std::string& text, std::uint8_t& relation) {
    for (std::size_t i = 0; i < kTriRelationNames.size(); ++i) {
        if (text == kTriRelationNames[i]) {
            relation = static_cast<std::uint8_t>(i);
            return true;
        }
    }
    return false;
}

bool tri_parse_label(const std::string& text, TriLabel& label) {
    for (std::size_t i = 0; i < kTriLabelNames.size(); ++i) {
        if (text == kTriLabelNames[i]) {
            label = static_cast<TriLabel>(i);
            return true;
        }
    }
    return false;
}

bool tri_encode_role(
    RawFieldVM& vm, const std::string& text,
    std::unordered_map<std::string, std::vector<std::int32_t>>& cache,
    std::vector<std::int32_t>& out, std::uint32_t& shard) {
    const auto found = cache.find(text);
    if (found != cache.end()) {
        out = found->second;
        return true;
    }
    std::array<std::uint8_t, 8> window{};
    window.fill(static_cast<std::uint8_t>(' '));
    const std::size_t take = std::min<std::size_t>(8, text.size());
    for (std::size_t i = 0; i < take; ++i)
        window[8 - take + i] =
            static_cast<std::uint8_t>(text[text.size() - take + i]);
    std::vector<std::int32_t> encoded;
    if (!vm.phase_encode_wide(window.data(), 8, 128, encoded, shard))
        return false;
    out = encoded;
    // Keep the cache bounded.  WordNet lemmas repeat heavily, so this avoids
    // re-encoding the same role while keeping memory predictable.
    if (cache.size() >= 24000) cache.clear();
    cache.emplace(text, encoded);
    return true;
}

void tri_read_bank(RawFieldVM& vm, TriBank& bank) {
    vm.read_triangle_model(bank.positive_shape, bank.positive_orientation);
    vm.read_triangle_model_negative(bank.negative_shape,
                                    bank.negative_orientation);
}

template <typename ScoreFn>
double tri_auc(const std::vector<const TriFeature*>& rows, ScoreFn score) {
    std::size_t positives = 0, negatives = 0;
    std::vector<std::pair<std::int32_t, bool>> values;
    values.reserve(rows.size());
    for (const TriFeature* row : rows) {
        const bool positive = tri_positive_label(row->label);
        values.emplace_back(score(*row), positive);
        if (positive) ++positives;
        else ++negatives;
    }
    if (positives == 0 || negatives == 0) return 0.5;
    std::sort(values.begin(), values.end(),
              [](const auto& a, const auto& b) {
                  if (a.first != b.first) return a.first < b.first;
                  return a.second < b.second;
              });
    double rank_sum_positive = 0.0;
    double rank = 1.0;
    std::size_t i = 0;
    while (i < values.size()) {
        std::size_t j = i;
        while (j < values.size() && values[j].first == values[i].first) ++j;
        const double group_size = static_cast<double>(j - i);
        const double average_rank = rank + (group_size - 1.0) / 2.0;
        for (std::size_t k = i; k < j; ++k)
            if (values[k].second) rank_sum_positive += average_rank;
        rank += group_size;
        i = j;
    }
    const double npos = static_cast<double>(positives);
    const double nneg = static_cast<double>(negatives);
    return (rank_sum_positive - npos * (npos + 1.0) / 2.0) / (npos * nneg);
}

template <typename ScoreFn>
TriMetrics tri_evaluate(const std::vector<const TriFeature*>& rows,
                        ScoreFn score, std::int32_t threshold) {
    TriMetrics metrics;
    metrics.n = rows.size();
    metrics.threshold = threshold;
    double positive_sum = 0.0, negative_sum = 0.0;
    for (const TriFeature* row : rows) {
        const bool positive = tri_positive_label(row->label);
        const std::int32_t value = score(*row);
        if (positive) {
            ++metrics.positives;
            positive_sum += value;
        } else {
            ++metrics.negatives;
            negative_sum += value;
        }
        const bool predicted = value >= threshold;
        if (positive && predicted) ++metrics.tp;
        else if (positive) ++metrics.fn;
        else if (predicted) ++metrics.fp;
        else ++metrics.tn;
    }
    if (metrics.positives > 0)
        metrics.mean_score_positive =
            positive_sum / static_cast<double>(metrics.positives);
    if (metrics.negatives > 0)
        metrics.mean_score_negative =
            negative_sum / static_cast<double>(metrics.negatives);
    const double tp = static_cast<double>(metrics.tp);
    const double fp = static_cast<double>(metrics.fp);
    const double tn = static_cast<double>(metrics.tn);
    const double fn = static_cast<double>(metrics.fn);
    metrics.precision = (tp + fp) > 0.0 ? tp / (tp + fp) : 0.0;
    metrics.recall = (tp + fn) > 0.0 ? tp / (tp + fn) : 0.0;
    const double specificity = (tn + fp) > 0.0 ? tn / (tn + fp) : 0.0;
    metrics.balanced_accuracy = 0.5 * (metrics.recall + specificity);
    metrics.f1 = (metrics.precision + metrics.recall) > 0.0
                     ? 2.0 * metrics.precision * metrics.recall /
                           (metrics.precision + metrics.recall)
                     : 0.0;
    metrics.auc = tri_auc(rows, score);
    return metrics;
}

template <typename ScoreFn>
std::int32_t tri_select_threshold(const std::vector<const TriFeature*>& rows,
                                  ScoreFn score) {
    if (rows.empty()) return 32768;
    std::vector<std::pair<std::int32_t, bool>> values;
    values.reserve(rows.size());
    std::size_t positives = 0, negatives = 0;
    for (const TriFeature* row : rows) {
        const bool positive = tri_positive_label(row->label);
        values.emplace_back(score(*row), positive);
        if (positive) ++positives;
        else ++negatives;
    }
    if (positives == 0 || negatives == 0) return 32768;
    std::sort(values.begin(), values.end(),
              [](const auto& a, const auto& b) {
                  if (a.first != b.first) return a.first > b.first;
                  return a.second > b.second;
              });
    auto candidate = [&](std::size_t tp, std::size_t fp,
                         std::int32_t threshold, double& ba, double& f1) {
        const std::size_t tn = negatives - fp;
        const std::size_t fn = positives - tp;
        const double precision =
            (tp + fp) > 0 ? static_cast<double>(tp) / (tp + fp) : 0.0;
        const double recall =
            (tp + fn) > 0 ? static_cast<double>(tp) / (tp + fn) : 0.0;
        const double specificity =
            (tn + fp) > 0 ? static_cast<double>(tn) / (tn + fp) : 0.0;
        ba = 0.5 * (recall + specificity);
        f1 = (precision + recall) > 0.0
                 ? 2.0 * precision * recall / (precision + recall)
                 : 0.0;
        (void)threshold;
    };
    std::size_t tp = 0, fp = 0;
    double best_ba = 0.0, best_f1 = 0.0;
    std::int32_t best_threshold = 65537;
    candidate(0, 0, 65537, best_ba, best_f1);
    std::size_t i = 0;
    while (i < values.size()) {
        std::size_t j = i;
        while (j < values.size() && values[j].first == values[i].first) {
            if (values[j].second) ++tp;
            else ++fp;
            ++j;
        }
        const std::int32_t threshold = values[i].first;
        double ba = 0.0, f1 = 0.0;
        candidate(tp, fp, threshold, ba, f1);
        const bool better =
            ba > best_ba + 1e-12 ||
            (std::abs(ba - best_ba) <= 1e-12 && f1 > best_f1 + 1e-12) ||
            (std::abs(ba - best_ba) <= 1e-12 &&
             std::abs(f1 - best_f1) <= 1e-12 &&
             std::abs(threshold - 32768) < std::abs(best_threshold - 32768));
        if (better) {
            best_ba = ba;
            best_f1 = f1;
            best_threshold = threshold;
        }
        i = j;
    }
    return best_threshold;
}

std::string tri_json_escape(const std::string& text) {
    std::string out;
    out.reserve(text.size() + 8);
    for (char c : text) {
        switch (c) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    out += "\\u00";
                    const char* digits = "0123456789abcdef";
                    out.push_back(digits[(c >> 4) & 0xF]);
                    out.push_back(digits[c & 0xF]);
                } else {
                    out.push_back(c);
                }
                break;
        }
    }
    return out;
}

void tri_write_metrics(std::ostream& out, const TriMetrics& metrics) {
    out << "{\"n\":" << metrics.n
        << ",\"positives\":" << metrics.positives
        << ",\"negatives\":" << metrics.negatives
        << ",\"tp\":" << metrics.tp << ",\"fp\":" << metrics.fp
        << ",\"tn\":" << metrics.tn << ",\"fn\":" << metrics.fn
        << ",\"auc\":" << std::fixed << std::setprecision(6) << metrics.auc
        << ",\"balanced_accuracy\":" << metrics.balanced_accuracy
        << ",\"precision\":" << metrics.precision
        << ",\"recall\":" << metrics.recall
        << ",\"f1\":" << metrics.f1
        << ",\"mean_score_positive\":" << metrics.mean_score_positive
        << ",\"mean_score_negative\":" << metrics.mean_score_negative
        << ",\"threshold\":" << metrics.threshold << "}";
}

void tri_write_bank(std::ostream& out, const TriBank& bank) {
    out << "{\"positive_shape\":["
        << bank.positive_shape[0] << "," << bank.positive_shape[1] << ","
        << bank.positive_shape[2] << "],\"positive_orientation\":["
        << bank.positive_orientation[0] << ","
        << bank.positive_orientation[1] << "],\"negative_shape\":["
        << bank.negative_shape[0] << "," << bank.negative_shape[1] << ","
        << bank.negative_shape[2] << "],\"negative_orientation\":["
        << bank.negative_orientation[0] << ","
        << bank.negative_orientation[1] << "]}";
}

std::string tri_file_sha256(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return "";
    Sha256 hash;
    std::array<char, 65536> buffer{};
    while (in) {
        in.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        const std::streamsize got = in.gcount();
        if (got > 0)
            hash.update(buffer.data(), static_cast<std::size_t>(got));
    }
    return hex(hash.final());
}

} // namespace

int triangle_contrast_train_cli(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: nanlm-universal triangle-contrast-train RECORDS"
                     " [PREFIX] [MAX_ROWS]\n";
        return 2;
    }
    const std::string records_path = argv[2];
    std::string prefix = "state/triangle_contrast";
    std::size_t max_rows = 0;
    try {
        if (argc > 3) prefix = argv[3];
        if (argc > 4) max_rows = static_cast<std::size_t>(std::stoull(argv[4]));
    } catch (...) {
        std::cerr << "invalid numeric argument\n";
        return 2;
    }
    std::ifstream records(records_path, std::ios::binary);
    if (!records) {
        std::cerr << "cannot open records: " << records_path << "\n";
        return 3;
    }
    std::string header;
    std::getline(records, header);
    if (!header.empty() && header.back() == '\r') header.pop_back();
    if (header != "N16TRI/1") {
        std::cerr << "unsupported records header: " << header << "\n";
        return 3;
    }
    RawFieldVM vm("build/field_driver.nan");
    if (!vm.ready()) {
        std::cerr << "raw field VM unavailable: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.phase_table_init()) {
        std::cerr << "phase table init failed: " << vm.error() << "\n";
        return 7;
    }
    if (!vm.triangle_model_reset()) {
        std::cerr << "triangle reset failed: " << vm.error() << "\n";
        return 7;
    }

    std::vector<TriFeature> features;
    features.reserve(max_rows ? max_rows : 1u << 20);
    std::unordered_map<std::string, std::vector<std::int32_t>> role_cache;
    std::array<std::size_t, 3> split_counts{};
    std::array<std::size_t, 5> label_counts{};
    std::array<std::size_t, kTriRelationCount> relation_counts{};
    std::uint32_t shard = 0;
    std::string line;
    std::size_t line_no = 1;
    while (std::getline(records, line)) {
        ++line_no;
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        if (max_rows && features.size() >= max_rows) break;
        const std::vector<std::string> fields = tri_split_tabs(line);
        if (fields.size() != 9) {
            std::cerr << "line " << line_no << ": expected 9 fields, got "
                      << fields.size() << "\n";
            return 3;
        }
        TriFeature feature;
        if (!tri_parse_split(fields[0], feature.split) ||
            !tri_parse_relation(fields[1], feature.relation) ||
            !tri_parse_label(fields[2], feature.label)) {
            std::cerr << "line " << line_no << ": invalid split/relation/label\n";
            return 3;
        }
        if (!tri_parse_uint(fields[3], feature.confidence) ||
            feature.confidence > 65535) {
            std::cerr << "line " << line_no << ": invalid confidence\n";
            return 3;
        }
        std::string subject_text, predicate_text, object_text;
        if (!tri_unhex(fields[4], subject_text) ||
            !tri_unhex(fields[5], predicate_text) ||
            !tri_unhex(fields[6], object_text)) {
            std::cerr << "line " << line_no << ": invalid role hex\n";
            return 3;
        }
        if (subject_text.empty() || predicate_text.empty() || object_text.empty()) {
            std::cerr << "line " << line_no << ": empty role text\n";
            return 3;
        }
        if (!tri_is_sha256_hex(fields[7])) {
            std::cerr << "line " << line_no << ": invalid source_sha256\n";
            return 3;
        }
        if (fields[8].empty()) {
            std::cerr << "line " << line_no << ": empty provenance\n";
            return 3;
        }
        if (feature.label == kTriSelfNegative) {
            if (subject_text != object_text) {
                std::cerr << "line " << line_no
                          << ": self_negative roles differ\n";
                return 3;
            }
        }
        // Non-self rows may share role text when two distinct synsets have the
        // same first lemma.  The synset IDs live in provenance; the trainer
        // must not reject a legitimate homonym relation on text equality.
        std::vector<std::int32_t> subject_vector, predicate_vector,
            object_vector;
        if (!tri_encode_role(vm, subject_text, role_cache, subject_vector,
                             shard) ||
            !tri_encode_role(vm, predicate_text, role_cache, predicate_vector,
                             shard) ||
            !tri_encode_role(vm, object_text, role_cache, object_vector,
                             shard)) {
            std::cerr << "line " << line_no
                      << ": role phase encoding failed: " << vm.error() << "\n";
            return 7;
        }
        std::vector<std::int32_t> triangle;
        triangle.reserve(kTriComponents);
        triangle.insert(triangle.end(), subject_vector.begin(),
                        subject_vector.end());
        triangle.insert(triangle.end(), predicate_vector.begin(),
                        predicate_vector.end());
        triangle.insert(triangle.end(), object_vector.begin(),
                        object_vector.end());
        if (triangle.size() != kTriComponents) {
            std::cerr << "line " << line_no << ": role vector size mismatch\n";
            return 7;
        }
        if (!vm.triangle_geometry(triangle, kTriDim, feature.sides,
                                  feature.area, feature.tightness,
                                  feature.orientation)) {
            std::cerr << "line " << line_no
                      << ": triangle geometry failed: " << vm.error() << "\n";
            return 7;
        }
        ++split_counts[static_cast<std::size_t>(feature.split)];
        ++label_counts[static_cast<std::size_t>(feature.label)];
        ++relation_counts[feature.relation];
        features.push_back(feature);
        if (features.size() % 100000 == 0)
            std::cerr << "parsed " << features.size() << " rows\n";
    }
    if (features.empty()) {
        std::cerr << "no rows parsed\n";
        return 3;
    }

    std::array<TriBank, kTriRelationCount> relation_banks{};
    std::array<bool, kTriRelationCount> relation_trained{};
    std::array<std::size_t, kTriRelationCount> relation_train_positive{};
    std::array<std::size_t, kTriRelationCount> relation_train_negative{};
    for (std::size_t r = 0; r < kTriRelationCount; ++r) {
        if (!vm.triangle_model_reset()) {
            std::cerr << "triangle reset failed: " << vm.error() << "\n";
            return 7;
        }
        std::size_t positive = 0, negative = 0;
        for (const TriFeature& feature : features) {
            if (feature.split != kTriTrain || feature.relation != r) continue;
            std::int32_t count = 0;
            if (tri_positive_label(feature.label)) {
                if (!vm.triangle_model_observe(feature.sides, feature.area,
                                               feature.tightness,
                                               feature.orientation, count)) {
                    std::cerr << "positive observe failed: " << vm.error()
                              << "\n";
                    return 7;
                }
                ++positive;
            } else {
                if (!vm.triangle_model_observe_negative(
                        feature.sides, feature.area, feature.tightness,
                        feature.orientation, count)) {
                    std::cerr << "negative observe failed: " << vm.error()
                              << "\n";
                    return 7;
                }
                ++negative;
            }
        }
        relation_train_positive[r] = positive;
        relation_train_negative[r] = negative;
        relation_trained[r] = positive > 0 && negative > 0;
        tri_read_bank(vm, relation_banks[r]);
        for (TriFeature& feature : features) {
            if (feature.relation != r) continue;
            if (!vm.triangle_model_score_contrastive(
                    feature.sides, feature.area, feature.tightness,
                    feature.score) ||
                !vm.triangle_model_score(feature.sides, feature.area,
                                         feature.tightness,
                                         feature.shape_score)) {
                std::cerr << "relation score failed: " << vm.error() << "\n";
                return 7;
            }
        }
        std::cerr << "trained relation " << kTriRelationNames[r]
                  << " pos=" << positive << " neg=" << negative << "\n";
    }

    TriBank global_bank;
    if (!vm.triangle_model_reset()) {
        std::cerr << "triangle reset failed: " << vm.error() << "\n";
        return 7;
    }
    std::size_t global_positive = 0, global_negative = 0;
    for (const TriFeature& feature : features) {
        if (feature.split != kTriTrain) continue;
        std::int32_t count = 0;
        if (tri_positive_label(feature.label)) {
            if (!vm.triangle_model_observe(feature.sides, feature.area,
                                           feature.tightness,
                                           feature.orientation, count)) {
                std::cerr << "global positive observe failed: " << vm.error()
                          << "\n";
                return 7;
            }
            ++global_positive;
        } else {
            if (!vm.triangle_model_observe_negative(
                    feature.sides, feature.area, feature.tightness,
                    feature.orientation, count)) {
                std::cerr << "global negative observe failed: " << vm.error()
                          << "\n";
                return 7;
            }
            ++global_negative;
        }
    }
    tri_read_bank(vm, global_bank);
    for (TriFeature& feature : features) {
        if (!vm.triangle_model_score_contrastive(
                feature.sides, feature.area, feature.tightness,
                feature.global_score) ||
            !vm.triangle_model_score(feature.sides, feature.area,
                                     feature.tightness,
                                     feature.global_shape_score)) {
            std::cerr << "global score failed: " << vm.error() << "\n";
            return 7;
        }
    }

    const std::filesystem::path prefix_path(prefix);
    if (prefix_path.has_parent_path())
        std::filesystem::create_directories(prefix_path.parent_path());

    std::array<std::vector<const TriFeature*>, kTriRelationCount> valid_rows,
        test_rows;
    for (const TriFeature& feature : features) {
        if (feature.split == kTriValid)
            valid_rows[feature.relation].push_back(&feature);
        else if (feature.split == kTriTest)
            test_rows[feature.relation].push_back(&feature);
    }
    auto relation_score = [](const TriFeature& feature) {
        return feature.score;
    };
    auto global_score = [](const TriFeature& feature) {
        return feature.global_score;
    };
    std::array<std::int32_t, kTriRelationCount> relation_thresholds{};
    std::array<TriMetrics, kTriRelationCount> relation_valid_metrics{};
    std::array<TriMetrics, kTriRelationCount> relation_test_metrics{};
    for (std::size_t r = 0; r < kTriRelationCount; ++r) {
        relation_thresholds[r] =
            tri_select_threshold(valid_rows[r], relation_score);
        relation_valid_metrics[r] = tri_evaluate(
            valid_rows[r], relation_score, relation_thresholds[r]);
        relation_test_metrics[r] = tri_evaluate(
            test_rows[r], relation_score, relation_thresholds[r]);
    }
    std::vector<const TriFeature*> global_valid, global_test;
    for (const TriFeature& feature : features) {
        if (feature.split == kTriValid) global_valid.push_back(&feature);
        else if (feature.split == kTriTest) global_test.push_back(&feature);
    }
    const std::int32_t global_threshold =
        tri_select_threshold(global_valid, global_score);
    const TriMetrics global_valid_metrics =
        tri_evaluate(global_valid, global_score, global_threshold);
    const TriMetrics global_test_metrics =
        tri_evaluate(global_test, global_score, global_threshold);

    {
        std::ofstream scores(prefix + ".scores.tsv", std::ios::binary);
        if (!scores) {
            std::cerr << "cannot write scores\n";
            return 4;
        }
        scores << "split\trelation\tlabel\tconfidence\trelation_trained\t"
                  "score\tglobal_score\tshape_score\tglobal_shape_score\t"
                  "side0\tside1\tside2\tarea\ttightness\torientation\t"
                  "provenance\n";
        std::ifstream replay(records_path, std::ios::binary);
        std::string replay_header;
        std::getline(replay, replay_header);
        std::size_t index = 0;
        std::string replay_line;
        while (std::getline(replay, replay_line) && index < features.size()) {
            if (!replay_line.empty() && replay_line.back() == '\r')
                replay_line.pop_back();
            if (replay_line.empty()) continue;
            const std::vector<std::string> fields =
                tri_split_tabs(replay_line);
            if (fields.size() != 9) {
                std::cerr << "replay field mismatch\n";
                return 4;
            }
            const TriFeature& feature = features[index++];
            scores << kTriSplitNames[static_cast<std::size_t>(feature.split)]
                   << '\t' << kTriRelationNames[feature.relation] << '\t'
                   << kTriLabelNames[static_cast<std::size_t>(feature.label)]
                   << '\t' << feature.confidence << '\t'
                   << (relation_trained[feature.relation] ? 1 : 0) << '\t'
                   << feature.score << '\t' << feature.global_score << '\t'
                   << feature.shape_score << '\t'
                   << feature.global_shape_score << '\t' << feature.sides[0]
                   << '\t' << feature.sides[1] << '\t' << feature.sides[2]
                   << '\t' << feature.area << '\t' << feature.tightness
                   << '\t' << feature.orientation << '\t' << fields[8]
                   << '\n';
        }
        if (index != features.size()) {
            std::cerr << "replay row count mismatch\n";
            return 4;
        }
    }

    {
        std::ofstream banks(prefix + ".banks.tsv", std::ios::binary);
        if (!banks) {
            std::cerr << "cannot write banks\n";
            return 4;
        }
        banks << "model\tpos_tight_sum\tpos_area_sum\tpos_count\t"
                 "pos_orient_positive\tpos_orient_negative\t"
                 "neg_tight_sum\tneg_area_sum\tneg_count\t"
                 "neg_orient_positive\tneg_orient_negative\n";
        for (std::size_t r = 0; r < kTriRelationCount; ++r) {
            const TriBank& bank = relation_banks[r];
            banks << kTriRelationNames[r] << '\t'
                  << bank.positive_shape[0] << '\t'
                  << bank.positive_shape[1] << '\t'
                  << bank.positive_shape[2] << '\t'
                  << bank.positive_orientation[0] << '\t'
                  << bank.positive_orientation[1] << '\t'
                  << bank.negative_shape[0] << '\t'
                  << bank.negative_shape[1] << '\t'
                  << bank.negative_shape[2] << '\t'
                  << bank.negative_orientation[0] << '\t'
                  << bank.negative_orientation[1] << '\n';
        }
        banks << "global\t" << global_bank.positive_shape[0] << '\t'
              << global_bank.positive_shape[1] << '\t'
              << global_bank.positive_shape[2] << '\t'
              << global_bank.positive_orientation[0] << '\t'
              << global_bank.positive_orientation[1] << '\t'
              << global_bank.negative_shape[0] << '\t'
              << global_bank.negative_shape[1] << '\t'
              << global_bank.negative_shape[2] << '\t'
              << global_bank.negative_orientation[0] << '\t'
              << global_bank.negative_orientation[1] << '\n';
    }

    {
        std::ofstream metrics(prefix + ".metrics.json", std::ios::binary);
        if (!metrics) {
            std::cerr << "cannot write metrics\n";
            return 4;
        }
        metrics << "{\n"
                << "  \"schema\": \"nanlm.triangle-contrast-metrics/1\",\n"
                << "  \"records\": \"" << tri_json_escape(records_path)
                << "\",\n"
                << "  \"records_sha256\": \"" << tri_file_sha256(records_path)
                << "\",\n"
                << "  \"rows\": " << features.size() << ",\n"
                << "  \"splits\": {\"train\": " << split_counts[0]
                << ", \"valid\": " << split_counts[1]
                << ", \"test\": " << split_counts[2] << "},\n"
                << "  \"labels\": {\"positive\": " << label_counts[0]
                << ", \"inverse\": " << label_counts[1]
                << ", \"hard_negative\": " << label_counts[2]
                << ", \"negative\": " << label_counts[3]
                << ", \"self_negative\": " << label_counts[4] << "},\n"
                << "  \"relations\": {\"ISA\": " << relation_counts[0]
                << ", \"HAS_SUBTYPE\": " << relation_counts[1]
                << ", \"PART_OF\": " << relation_counts[2]
                << ", \"HAS_PART\": " << relation_counts[3]
                << ", \"CONTRADICTS\": " << relation_counts[4]
                << ", \"ASSOCIATED\": " << relation_counts[5] << "},\n"
                << "  \"per_relation\": {\n";
        for (std::size_t r = 0; r < kTriRelationCount; ++r) {
            const std::size_t train_rows =
                relation_train_positive[r] + relation_train_negative[r];
            metrics << "    \"" << kTriRelationNames[r] << "\": {\n"
                    << "      \"train_rows\": " << train_rows << ",\n"
                    << "      \"train_positive\": "
                    << relation_train_positive[r] << ",\n"
                    << "      \"train_negative\": "
                    << relation_train_negative[r] << ",\n"
                    << "      \"valid_rows\": " << valid_rows[r].size()
                    << ",\n"
                    << "      \"test_rows\": " << test_rows[r].size()
                    << ",\n"
                    << "      \"trained\": "
                    << (relation_trained[r] ? "true" : "false") << ",\n"
                    << "      \"bank\": ";
            tri_write_bank(metrics, relation_banks[r]);
            metrics << ",\n      \"threshold\": " << relation_thresholds[r]
                    << ",\n      \"valid\": ";
            tri_write_metrics(metrics, relation_valid_metrics[r]);
            metrics << ",\n      \"test\": ";
            tri_write_metrics(metrics, relation_test_metrics[r]);
            metrics << "\n    }"
                    << (r + 1 < kTriRelationCount ? "," : "") << "\n";
        }
        metrics << "  },\n"
                << "  \"global\": {\n"
                << "    \"train_positive\": " << global_positive << ",\n"
                << "    \"train_negative\": " << global_negative << ",\n"
                << "    \"trained\": "
                << ((global_positive > 0 && global_negative > 0) ? "true"
                                                                  : "false")
                << ",\n"
                << "    \"bank\": ";
        tri_write_bank(metrics, global_bank);
        metrics << ",\n    \"threshold\": " << global_threshold
                << ",\n    \"valid\": ";
        tri_write_metrics(metrics, global_valid_metrics);
        metrics << ",\n    \"test\": ";
        tri_write_metrics(metrics, global_test_metrics);
        metrics << "\n  },\n"
                << "  \"notes\": [\n"
                << "    \"raw scores are shape-bank contrastive scores, not calibrated probabilities\",\n"
                << "    \"threshold is selected on valid by balanced accuracy; test metrics are held out\",\n"
                << "    \"per-relation banks are sequential snapshots; the global bank is the production model\",\n"
                << "    \"train scores are in-sample diagnostics and must not be used for calibration\"\n"
                << "  ]\n"
                << "}\n";
    }

    std::cout << "triangle_contrast_train rows=" << features.size()
              << " valid=" << global_valid.size() << " test=" << global_test.size()
              << " global_threshold=" << global_threshold
              << " global_test_auc=" << std::fixed << std::setprecision(6)
              << global_test_metrics.auc
              << " global_test_balanced_accuracy="
              << global_test_metrics.balanced_accuracy
              << " prefix=" << prefix << "\n";
    return 0;
}

} // namespace nanlm
