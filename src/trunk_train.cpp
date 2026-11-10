#include "nanlm/trunk_train.hpp"
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
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
                     " [REPORT_EVERY] [BUCKETS] [CONTEXT_BYTES] [LR] [EVAL_EVERY] [TRAIN_FRACTION] [backoff|backoffcopy] [EXACT_BUCKETS] [fallback=N]\n"
                  << "Trains a raw context-indexed 16x16 class-memory readout.\n"
                  << "TRAIN_FRACTION <1 holds out a random evaluation split.\n"
                  << "backoff uses exact high-frequency 4-byte contexts plus a 3-byte fallback.\n"
                  << "backoffcopy routes unseen 3-byte contexts to a copy/unigram table.\n";
        return 2;
    }
    const std::string corpus_path = argv[2];
    std::size_t max_lines = 0, epochs = 3, report_every = 10000;
    std::size_t buckets = 8192, context_bytes = 3, eval_every = 1;
    float base_lr = 0.5f, train_fraction = 1.0f;
    bool backoff_mode = false;
    bool copy_backoff = false;
    std::size_t exact_limit_arg = 8192;
    std::size_t fallback_bytes = 3;
    std::string load_path;
    std::string save_path;
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
            backoff_mode = route == "backoff" || route == "backoffcopy";
            copy_backoff = route == "backoffcopy";
        }
        if (argc > 12) exact_limit_arg = static_cast<std::size_t>(std::stoull(argv[12]));
        for (int i = 13; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg.rfind("load=", 0) == 0) load_path = arg.substr(5);
            else if (arg.rfind("save=", 0) == 0) save_path = arg.substr(5);
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
    std::vector<std::uint32_t> context_buckets(usable.size());
    std::vector<std::uint8_t> targets(usable.size());
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
    std::vector<std::size_t> all_indices(usable.size());
    for (std::size_t i = 0; i < all_indices.size(); ++i) all_indices[i] = i;
    std::vector<std::size_t> train_indices;
    std::vector<std::size_t> eval_indices;
    if (train_fraction >= 1.0f) {
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
    if (backoff_mode) {
        if (buckets < 2) {
            std::cerr << "backoff requires at least 2 buckets\n";
            return 2;
        }
        const auto context_key = [](std::string_view line) {
            return (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[4])) << 24) |
                   (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[5])) << 16) |
                   (static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[6])) << 8) |
                   static_cast<std::uint32_t>(static_cast<std::uint8_t>(line[7]));
        };
        std::unordered_map<std::uint32_t, std::uint32_t> counts;
        for (const std::size_t sample : train_indices) {
            ++counts[context_key(usable[sample])];
        }
        std::vector<std::pair<std::uint32_t, std::uint32_t>> ranked;
        ranked.reserve(counts.size());
        for (const auto& entry : counts) ranked.emplace_back(entry.second, entry.first);
        std::sort(ranked.begin(), ranked.end(),
                  [](const auto& a, const auto& b) { return a.first > b.first; });
        const std::size_t exact_limit = std::min<std::size_t>(exact_limit_arg, buckets - 1);
        const std::size_t exact_count = std::min(exact_limit, ranked.size());
        std::unordered_map<std::uint32_t, std::uint32_t> exact;
        exact.reserve(exact_count * 2);
        for (std::size_t i = 0; i < exact_count; ++i) {
            exact.emplace(ranked[i].second, static_cast<std::uint32_t>(i));
        }
        const std::size_t fallback = buckets - exact_count;
        const std::size_t k3_fallback = copy_backoff && fallback > 1
            ? std::max<std::size_t>(1, (fallback * 3) / 4) : fallback;
        const std::size_t copy_fallback = fallback - k3_fallback;
        std::unordered_set<std::uint32_t> k3_seen;
        if (copy_backoff) {
            k3_seen.reserve(train_indices.size());
            for (const std::size_t sample : train_indices) {
                std::uint32_t key = 0;
                for (std::size_t j = 1; j <= 3; ++j) {
                    key = (key << 8) |
                        static_cast<std::uint8_t>(usable[sample][8 - j]);
                }
                k3_seen.insert(key);
            }
        }
        for (std::size_t sample = 0; sample < usable.size(); ++sample) {
            const auto key = context_key(usable[sample]);
            const auto it = exact.find(key);
            if (it != exact.end()) {
                context_buckets[sample] = it->second;
            } else {
                std::uint32_t hash = 2166136261u;
                const std::size_t fallback_width = fallback_bytes;
                for (std::size_t j = 1; j <= fallback_width; ++j) {
                    const auto byte = static_cast<std::uint8_t>(usable[sample][8 - j]);
                    hash = (hash ^ byte) * 16777619u;
                }
                if (copy_backoff && k3_seen.find(key & 0xFFFFFFu) != k3_seen.end()) {
                    std::uint32_t k3_hash = 2166136261u;
                    for (std::size_t j = 1; j <= 3; ++j) {
                        const auto byte = static_cast<std::uint8_t>(usable[sample][8 - j]);
                        k3_hash = (k3_hash ^ byte) * 16777619u;
                    }
                    context_buckets[sample] = static_cast<std::uint32_t>(exact_count) +
                        (k3_fallback ? k3_hash % k3_fallback : 0);
                } else if (copy_backoff && copy_fallback) {
                    std::uint32_t copy_hash = 2166136261u;
                    copy_hash = (copy_hash ^ static_cast<std::uint8_t>(usable[sample][7])) * 16777619u;
                    context_buckets[sample] = static_cast<std::uint32_t>(exact_count + k3_fallback) +
                        copy_hash % copy_fallback;
                } else {
                    context_buckets[sample] = static_cast<std::uint32_t>(exact_count) +
                        (fallback ? hash % fallback : 0);
                }
            }
        }
        std::cout << "context_backoff exact=" << exact_count
                  << " fallback=" << fallback
                  << " k3_fallback=" << k3_fallback
                  << " copy_fallback=" << copy_fallback
                  << " fallback_bytes=" << fallback_bytes << "\n";
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
            if (!vm.readout_context(targets[sample], 0.0f,
                                    context_buckets[sample], buckets,
                                    correct, loss, ph, pl)) {
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
            if (!vm.readout_context(targets[sample], base_lr,
                                    context_buckets[sample], buckets,
                                    correct, loss, ph, pl)) {
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

} // namespace nanlm
