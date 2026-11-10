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

} // namespace nanlm
