#include "nanlm/summary_bank_checkpoint.hpp"
#include "test_util.hpp"

#include <filesystem>
#include <fstream>
#include <vector>

using namespace nanlm;

namespace {
ChunkSummary summary(std::uint64_t id, unsigned head, float lane) {
    ChunkSummary s{};
    s.chunk_id = id;
    s.token_count = 256;
    s.heads = {head};
    std::array<float, 128> state{};
    state[0] = lane;
    state[127] = -lane;
    s.states = {state};
    return s;
}
} // namespace

int main() {
    const auto dir = std::filesystem::path("state") /
        "benchmarks" / "summary_bank_checkpoint_test";
    std::filesystem::remove_all(dir);
    {
        SummaryBank bank(512);
        for (unsigned i = 0; i < 512u; ++i)
            bank.append(summary(1000u + i, 3, static_cast<float>(i) / 512.0f));
        SummaryBankCheckpoint store(dir);
        store.write_bank(bank, 7);
        CHECK_EQ(store.record_count(), 512u);
        CHECK(store.record(511).present);
        CHECK(store.record(511).chunk_id == 1511u);
        CHECK_EQ(store.record(511).head_count, 1u);
        CHECK_EQ(store.root_digest().size(), 64u);
    }
    {
        SummaryBankCheckpoint store(dir);
        CHECK_EQ(store.record_count(), 512u);
        SummaryBank loaded(512);
        std::string error;
        CHECK(store.load(loaded, &error));
        CHECK(error.empty());
        CHECK_EQ(loaded.size(), 512u);
        CHECK_EQ(loaded.at(0).chunk_id, 1000u);
        CHECK_EQ(loaded.at(511).chunk_id, 1511u);
        CHECK(loaded.at(511).states[0][0] == 511.0f / 512.0f);
        CHECK(store.verify_all(&error));

        // Corrupt one record; verification and load must fail closed.
        auto path = store.record_path(7);
        std::fstream f(path, std::ios::in | std::ios::out | std::ios::binary);
        f.seekp(100);
        f.put('\x7F');
        f.close();
        CHECK(!store.verify_all(&error));
        SummaryBank bad(512);
        CHECK(!store.load(bad, &error));
    }
    std::filesystem::remove_all(dir);

    const auto malformed = std::filesystem::path("state") /
        "benchmarks" / "summary_bank_checkpoint_bad";
    std::filesystem::remove_all(malformed);
    std::filesystem::create_directories(malformed);
    std::ofstream(malformed / "manifest.txt") << "bad line\n";
    bool rejected = false;
    try {
        SummaryBankCheckpoint bad(malformed);
    } catch (const std::runtime_error&) {
        rejected = true;
    }
    CHECK(rejected);
    std::filesystem::remove_all(malformed);

    return test_done("persistent summary-bank checkpoint");
}
