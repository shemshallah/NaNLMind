#include "nanlm/logic_session.hpp"
#include "test_util.hpp"

#include <memory>
#include <string>

using namespace nanlm;

int main() {
    auto u = std::make_unique<Universe>(0x4C4F474943303031ull);
    HeadArray heads(*u, PageId::root());
    LogicSessionTrainer trainer(heads);
    const LogicSessionResult result = trainer.run(2, 4);
    CHECK(result.ok);
    CHECK_EQ(result.stages.size(), 3u);
    if (result.stages.size() == 3u) {
        CHECK(result.stages[0].name == "boolean_foundation");
        CHECK_EQ(result.stages[0].correct, 1024u);
        CHECK_EQ(result.stages[0].total, 1024u);
        CHECK(result.stages[1].name == "deep_logic_circuits");
        CHECK_EQ(result.stages[1].correct, result.stages[1].total);
        CHECK(result.stages[2].name == "words_after_logic");
        CHECK_EQ(result.stages[2].correct, 10u);
        CHECK(result.stages[2].detail.find("byte_completion_top1=") != std::string::npos);
    }
    return test_done("staged Boolean -> deep logic -> word session");
}
