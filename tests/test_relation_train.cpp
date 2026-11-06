#include "nanlm/global.hpp"
#include "nanlm/relation_train.hpp"
#include "test_util.hpp"

#include <filesystem>
#include <fstream>
#include <string>

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
    CHECK(std::filesystem::is_file(state));
    std::ifstream in(state, std::ios::binary);
    std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(in)),
                                    std::istreambuf_iterator<char>());
    auto restored = GlobalTopology::from_bytes(bytes.data(), bytes.size());
    CHECK(restored != nullptr);
    if (restored) {
        CHECK_EQ(restored->hypergraph().size(), 5u);
        CHECK(restored->temporal().size() >= 15u);
        CHECK(restored->ledger().verify());
    }
    // Exact replay is idempotent: no duplicate relation hyperedges or head updates.
    CHECK_EQ(relation_train_cli(4, argv), 8);
    std::filesystem::remove_all(root);
    return test_done("resolution-aware native relation learning");
}
