#include "nanlm/training.hpp"

#include <algorithm>

namespace nanlm {
namespace {

Ref head_ref(std::uint8_t head) {
    return Ref::from_bit({PageId::root(), HeadAddress::from_index(head).value, 0, 0});
}

std::uint8_t ref_head(const Ref& ref) {
    const auto cell = static_cast<std::uint16_t>((ref.offset >> 8) & 0xFFFFu);
    return matrix_row(cell);
}

} // namespace

void UniverseTrainer::train_boolean(std::uint8_t head,
                                    const std::vector<BooleanSample>& samples,
                                    int epochs) {
    HeadView h = heads_->at(head);
    for (int e = 0; e < epochs; ++e) {
        for (const BooleanSample& s : samples) {
            h.train_boolean(s.a, s.b, s.target);
        }
    }
}

AccuracyReport UniverseTrainer::evaluate_boolean(
    std::uint8_t head, const std::vector<BooleanSample>& samples) const {
    AccuracyReport r;
    const HeadView h(const_cast<HeadArray&>(*heads_), head);
    for (const BooleanSample& s : samples) {
        ++r.total;
        const std::uint32_t pred =
            NanWord::eval_bool(h.boolean_rule(), s.a, s.b) & 1u;
        if ((pred != 0) == s.target) ++r.correct;
    }
    if (r.total) r.accuracy = static_cast<double>(r.correct) / static_cast<double>(r.total);
    return r;
}

void UniverseTrainer::train_sequence(const std::vector<std::uint8_t>& sequence,
                                     std::uint64_t epoch) {
    if (sequence.size() < 2) return;
    for (std::size_t i = 0; i + 1 < sequence.size(); ++i) {
        temporal_.link(head_ref(sequence[i]), head_ref(sequence[i + 1]), epoch,
                       kTemporalReversible);
    }
    // Close the loop if it is cyclic (first == last) or always? Keep it linear
    // by default; the caller can repeat the first element to close it.
}

std::vector<std::uint8_t> UniverseTrainer::recall_forward(std::uint8_t start,
                                                          int steps) const {
    std::vector<std::uint8_t> out;
    Ref cur = head_ref(start);
    for (int i = 0; i < steps; ++i) {
        Ref next;
        if (!temporal_.forward(cur, next)) break;
        out.push_back(ref_head(next));
        cur = next;
    }
    return out;
}

std::vector<std::uint8_t> UniverseTrainer::recall_reverse(std::uint8_t start,
                                                          int steps) const {
    std::vector<std::uint8_t> out;
    Ref cur = head_ref(start);
    for (int i = 0; i < steps; ++i) {
        Ref prev;
        if (!temporal_.backward(cur, prev)) break;
        out.push_back(ref_head(prev));
        cur = prev;
    }
    return out;
}

} // namespace nanlm
