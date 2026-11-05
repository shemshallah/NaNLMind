#include "nanlm/learning_mesh.hpp"

#include <algorithm>

namespace nanlm {

void OverbootstrapLearner::observe(const BootstrapTrace& trace) {
    ++traces_;
    for (std::uint8_t h : trace.active) {
        // Meta-state is count/evidence based, not a Hopfield key. Correct
        // activations gain evidence; wrong or abstained ones lose it.
        if (trace.correct) {
            ++correct_[h];
            evidence_[h] = std::min<std::int32_t>(1024, evidence_[h] + 1);
        } else {
            ++wrong_[h];
            evidence_[h] = std::max<std::int32_t>(-1024, evidence_[h] - 1);
        }
    }
}

std::array<std::int16_t, 256> OverbootstrapLearner::feedback() const {
    std::array<std::int16_t, 256> out{};
    for (std::size_t h = 0; h < out.size(); ++h) {
        // Bounded bias: enough to steer top-k, not enough to rewrite the
        // bootstrap's local association.
        out[h] = static_cast<std::int16_t>(std::clamp(evidence_[h] / 8, -8, 8));
    }
    return out;
}

std::int32_t OverbootstrapLearner::evidence(std::uint8_t head) const {
    return evidence_[head];
}

Hash256 OverbootstrapLearner::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'E', 'T', 'A', '0', '1'};
    h.update(tag, sizeof(tag));
    h.update(&traces_, sizeof(traces_));
    h.update(evidence_.data(), evidence_.size() * sizeof(std::int32_t));
    return h.final();
}

void HyperparameterLearner::observe(std::uint8_t used_top_k, bool correct) {
    if (used_top_k > 16) return;
    ++samples_;
    ++total_[used_top_k];
    if (correct) ++success_[used_top_k];
}

std::uint8_t HyperparameterLearner::best_top_k() const {
    std::uint8_t best = kCandidates.front();
    double best_rate = -1.0;
    for (std::uint8_t k : kCandidates) {
        if (total_[k] == 0) continue;
        const double rate = static_cast<double>(success_[k]) /
                            static_cast<double>(total_[k]);
        if (rate > best_rate ||
            (rate == best_rate && total_[k] > total_[best])) {
            best_rate = rate;
            best = k;
        }
    }
    return best;
}

std::int16_t HyperparameterLearner::bias_limit() const {
    const std::uint8_t k = best_top_k();
    if (total_[k] == 0) return 4;
    const double rate = static_cast<double>(success_[k]) /
                        static_cast<double>(total_[k]);
    if (rate >= 0.9) return 8;
    if (rate >= 0.7) return 4;
    if (rate >= 0.4) return 2;
    return 1;
}

Hash256 HyperparameterLearner::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'B', 'A', 'N', 'D', '1', ' '};
    h.update(tag, sizeof(tag));
    h.update(&samples_, sizeof(samples_));
    h.update(success_.data(), success_.size() * sizeof(std::uint64_t));
    h.update(total_.data(), total_.size() * sizeof(std::uint64_t));
    return h.final();
}

bool BootstrapMesh::step(const HopfieldRouter::Vector& query, std::uint32_t target) {
    const HopfieldPrediction pred = bootstrap_.predict(query);
    BootstrapTrace trace;
    trace.target = target;
    trace.correct = !pred.abstain && pred.token == target;
    const std::size_t n = std::min<std::size_t>(top_k_active_, pred.active.size());
    trace.active.assign(pred.active.begin(), pred.active.begin() + n);

    const bool learned = bootstrap_.learn(query, target);
    mind_.observe(trace);
    const auto feedback = mind_.feedback();
    for (std::size_t h = 0; h < feedback.size(); ++h) {
        bootstrap_.set_head_bias(static_cast<std::uint8_t>(h), feedback[h]);
    }
    return learned;
}

} // namespace nanlm
