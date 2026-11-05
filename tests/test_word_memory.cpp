#include "nanlm/word_memory.hpp"
#include "test_util.hpp"

#include <array>
#include <string>

using namespace nanlm;

int main() {
    const std::string corpus =
        "robin is a bird. eagle is a bird. penguin is a bird. "
        "penguin cannot fly. bird can fly. "
        "sparrow is a bird. magpie is a bird. ostrich is a bird. "
        "ostrich cannot fly. kiwi is a bird. kiwi cannot fly. "
        "emu is a bird. emu cannot fly. cassowary is a bird. "
        "cassowary cannot fly. emperor is a penguin. king is a penguin. "
        "penguin can swim. ostrich can run. salmon is a fish. fish can swim. "
        "shark is a fish. trout is a fish. cod is a fish. carp is a fish.";

    BinStore store;
    WordMemory words(store);
    CHECK(words.build(corpus));
    CHECK(words.vocab() > 0);
    CHECK(words.vector_dim() >= 64);
    CHECK(words.bin_id() != kInvalidBin);
    const BinHeader* vh = store.header(words.bin_id());
    CHECK(vh != nullptr);
    if (vh) CHECK_EQ(vh->dim, words.vector_dim());
    CHECK(words.associations() >= 20);

    CHECK(words.kind_of("sparrow").has_value());
    if (words.kind_of("sparrow")) CHECK_EQ(*words.kind_of("sparrow"), std::string("bird"));
    if (words.kind_of("trout")) CHECK_EQ(*words.kind_of("trout"), std::string("fish"));
    if (words.can_of("bird")) CHECK_EQ(*words.can_of("bird"), std::string("fly"));
    if (words.can_of("fish")) CHECK_EQ(*words.can_of("fish"), std::string("swim"));
    if (words.cannot_of("ostrich")) CHECK_EQ(*words.cannot_of("ostrich"), std::string("fly"));
    CHECK(!words.cannot_of("sparrow").has_value());
    CHECK(!words.kind_of("zorp").has_value());
    CHECK(words.kind_of("emperor").has_value());
    if (words.kind_of("emperor")) CHECK_EQ(*words.kind_of("emperor"), std::string("penguin"));
    CHECK(!words.answer_yes("cassowary", "fly")); // exception beats bird inheritance
    CHECK(!words.answer_yes("emperor", "fly"));
    CHECK(words.answer_yes("emperor", "swim"));
    CHECK(!words.answer_yes("king", "fly"));
    CHECK(words.answer_yes("king", "swim"));

    struct Case {
        const char* entity;
        const char* ability;
        bool expected;
    };
    const std::array<Case, 10> cases{{
        {"sparrow", "fly", true},
        {"magpie", "fly", true},
        {"trout", "swim", true},
        {"cod", "swim", true},
        {"ostrich", "fly", false},
        {"kiwi", "fly", false},
        {"emu", "fly", false},
        {"cassowary", "fly", false},
        {"emperor", "fly", false},
        {"emperor", "swim", true},
    }};
    std::size_t correct = 0;
    for (const Case& c : cases) {
        const bool got = words.answer_yes(c.entity, c.ability);
        if (got == c.expected) ++correct;
        CHECK_EQ(got, c.expected);
    }
    CHECK_EQ(correct, cases.size());

    const std::array<Case, 10> hard{{
        {"emperor", "fly", false},
        {"emperor", "swim", true},
        {"king", "fly", false},
        {"king", "swim", true},
        {"penguin", "fly", false},
        {"penguin", "swim", true},
        {"ostrich", "run", true},
        {"ostrich", "fly", false},
        {"sparrow", "fly", true},
        {"salmon", "fly", false},
    }};
    std::size_t hard_correct = 0;
    for (const Case& c : hard) {
        const bool got = words.answer_yes(c.entity, c.ability);
        if (got == c.expected) ++hard_correct;
        CHECK_EQ(got, c.expected);
    }
    CHECK_EQ(hard_correct, hard.size());

    // Unknown entities do not invent an answer.
    CHECK(!words.answer_yes("zorp", "fly"));
    CHECK(!words.answer_yes("sparrow", "swim"));

    // A second build from the same text produces a stable vocabulary and memory.
    BinStore store2;
    WordMemory words2(store2);
    CHECK(words2.build(corpus));
    CHECK_EQ(words2.vocab(), words.vocab());
    CHECK_EQ(words2.associations(), words.associations());

    return test_done("word-level relational memory");
}
