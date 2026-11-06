#include "nanlm/logic_session.hpp"
#include "test_util.hpp"

#include <memory>
#include <string>

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x4C4F474943303031ull);
    HeadArray heads(*u, PageId::root());
    LogicSessionTrainer trainer(heads);
    const LogicSessionResult result = trainer.run(32, 64);
    CHECK(result.ok);
    CHECK_EQ(result.stages.size(), 3u);
    if (result.stages.size() == 3u) {
        CHECK(result.stages[0].name == "boolean_foundation");
        CHECK_EQ(result.stages[0].correct, 1024u);
        CHECK_EQ(result.stages[0].total, 1024u);
        CHECK_EQ(result.stages[0].distinct_rules, 16u);
        CHECK_EQ(result.stages[0].failed_heads, 0u);
        CHECK(result.stages[1].name == "deep_logic_circuits");
        CHECK_EQ(result.stages[1].correct, result.stages[1].total);
        CHECK(result.stages[2].name == "words_after_logic");
        CHECK_EQ(result.stages[2].correct, 10u);
        CHECK(result.stages[2].detail.find("fixed_control_byte_heldout_top1=") != std::string::npos);
    }
    // A single observation per head cannot determine four truth-table rows.
    auto u2 = std::make_unique<Universe>(0x4C4F474943303032ull);
    HeadArray heads2(*u2, PageId::root());
    LogicSessionResult partial = LogicSessionTrainer(heads2).run(1, 1);
    CHECK(!partial.ok);
    CHECK(!partial.stages.empty() && !partial.stages[0].passed);
    CHECK(partial.stages[0].failed_heads > 0);
    return test_done("staged Boolean -> deep logic -> word session with failure path");
}
