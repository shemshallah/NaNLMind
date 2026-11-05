// Compositional inheritance challenge for the current byte structure.
//
// The training stream contains true bird facts and a few answered questions.
// The test entities appear in the facts but never in an answered question. A
// rule system can answer them by inheritance/exception; the order-2 byte model
// has to answer from local counts.
//
// This test is deliberately not in `make test`: it is allowed to fail. It is a
// falsification probe, not a gate that should be made green by weakening it.
#include "nanlm/context2.hpp"
#include "test_util.hpp"

#include <array>
#include <cctype>
#include <iostream>
#include <string>
#include <vector>

using namespace nanlm;

namespace {

struct Case {
    const char* entity;
    bool expected_yes;
    bool exception_no;
};

const std::array<Case, 8> kCases{{
    {"sparrow", true, false},
    {"ostrich", false, true},
    {"magpie", true, false},
    {"kiwi", false, true},
    {"falcon", true, false},
    {"emu", false, true},
    {"cassowary", false, true},
    {"swallow", true, false},
}};

std::string prompt_for(const Case& c) {
    return std::string("can ") + c.entity + " fly? answer " + c.entity + " ";
}

double answer_probability(const Context2Model& model, const std::string& prompt,
                          char answer) {
    const std::uint8_t a = static_cast<std::uint8_t>(prompt[prompt.size() - 2]);
    const std::uint8_t b = static_cast<std::uint8_t>(prompt[prompt.size() - 1]);
    return model.probability(a, b, static_cast<std::uint8_t>(answer));
}

} // namespace

int main() {
    std::string train =
        "robin is a bird. "
        "eagle is a bird. "
        "penguin is a bird. "
        "penguin cannot fly. "
        "bird can fly. "
        "sparrow is a bird. "
        "ostrich is a bird. "
        "ostrich cannot fly. "
        "magpie is a bird. "
        "kiwi is a bird. "
        "kiwi cannot fly. "
        "falcon is a bird. "
        "emu is a bird. "
        "emu cannot fly. "
        "cassowary is a bird. "
        "cassowary cannot fly. "
        "swallow is a bird. "
        "can robin fly? answer robin yes. "
        "can eagle fly? answer eagle yes. "
        "can penguin fly? answer penguin no. ";

    Context2Model model;
    model.train(std::vector<std::uint8_t>(train.begin(), train.end()));

    std::size_t correct = 0;
    std::size_t symbolic_correct = 0;
    std::cout << "compositional inheritance challenge (true bird facts)\n";
    for (const Case& c : kCases) {
        const std::string prompt = prompt_for(c);
        const double py = answer_probability(model, prompt, 'y');
        const double pn = answer_probability(model, prompt, 'n');
        const bool predicted_yes = py >= pn;
        const bool ok = predicted_yes == c.expected_yes;
        const bool symbolic_yes = !c.exception_no;
        const bool symbolic_ok = symbolic_yes == c.expected_yes;
        if (ok) ++correct;
        if (symbolic_ok) ++symbolic_correct;
        std::cout << "  " << c.entity
                  << " expected=" << (c.expected_yes ? "yes" : "no")
                  << " model=" << (predicted_yes ? "yes" : "no")
                  << " p(yes)=" << py << " p(no)=" << pn
                  << " symbolic=" << (symbolic_ok ? "ok" : "wrong")
                  << " -> " << (ok ? "PASS" : "FAIL") << "\n";
    }

    const double accuracy = static_cast<double>(correct) / kCases.size();
    const double symbolic_accuracy =
        static_cast<double>(symbolic_correct) / kCases.size();
    std::cout << "model accuracy=" << accuracy
              << " symbolic accuracy=" << symbolic_accuracy
              << " threshold=0.875\n";

    if (accuracy >= 0.875) {
        std::cout << "PASS challenge (unexpected: the byte model generalized)\n";
        return 0;
    }
    std::cout << "FAIL challenge (this is the falsification result)\n";
    return 1;
}
