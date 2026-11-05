#include "nanlm/global.hpp"
#include "nanlm/training.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    GlobalTopology g(0x1234);
    HeadArray heads = g.root_heads();
    UniverseTrainer trainer(heads);

    const std::vector<BooleanSample> xor_samples = {
        {0, 0, false}, {0, 1, true}, {1, 0, true}, {1, 1, false}};
    const std::vector<BooleanSample> and_samples = {
        {0, 0, false}, {0, 1, false}, {1, 0, false}, {1, 1, true}};
    const std::vector<BooleanSample> or_samples = {
        {0, 0, false}, {0, 1, true}, {1, 0, true}, {1, 1, true}};

    trainer.train_boolean(0, xor_samples, 100);
    trainer.train_boolean(1, and_samples, 100);
    trainer.train_boolean(2, or_samples, 100);

    const auto xor_acc = trainer.evaluate_boolean(0, xor_samples);
    const auto and_acc = trainer.evaluate_boolean(1, and_samples);
    const auto or_acc = trainer.evaluate_boolean(2, or_samples);
    CHECK_EQ(xor_acc.total, 4u);
    CHECK_EQ(xor_acc.correct, 4u);
    CHECK_EQ(and_acc.correct, 4u);
    CHECK_EQ(or_acc.correct, 4u);
    CHECK_EQ(heads.at(0).boolean_rule(), 6u); // XOR
    CHECK_EQ(heads.at(1).boolean_rule(), 8u); // AND
    CHECK_EQ(heads.at(2).boolean_rule(), 14u); // OR

    const std::vector<std::uint8_t> seq = {3, 7, 11, 19};
    trainer.train_sequence(seq, 1);
    const auto fwd = trainer.recall_forward(3, 3);
    CHECK_EQ(fwd.size(), 3u);
    if (fwd.size() == 3) {
        CHECK_EQ(fwd[0], 7u);
        CHECK_EQ(fwd[1], 11u);
        CHECK_EQ(fwd[2], 19u);
    }
    const auto rev = trainer.recall_reverse(19, 3);
    CHECK_EQ(rev.size(), 3u);
    if (rev.size() == 3) {
        CHECK_EQ(rev[0], 11u);
        CHECK_EQ(rev[1], 7u);
        CHECK_EQ(rev[2], 3u);
    }
    CHECK(heads.verify());

    return test_done("single-universe training task");
}
