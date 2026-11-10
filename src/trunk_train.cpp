#include "nanlm/trunk_train.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
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
    std::size_t max_lines = 0, window = 8, dim = 64, max_windows = 0;
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
    if (!samples.empty()) {
        pipeline_dim = std::min<std::size_t>(dim * 2, 128);
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
    std::size_t max_lines = 0, window = 8, dim = 64, max_windows = 0;
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
            if (eval_arg.rfind("eval=", 0) == 0)
                eval_path = eval_arg.substr(5);
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
    const std::size_t pipeline_dim = std::min<std::size_t>(dim * 2, 128);
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

    const auto emit_metrics = [&](std::size_t step, bool final) -> bool {
        std::uint64_t eval_distance = 0;
        std::size_t probe_hits = 0;
        std::uint64_t probe_score_sum = 0;
        std::size_t probe_count = 0;
        std::uint32_t prev_eval_code = 0;
        bool have_prev_eval = false;
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
        const double train_mean = train_distance_count
            ? static_cast<double>(train_distance) /
                  static_cast<double>(train_distance_count)
            : 0.0;
        const double eval_mean = eval_count
            ? static_cast<double>(eval_distance) / static_cast<double>(eval_count)
            : 0.0;
        const double hit_rate = probe_count
            ? static_cast<double>(probe_hits) / static_cast<double>(probe_count)
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
                << ", \"eval_mean_l1_q16\": " << eval_mean
                << ", \"probe_hit_rate\": " << hit_rate
                << ", \"probe_mean_score_q16\": " << score_mean
                << ", \"leaf_verify_rate\": " << leaf_rate
                << ", \"leaf_mean_error_q16\": " << leaf_mean_error
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
                  << " eval_l1=" << eval_mean
                  << " probe_hit=" << hit_rate
                  << " leaf_verify=" << leaf_rate
                  << " field_hot=" << (hot.field_hot ? "true" : "false")
                  << (final ? " final=1\n" : "\n");
        return true;
    };

    constexpr std::size_t kTrainChunk = 64;
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
        if (!vm.pq_update(chunk_bank, count, pipeline_dim, codewords, 1,
                          codebook)) {
            std::cerr << "phase-train codebook update failed: " << vm.error() << "\n";
            return 7;
        }
        processed = start + count;
        ++step;
        if (!emit_metrics(step, false)) return 7;
    }
    if (!emit_metrics(step + 1, true)) return 7;
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
    std::size_t max_lines = 0, window = 8, dim = 64, codewords = 256;
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
    const std::size_t pipeline_dim = std::min<std::size_t>(dim * 2, 128);
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
        for (std::size_t start = 0; start < vectors.size(); start += kEncodeBatch) {
            const std::size_t count = std::min(kEncodeBatch, vectors.size() - start);
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

} // namespace nanlm

