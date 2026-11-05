#include "nanlm/head_gate.hpp"
#include "nanlm/hypervector.hpp"
#include "nanlm/learning_mesh.hpp"
#include "nanlm/word_memory.hpp"
#include "test_util.hpp"

#include <array>
#include <string>
#include <unordered_map>

using namespace nanlm;

namespace {
struct TinyTriples {
    std::unordered_map<std::string, std::unordered_map<std::string, std::string>> t;
    void add(const std::string& s, const std::string& p, const std::string& o) { t[s][p] = o; }
    bool has(const std::string& s, const std::string& p, const std::string& o) const {
        const auto a = t.find(s); if (a == t.end()) return false;
        const auto b = a->second.find(p); return b != a->second.end() && b->second == o;
    }
};
} // namespace

int main() {
    // Hopfield recalls the relation-qualified candidate.
    HopfieldConfig cfg; cfg.top_k = 1; cfg.max_strength = 32;
    BootstrapMesh mesh(cfg, 1);
    enum : std::uint8_t { K_CASSOWARY_CANNOT = 0, T_FLY = 1, T_BIRD = 2 };
    mesh.bootstrap().set_head(K_CASSOWARY_CANNOT,
        HopfieldRouter::token_code(K_CASSOWARY_CANNOT));
    mesh.bootstrap().set_head(T_FLY, HopfieldRouter::token_code(T_FLY));
    for (int i = 0; i < 10; ++i) {
        CHECK(mesh.step(HopfieldRouter::token_code(K_CASSOWARY_CANNOT), T_FLY));
    }
    const auto candidate = mesh.bootstrap().predict(
        HopfieldRouter::token_code(K_CASSOWARY_CANNOT));
    CHECK(!candidate.abstain);
    CHECK_EQ(candidate.token, static_cast<std::uint32_t>(T_FLY));

    // Learned Boolean gate applies bird AND NOT exception.
    auto u = std::make_unique<Universe>(0xCA55);
    HeadArray heads(*u, PageId::root());
    HeadGate gate(heads, 0);
    gate.train(0b0100); // bit 2 = a AND NOT b
    const std::uint32_t birds = 0x0000000F;
    const std::uint32_t exception = 0x0000000A; // penguin + ostrich
    CHECK_EQ(gate.apply(birds, exception), 0x00000005u);

    // Symbolic triple store and word layer grade the cassowary exception.
    TinyTriples kb;
    kb.add("cassowary", "isa", "bird");
    kb.add("bird", "can", "fly");
    kb.add("cassowary", "cannot", "fly");
    CHECK(kb.has("cassowary", "cannot", "fly"));
    CHECK(!kb.has("cassowary", "can", "fly"));

    BinStore store;
    WordMemory words(store);
    const std::string facts =
        "cassowary is a bird. bird can fly. cassowary cannot fly. "
        "penguin is a bird. penguin cannot fly. penguin can swim.";
    CHECK(words.build(facts));
    CHECK(!words.answer_yes("cassowary", "fly"));
    CHECK(words.answer_yes("penguin", "swim"));

    // Hypervector candidate store recalls the direct exception fact.
    HyperTripleStore hv;
    hv.add("cassowary", "cannot", "fly");
    hv.add("penguin", "cannot", "fly");
    CHECK_EQ(hv.query("cassowary", "cannot"), std::string("fly"));

    return test_done("teacher, Boolean gate, and triple-store grader");
}
