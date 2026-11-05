#include "nanlm/global.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    GlobalTopology g(0x1234);
    const PageId root = PageId::root();
    const auto* entry = g.pages().entry(root);
    CHECK(entry != nullptr);
    const Hash256 base = entry->page->digest();

    ScratchJournal j;
    j.id = 1;
    j.epoch = 7;
    j.page = root;
    j.base = base;
    j.ops.push_back({ScratchKind::Chart, 0, 0, {1, 2, 3}});
    j.ops.push_back({ScratchKind::HeadLocal, 0, 0, {0xAA, 0xBB}});
    j.ops.push_back({ScratchKind::HeadWork, 0, 0, {0xCC}});

    const Hash256 before = g.global_digest();
    const ConsolidationResult r1 = g.consolidate(j, 1);
    CHECK(r1.ok);
    CHECK(!r1.duplicate);
    CHECK_EQ(r1.generation, 1u);
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.ledger().at(0).epoch, 7u);
    CHECK(g.ledger().verify());

    auto page = g.pages().resolve(root);
    CHECK(page != nullptr);
    if (page) {
        CHECK_EQ(page->chart_scratch()[0], 1u);
        CHECK_EQ(page->chart_scratch()[1], 2u);
        CHECK_EQ(page->chart_scratch()[2], 3u);
        CHECK_EQ(page->head_scratch(0).local()[0], 0xAAu);
        CHECK_EQ(page->head_scratch(0).local()[1], 0xBBu);
        CHECK_EQ(page->head_scratch(0).work()[0], 0xCCu);
        CHECK_EQ(page->head(0).scratch_used, 257u);
    }
    CHECK_EQ(g.manifest().generation, 1u);
    CHECK(g.manifest().root == g.pages().root_hash());
    CHECK(!(g.global_digest() == before));

    // Duplicate journal id is an idempotent no-op.
    const Hash256 after_commit = g.pages().entry(root)->page->digest();
    const ConsolidationResult r2 = g.consolidate(j, 1);
    CHECK(r2.ok);
    CHECK(r2.duplicate);
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.manifest().generation, 1u);
    CHECK(g.pages().entry(root)->page->digest() == after_commit);

    // Stale base is rejected without touching the page or the manifest.
    ScratchJournal stale;
    stale.id = 2;
    stale.page = root;
    stale.base = base;
    stale.ops.push_back({ScratchKind::Chart, 0, 20, {9}});
    const ConsolidationResult r3 = g.consolidate(stale, 1);
    CHECK(!r3.ok);
    CHECK(r3.error == "stale base hash");
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.manifest().generation, 1u);
    CHECK(g.pages().entry(root)->page->digest() == after_commit);

    // Out-of-range scratch aborts before any commit.
    ScratchJournal bad;
    bad.id = 3;
    bad.page = root;
    bad.base = after_commit;
    bad.ops.push_back({ScratchKind::HeadLocal, 0, 250, {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}});
    const ConsolidationResult r4 = g.consolidate(bad, 1);
    CHECK(!r4.ok);
    CHECK(r4.error.find("out of range") != std::string::npos);
    CHECK_EQ(g.ledger().size(), 1u);
    CHECK_EQ(g.manifest().generation, 1u);
    CHECK(g.pages().entry(root)->page->digest() == after_commit);

    // A valid second consolidation flips the manifest again.
    ScratchJournal j2;
    j2.id = 4;
    j2.epoch = 8;
    j2.page = root;
    j2.base = after_commit;
    j2.ops.push_back({ScratchKind::Chart, 0, 10, {7, 8, 9}});
    const ConsolidationResult r5 = g.consolidate(j2, 1);
    CHECK(r5.ok);
    CHECK_EQ(r5.generation, 2u);
    CHECK_EQ(g.manifest().generation, 2u);
    CHECK_EQ(g.ledger().size(), 2u);
    CHECK_EQ(g.ledger().at(1).epoch, 8u);
    CHECK(g.ledger().verify());
    CHECK_EQ(g.pages().resolve(root)->chart_scratch()[10], 7u);

    // Journal and manifest digests are deterministic.
    ScratchJournal j3 = j2;
    CHECK(j3.digest() == j2.digest());
    Manifest m1 = g.manifest();
    Manifest m2 = g.manifest();
    CHECK(m1.digest() == m2.digest());

    return test_done("consolidation and atomic manifest flip");
}
