#include "nanlm/learning_mesh.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    HyperparameterLearner policy;
    for (int i = 0; i < 20; ++i) policy.observe(1, true);
    for (int i = 0; i < 20; ++i) policy.observe(8, false);
    CHECK_EQ(policy.best_top_k(), 1u);
    CHECK_EQ(policy.bias_limit(), 8);

    for (int i = 0; i < 50; ++i) policy.observe(4, true);
    CHECK_EQ(policy.best_top_k(), 4u);
    CHECK_EQ(policy.samples(), 90u);
    CHECK(policy.digest() == policy.digest());

    HyperparameterLearner empty;
    CHECK_EQ(empty.best_top_k(), 1u);
    CHECK_EQ(empty.bias_limit(), 4);

    return test_done("integer hyperparameter bandit");
}
