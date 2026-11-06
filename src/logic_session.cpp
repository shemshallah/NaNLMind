#include "nanlm/logic_session.hpp"

#include "nanlm/context2.hpp"
#include "nanlm/head_gate.hpp"
#include "nanlm/word_memory.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace nanlm {
namespace {
void record(LogicStageResult& stage, bool ok) {
    ++stage.total;
    if (ok) ++stage.correct;
    stage.accuracy = stage.total
        ? static_cast<double>(stage.correct) / static_cast<double>(stage.total)
        : 0.0;
}

bool gate_bit(HeadGate& gate, std::uint32_t a, std::uint32_t b) {
    return (gate.apply(a, b) & 1u) != 0;
}
} // namespace

LogicSessionResult LogicSessionTrainer::run(int boolean_repetitions,
                                            int circuit_repetitions) {
    LogicSessionResult result;
    result.stages.push_back(train_boolean_basis(boolean_repetitions));
    if (!result.stages.back().passed) {
        result.ok = false;
        return result;
    }
    result.stages.push_back(train_deep_circuits(circuit_repetitions));
    if (!result.stages.back().passed) {
        result.ok = false;
        return result;
    }
    result.stages.push_back(train_words_after_logic());
    result.ok = result.stages.back().passed;
    return result;
}

LogicStageResult LogicSessionTrainer::train_boolean_basis(int repetitions) {
    LogicStageResult stage;
    stage.name = "boolean_foundation";
    for (std::uint16_t i = 0; i < HeadArray::size(); ++i) {
        HeadView head = heads_->at(static_cast<std::uint8_t>(i));
        const std::uint8_t target = static_cast<std::uint8_t>(i & 15u);
        head.reset_boolean_learner();
        for (int rep = 0; rep < repetitions; ++rep) {
            for (std::uint32_t a = 0; a < 2; ++a) {
                for (std::uint32_t b = 0; b < 2; ++b) {
                    const bool truth = ((target >> (2u * a + b)) & 1u) != 0;
                    head.train_boolean(a, b, truth);
                }
            }
        }
        for (std::uint32_t a = 0; a < 2; ++a) {
            for (std::uint32_t b = 0; b < 2; ++b) {
                const bool expected = ((target >> (2u * a + b)) & 1u) != 0;
                const bool got = (NanWord::eval_bool(head.boolean_rule(), a, b) & 1u) != 0;
                record(stage, got == expected);
            }
        }
    }
    stage.passed = stage.correct == stage.total;
    stage.detail = "256 heads x 4 truth-table rows";
    return stage;
}

LogicStageResult LogicSessionTrainer::train_deep_circuits(int repetitions) {
    LogicStageResult stage;
    stage.name = "deep_logic_circuits";
    HeadGate xor_gate(*heads_, 0);
    HeadGate and_gate(*heads_, 1);
    HeadGate or_gate(*heads_, 2);
    HeadGate not_gate(*heads_, 3);
    xor_gate.train(6, repetitions);
    and_gate.train(8, repetitions);
    or_gate.train(14, repetitions);
    not_gate.train(3, repetitions);

    // Half adder.
    for (std::uint32_t a = 0; a < 2; ++a) {
        for (std::uint32_t b = 0; b < 2; ++b) {
            const bool sum = gate_bit(xor_gate, a, b);
            const bool carry = gate_bit(and_gate, a, b);
            record(stage, sum == ((a ^ b) != 0) && carry == ((a & b) != 0));
        }
    }
    // Full adder.
    for (std::uint32_t a = 0; a < 2; ++a) {
        for (std::uint32_t b = 0; b < 2; ++b) {
            for (std::uint32_t c = 0; c < 2; ++c) {
                const bool s1 = gate_bit(xor_gate, a, b);
                const bool sum = gate_bit(xor_gate, s1 ? 1 : 0, c);
                const bool c1 = gate_bit(and_gate, a, b);
                const bool c2 = gate_bit(and_gate, s1 ? 1 : 0, c);
                const bool carry = gate_bit(or_gate, c1 ? 1 : 0, c2 ? 1 : 0);
                const unsigned value = a + b + c;
                record(stage, sum == ((value & 1u) != 0) && carry == (value >= 2));
            }
        }
    }
    // Majority of three.
    for (std::uint32_t a = 0; a < 2; ++a) {
        for (std::uint32_t b = 0; b < 2; ++b) {
            for (std::uint32_t c = 0; c < 2; ++c) {
                const bool ab = gate_bit(and_gate, a, b);
                const bool bc = gate_bit(and_gate, b, c);
                const bool ac = gate_bit(and_gate, a, c);
                const bool left = gate_bit(or_gate, ab ? 1 : 0, bc ? 1 : 0);
                const bool majority = gate_bit(or_gate, left ? 1 : 0, ac ? 1 : 0);
                const bool expected = (a + b + c) >= 2;
                record(stage, majority == expected);
            }
        }
    }
    // Multiplexer: select ? b : a.
    for (std::uint32_t a = 0; a < 2; ++a) {
        for (std::uint32_t b = 0; b < 2; ++b) {
            for (std::uint32_t select = 0; select < 2; ++select) {
                const bool not_select = gate_bit(not_gate, select, select);
                const bool lo = gate_bit(and_gate, a, not_select ? 1 : 0);
                const bool hi = gate_bit(and_gate, b, select);
                const bool out = gate_bit(or_gate, lo ? 1 : 0, hi ? 1 : 0);
                const bool expected = (select ? b : a) != 0;
                record(stage, out == expected);
            }
        }
    }
    // Deep chain: eight alternating AND/XOR stages on the same two lanes.
    for (std::uint32_t a = 0; a < 2; ++a) {
        for (std::uint32_t b = 0; b < 2; ++b) {
            std::uint32_t value = a;
            for (int depth = 0; depth < 8; ++depth) {
                value = (depth & 1)
                    ? and_gate.apply(value, b)
                    : xor_gate.apply(value, b);
                value &= 1u;
            }
            std::uint32_t expected = a;
            for (int depth = 0; depth < 8; ++depth) {
                expected = (depth & 1) ? (expected & b) : (expected ^ b);
                expected &= 1u;
            }
            record(stage, value == expected);
        }
    }
    stage.passed = stage.correct == stage.total;
    stage.detail = "half/full adder, majority, mux, depth-8 chain";
    return stage;
}

LogicStageResult LogicSessionTrainer::train_words_after_logic() {
    LogicStageResult stage;
    stage.name = "words_after_logic";
    const std::string corpus =
        "robin is a bird. sparrow is a bird. eagle is a bird. "
        "penguin is a bird. penguin cannot fly. penguin can swim. "
        "ostrich is a bird. ostrich cannot fly. ostrich can run. "
        "emperor is a penguin. king is a penguin. "
        "bird can fly. fish can swim. fish cannot fly. salmon is a fish. "
        "shark is a fish. trout is a fish. cod is a fish. "
        "can robin fly? answer robin yes. "
        "can sparrow fly? answer sparrow yes. "
        "can penguin fly? answer penguin no. "
        "can penguin swim? answer penguin yes. "
        "can penguin run? answer penguin no. "
        "can ostrich fly? answer ostrich no. "
        "can ostrich run? answer ostrich yes. "
        "can emperor fly? answer emperor no. "
        "can emperor swim? answer emperor yes. "
        "can king fly? answer king no. "
        "can king swim? answer king yes. "
        "can salmon swim? answer salmon yes. "
        "can salmon fly? answer salmon no. ";
    BinStore store;
    WordMemory words(store);
    if (!words.build(corpus)) {
        stage.detail = "word memory build failed";
        return stage;
    }
    struct Case { const char* entity; const char* ability; bool yes; };
    const Case cases[] = {
        {"emperor", "fly", false}, {"emperor", "swim", true},
        {"king", "fly", false}, {"king", "swim", true},
        {"penguin", "fly", false}, {"penguin", "swim", true},
        {"ostrich", "run", true}, {"ostrich", "fly", false},
        {"sparrow", "fly", true}, {"salmon", "fly", false},
    };
    for (const auto& c : cases) {
        const auto answer = words.answer(c.entity, c.ability);
        record(stage, answer.has_value() && *answer == c.yes);
    }
    stage.passed = stage.correct == stage.total;
    stage.detail = "held-out entity/ability word queries";

    // Diagnostic only: byte completion is measured, not used to promote.
    Context2Model completion;
    const std::vector<std::uint8_t> data(corpus.begin(), corpus.end());
    completion.train(data);
    const Context2Eval eval = completion.evaluate(data, 2, data.size());
    stage.detail += " | byte_completion_top1=" + std::to_string(eval.accuracy);
    return stage;
}

} // namespace nanlm
