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
