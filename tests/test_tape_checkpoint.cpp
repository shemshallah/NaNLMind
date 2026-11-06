#include "nanlm/tape_checkpoint.hpp"
#include "nanlm/universal_tm.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    const std::vector<TmTransition> binary{
        {0, 1, 0, -1, 0, false},
        {0, 0, 1, 0, 0, true},
        {0, 2, 1, 0, 0, true},
    };
    Universe u(0x54415045);
    UniversalTuringMachine utm(u);
    Atlas atlas;
    utm.tape_store().attach_atlas(atlas);
    CHECK(utm.load_machine(binary, "1011", 3));
    utm.run(100);
    CHECK(atlas.page_count() >= 2u);
    const TapeCheckpoint cp = TapeCheckpointManager::make(utm.tape_store());
    CHECK_EQ(cp.page_hashes.size(), cp.page_keys.size());
    CHECK(cp.pages > 0u);

    GlobalTopology g;
    CHECK(TapeCheckpointManager::commit(g, cp, 7, 42));
    std::string err;
    CHECK(g.journals().verify(&err));
    CHECK_EQ(g.journals().size(), 1u + cp.page_keys.size());
    CHECK_EQ(TapeCheckpointManager::page_records(g, cp), cp.page_keys.size());
    const auto index = TapeCheckpointManager::load_index(g, cp);
    CHECK(index.has_value());
    if (index) {
        CHECK(index->pages.size() == cp.page_keys.size());
        for (std::size_t i = 0; i < cp.page_keys.size(); ++i) {
            CHECK(index->pages.at(cp.page_keys[i]) == cp.page_hashes[i]);
        }
    }
    CHECK(g.journals().ordered().front().subject == cp.root);

    // A fresh interpreter can restore the exact tape bytes.
    Universe u2(0x54415045);
    UniversalTuringMachine resumed(u2);
    CHECK(resumed.load_machine(binary, "", 0));
    const auto tape = utm.serialize_tape();
    CHECK(resumed.restore_tape(tape.data(), tape.size()));
    CHECK_EQ(resumed.tape(0, 4), std::string("1100"));
    CHECK(TapeCheckpointManager::make(resumed.tape_store()).root == cp.root);

    return test_done("tape page checkpoint committed to sharded journal");
}
