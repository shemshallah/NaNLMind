#pragma once

#include "nanlm/head.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {

struct LogicStageResult {
    std::string name;
    bool passed = false;
    std::size_t correct = 0;
    std::size_t total = 0;
    std::size_t distinct_rules = 0;
    std::size_t failed_heads = 0;
    double accuracy = 0.0;
    std::string detail;
};

struct LogicSessionResult {
    bool ok = false;
    std::vector<LogicStageResult> stages;
};

class LogicSessionTrainer {
public:
    explicit LogicSessionTrainer(HeadArray& heads) : heads_(&heads) {}

    LogicSessionResult run(int boolean_repetitions = 32,
                           int circuit_repetitions = 64);

private:
    LogicStageResult train_boolean_basis(int repetitions);
    LogicStageResult train_deep_circuits(int repetitions);
    LogicStageResult train_words_after_logic();

    HeadArray* heads_;
};

} // namespace nanlm
