#include "nanlm/head_gate.hpp"

namespace nanlm {

void HeadGate::train(std::uint8_t target, int repetitions) {
    head_.reset_boolean_learner();
    for (int rep = 0; rep < repetitions; ++rep) {
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                const bool truth = ((target >> (2u * a + b)) & 1u) != 0;
                head_.train_boolean(a, b, truth);
            }
        }
    }
}

} // namespace nanlm
