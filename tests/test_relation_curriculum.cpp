#include "nanlm/learning_mesh.hpp"
#include "nanlm/word_memory.hpp"
#include "test_util.hpp"

#include <array>

using namespace nanlm;

namespace {

// Relation keys and value tokens. Keys are relation-qualified so a single
// entity can have isa/can/cannot/has associations without overwriting one key.
enum : std::uint8_t {
    K_PENGUIN_ISA = 0,
    K_EAGLE_ISA,
    K_BIRD_CAN,
    K_PENGUIN_CANNOT,
    K_PENGUIN_CAN,
    K_BIRD_HAS,
    K_OSTRICH_CANNOT,
    K_EMPEROR_ISA,
    T_BIRD = 32,
    T_FLY,
    T_SWIM,
    T_WINGS,
    T_RUN,
    T_PENGUIN,
};

struct Relation {
    std::uint8_t key;
    std::uint8_t value;
};

const std::array<Relation, 8> kRelations{{
    {K_PENGUIN_ISA, T_BIRD},
    {K_EAGLE_ISA, T_BIRD},
    {K_EMPEROR_ISA, T_PENGUIN}, // transitivity is resolved by the word layer
    {K_BIRD_CAN, T_FLY},
    {K_PENGUIN_CANNOT, T_FLY},
    {K_PENGUIN_CAN, T_SWIM},
    {K_BIRD_HAS, T_WINGS},
    {K_OSTRICH_CANNOT, T_FLY},
}};

} // namespace

int main() {
    HopfieldConfig cfg;
    cfg.top_k = 1;
    cfg.max_strength = 32;
    BootstrapMesh mesh(cfg, 1);
    for (std::uint16_t t = 0; t < 64; ++t) {
        mesh.bootstrap().set_head(static_cast<std::uint8_t>(t),
                                  HopfieldRouter::token_code(static_cast<std::uint8_t>(t)));
    }

    // Train relation-qualified keys. Repeated passes make the association
    // stable before the higher word/logic layer sees it.
    for (int epoch = 0; epoch < 10; ++epoch) {
        for (const auto& r : kRelations) {
            CHECK(mesh.step(HopfieldRouter::token_code(r.key), r.value));
        }
    }

    std::size_t correct = 0;
    for (const auto& r : kRelations) {
        const auto pred = mesh.bootstrap().predict(HopfieldRouter::token_code(r.key));
        if (!pred.abstain && pred.token == r.value) ++correct;
    }
    CHECK_EQ(correct, kRelations.size());
    CHECK_EQ(mesh.mind().traces(), 10u * kRelations.size());
    CHECK(mesh.mind().evidence(K_PENGUIN_CANNOT) != 0);

    // The word/logic layer consumes the same facts and resolves the
    // penguin exception and the nested emperor -> penguin -> bird chain.
    const std::string facts =
        "penguin is a bird. eagle is a bird. emperor is a penguin. "
        "bird can fly. penguin cannot fly. penguin can swim. "
        "bird has wings. ostrich is a bird. ostrich cannot fly.";
    BinStore store;
    WordMemory words(store);
    CHECK(words.build(facts));
    CHECK(!words.answer_yes("penguin", "fly"));
    CHECK(words.answer_yes("eagle", "fly"));
    CHECK(!words.answer_yes("emperor", "fly")); // inherited penguin exception
    CHECK(words.answer_yes("emperor", "swim")); // inherited penguin ability
    CHECK(words.answer_yes("bird", "fly"));

    return test_done("relation-first penguin curriculum");
}
