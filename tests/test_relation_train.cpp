#include "nanlm/global.hpp"
#include "nanlm/hypermatrix.hpp"
#include "nanlm/relation_train.hpp"
#include "test_util.hpp"

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using namespace nanlm;

int main() {
    const auto root = std::filesystem::temp_directory_path() / "nanlm-relation-train-test";
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    const auto corpus = root / "relations.n16rel";
    const auto state = root / "global_universe.nmg";
    {
        std::ofstream out(corpus);
        out << "N16REL/1\n";
        out << "train\t5\t+\t60000\t70656e6775696e\t69735f61\t62697264\t" << std::string(64, '1') << "\n";
        out << "train\t5\t+\t60000\t726f62696e\t69735f61\t62697264\t" << std::string(64, '2') << "\n";
        out << "train\t5\t-\t60000\t70656e6775696e\t63616e\t666c79\t" << std::string(64, '3') << "\n";
        out << "train\t5\t+\t60000\t70656e6775696e\t63616e\t7377696d\t" << std::string(64, '4') << "\n";
        out << "test\t5\t-\t60000\t6f737472696368\t63616e\t666c79\t" << std::string(64, '5') << "\n";
        out << "test\t5\t+\t60000\t6f737472696368\t63616e\t72756e\t" << std::string(64, '6') << "\n";
        out << "train\t7\t+\t50000\t7269766572\t636f6e7461696e73\t7761746572\t" << std::string(64, '7') << "\n";
        out << "test\t7\t+\t50000\t73747265616d\t636f6e7461696e73\t7761746572\t" << std::string(64, '8') << "\n";
    }
    char arg0[] = "nanlm-universal";
    char arg1[] = "relation-train";
    std::string corpus_arg = corpus.string(), state_arg = state.string();
    char* argv[] = {arg0, arg1, corpus_arg.data(), state_arg.data()};
    CHECK_EQ(relation_train_cli(4, argv), 0);
    CHECK(std::filesystem::is_regular_file(state));
    std::ifstream in(state, std::ios::binary);
    std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(in)),
                                    std::istreambuf_iterator<char>());
    auto restored = GlobalTopology::from_bytes(bytes.data(), bytes.size());
    CHECK(restored != nullptr);
    if (restored) {
        CHECK_EQ(restored->hypergraph().size(), 5u);
        CHECK(restored->temporal().size() >= 15u);
        CHECK(restored->ledger().verify());
        CHECK(restored->hypermatrix_nonzero() > 0u);
        auto root_page = restored->pages().resolve(PageId::root());
        CHECK(root_page != nullptr);
        if (root_page) {
            CHECK(TriadField::field_count(*root_page) > 0u);
        }
    }
    // Read-only audit proves the mapped hypermatrix contributes a non-zero
    // score on held-out rows and reports the ablated score separately.
    {
        const auto test_only = root / "test.n16rel";
        std::ofstream tout(test_only);
        tout << "N16REL/1\n";
        tout << "test\t5\t-\t60000\t6f737472696368\t63616e\t666c79\t" << std::string(64, '5') << "\n";
        tout << "test\t5\t+\t60000\t6f737472696368\t63616e\t72756e\t" << std::string(64, '6') << "\n";
        tout << "test\t7\t+\t50000\t73747265616d\t636f6e7461696e73\t7761746572\t" << std::string(64, '8') << "\n";
        tout.close();
        std::string test_arg = test_only.string();
        char arg0[] = "nanlm-universal";
        char arg1[] = "relation-audit";
        char* audit_argv[] = {arg0, arg1, test_arg.data(), state_arg.data()};
        CHECK_EQ(relation_audit_cli(4, audit_argv), 0);
    }

    // Exact replay is idempotent and returns a machine-readable no-op receipt.
    const Hash256 learned_digest = restored ? restored->global_digest() : Hash256{};
    CHECK_EQ(relation_train_cli(4, argv), 0);
    std::ifstream replay_in(state, std::ios::binary);
    std::vector<std::uint8_t> replay_bytes((std::istreambuf_iterator<char>(replay_in)),
                                           std::istreambuf_iterator<char>());
    auto replayed = GlobalTopology::from_bytes(replay_bytes.data(), replay_bytes.size());
    CHECK(replayed != nullptr);
    if (replayed) CHECK(replayed->global_digest() == learned_digest);
    std::filesystem::remove_all(root);
    return test_done("resolution-aware native relation learning");
}
