#include "nan16_ptc.hpp"
#include "test_util.hpp"

int main() {
    nan16::Topology t;

    const auto cog = t.experiment_cognitive_suite();
    CHECK(cog.passed == cog.tests);
    const auto hard = t.experiment_hard_cognition();
    CHECK(hard.passed == hard.tests);
    const auto extreme = t.experiment_extreme_cognition();
    CHECK(extreme.passed == extreme.tests);
    const auto formal = t.experiment_formal_suite();
    CHECK(formal.passed == formal.tests);
    const auto puzzles = t.experiment_hard_puzzles();
    CHECK(puzzles.passed == puzzles.tests);
    const auto modal = t.experiment_modal_suite();
    CHECK(modal.passed == modal.tests);

    std::cout << "legacy suites: cog " << cog.passed << "/" << cog.tests
              << ", hard " << hard.passed << "/" << hard.tests
              << ", extreme " << extreme.passed << "/" << extreme.tests
              << ", formal " << formal.passed << "/" << formal.tests
              << ", puzzles " << puzzles.passed << "/" << puzzles.tests
              << ", modal " << modal.passed << "/" << modal.tests << "\n";
    return test_done("legacy logic and puzzle suites");
}
