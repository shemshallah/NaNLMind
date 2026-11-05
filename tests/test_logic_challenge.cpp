// Compositional inheritance challenge for the current byte structure.
//
// True facts only:
//   fish can swim; birds can fly;
//   penguin/ostrich/kiwi/emu/cassowary cannot fly.
//
// Training has balanced yes/no answers. Test entities appear in the facts but
// never in an answered question. The test is repeated with ten shuffled fact
// orders; the count model should be order-independent.
//
// This is deliberately not in `make test`: it is allowed to fail.
#include "nanlm/context2.hpp"
#include "test_util.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <random>
#include <string>
#include <vector>

using namespace nanlm;

namespace {

struct Case {
    const char* entity;
    const char* ability;
    bool expected_yes;
    bool exception_no;
};

const std::array<Case, 8> kCases{{
    {"sparrow", "fly", true, false},
    {"magpie", "fly", true, false},
    {"trout", "swim", true, false},
    {"cod", "swim", true, false},
    {"ostrich", "fly", false, true},
    {"kiwi", "fly", false, true},
    {"emu", "fly", false, true},
    {"cassowary", "fly", false, true},
}};

const std::array<const char*, 16> kFactLines{{
    "robin is a bird.",
    "eagle is a bird.",
    "penguin is a bird.",
    "penguin cannot fly.",
    "bird can fly.",
    "sparrow is a bird.",
    "magpie is a bird.",
    "ostrich is a bird.",
    "ostrich cannot fly.",
    "kiwi is a bird.",
    "kiwi cannot fly.",
    "emu is a bird.",
    "emu cannot fly.",
    "cassowary is a bird.",
    "cassowary cannot fly.",
    "salmon is a fish.",
}};

const std::array<const char*, 11> kMoreFacts{{
    "fish can swim.",
    "shark is a fish.",
    "trout is a fish.",
    "cod is a fish.",
    "carp is a fish.",
    "can robin fly? answer robin yes.",
    "can eagle fly? answer eagle yes.",
    "can penguin fly? answer penguin no.",
    "can ostrich fly? answer ostrich no.",
    "can salmon swim? answer salmon yes.",
    "can emu fly? answer emu no.",
}};

const std::array<const char*, 2> kTailFacts{{
    "can shark swim? answer shark yes.",
    "can kiwi fly? answer kiwi no.",
}};

std::string prompt_for(const Case& c) {
    return std::string("can ") + c.entity + " " + c.ability + "? answer " +
           c.entity + " ";
}

double answer_probability(const Context2Model& model, const std::string& prompt,
                          char answer) {
    const std::uint8_t a = static_cast<std::uint8_t>(prompt[prompt.size() - 2]);
    const std::uint8_t b = static_cast<std::uint8_t>(prompt[prompt.size() - 1]);
    return model.probability(a, b, static_cast<std::uint8_t>(answer));
}

struct Run {
    int seed = 0;
    std::size_t correct = 0;
    std::size_t yes_count = 0;
};

Run run_once(int seed, bool print_cases, std::size_t& symbolic_correct) {
    std::vector<std::string> lines;
    for (const char* f : kFactLines) lines.emplace_back(f);
    for (const char* f : kMoreFacts) lines.emplace_back(f);
    for (const char* f : kTailFacts) lines.emplace_back(f);
    std::mt19937 rng(static_cast<std::uint32_t>(seed));
    std::shuffle(lines.begin(), lines.end(), rng);
    std::string train;
    for (const auto& line : lines) {
        train += line;
        train += ' ';
    }

    Context2Model model;
    model.train(std::vector<std::uint8_t>(train.begin(), train.end()));

    Run run;
    run.seed = seed;
    symbolic_correct = 0;
    if (print_cases) {
        std::cout << "compositional inheritance challenge (fish + birds, "
                     "true facts)\n";
    }
    for (const Case& c : kCases) {
        const std::string prompt = prompt_for(c);
        const double py = answer_probability(model, prompt, 'y');
        const double pn = answer_probability(model, prompt, 'n');
        constexpr double kTie = 1e-12;
        const int predicted = (py > pn + kTie) ? 1 : (pn > py + kTie ? 0 : -1);
        const bool ok = predicted == (c.expected_yes ? 1 : 0);
        const bool symbolic_yes = !c.exception_no;
        const bool symbolic_ok = symbolic_yes == c.expected_yes;
        if (ok) ++run.correct;
        if (predicted == 1) ++run.yes_count;
        if (symbolic_ok) ++symbolic_correct;
        if (print_cases) {
            std::cout << "  " << c.entity << " " << c.ability
                      << " expected=" << (c.expected_yes ? "yes" : "no")
                      << " model="
                      << (predicted == 1 ? "yes" : predicted == 0 ? "no" : "uncertain")
                      << " p(yes)=" << py << " p(no)=" << pn
                      << " symbolic=" << (symbolic_ok ? "ok" : "wrong")
                      << " -> " << (ok ? "PASS" : "FAIL") << "\n";
        }
    }
    return run;
}

} // namespace

int main() {
    std::size_t symbolic_correct = 0;
    Run first = run_once(0, true, symbolic_correct);
    std::cout << "run seed=" << first.seed << " accuracy="
              << static_cast<double>(first.correct) / kCases.size()
              << " yes=" << first.yes_count << "/" << kCases.size() << "\n";
    bool all_same = true;
    for (int seed = 1; seed < 10; ++seed) {
        std::size_t ignored = 0;
        const Run r = run_once(seed, false, ignored);
        if (r.correct != first.correct || r.yes_count != first.yes_count) {
            all_same = false;
        }
        std::cout << "run seed=" << seed << " accuracy="
                  << static_cast<double>(r.correct) / kCases.size()
                  << " yes=" << r.yes_count << "/" << kCases.size() << "\n";
    }

    const double accuracy = static_cast<double>(first.correct) / kCases.size();
    const double symbolic_accuracy =
        static_cast<double>(symbolic_correct) / kCases.size();
    std::cout << "model accuracy=" << accuracy
              << " symbolic accuracy=" << symbolic_accuracy
              << " threshold=0.875 order_independent="
              << (all_same ? "yes" : "no") << "\n";

    if (accuracy >= 0.875) {
        std::cout << "PASS challenge (unexpected: the byte model generalized)\n";
        return 0;
    }
    std::cout << "FAIL challenge (this is the falsification result)\n";
    return 1;
}
