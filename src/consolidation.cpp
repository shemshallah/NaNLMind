#include "nanlm/consolidation.hpp"

#include <algorithm>

namespace nanlm {
namespace {

} // namespace

Hash256 Manifest::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'M', 'A', 'N', 'I', '1'};
    h.update(tag, sizeof(tag));
    h.update(&generation, sizeof(generation));
    h.update(&page.depth, sizeof(page.depth));
    h.update(page.path.data(), page.path.size());
    h.update(base.data(), base.size());
    h.update(root.data(), root.size());
    h.update(&epoch, sizeof(epoch));
    const auto count = static_cast<std::uint64_t>(pages.size());
    h.update(&count, sizeof(count));
    for (const PageId& p : pages) {
        h.update(&p.depth, sizeof(p.depth));
        h.update(p.path.data(), p.path.size());
    }
    return h.final();
}

void ManifestStore::reset(const PageId& root_page, const Hash256& root_hash) {
    std::lock_guard<std::mutex> lock(mutex_);
    current_ = Manifest{};
    current_.generation = 0;
    current_.page = root_page;
    current_.root = root_hash;
    current_.epoch = 0;
    current_.pages = {root_page};
}

Manifest ManifestStore::snapshot() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return current_;
}

bool ManifestStore::publish(Manifest next, std::uint64_t expected_generation) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (current_.generation != expected_generation) return false;
    if (next.generation != expected_generation + 1u) return false;
    current_ = std::move(next);
    return true;
}

std::uint64_t ManifestStore::generation() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return current_.generation;
}

Hash256 ScratchJournal::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'S', 'C', 'R', 'J', '1'};
    h.update(tag, sizeof(tag));
    h.update(&id, sizeof(id));
    h.update(&epoch, sizeof(epoch));
    h.update(&page.depth, sizeof(page.depth));
    h.update(page.path.data(), page.path.size());
    h.update(base.data(), base.size());
    const auto count = static_cast<std::uint64_t>(ops.size());
    h.update(&count, sizeof(count));
    for (const ScratchOp& op : ops) {
        const std::uint8_t kind = static_cast<std::uint8_t>(op.kind);
        h.update(&kind, sizeof(kind));
        h.update(&op.head, sizeof(op.head));
        h.update(&op.offset, sizeof(op.offset));
        const auto len = static_cast<std::uint32_t>(op.bytes.size());
        h.update(&len, sizeof(len));
        h.update(op.bytes.data(), op.bytes.size());
    }
    return h.final();
}

bool ConsolidationEngine::apply_op(Universe& workspace, const ScratchOp& op,
                                   std::string& error) {
    if (op.bytes.empty()) return true;
    switch (op.kind) {
        case ScratchKind::Chart: {
            if (static_cast<std::size_t>(op.offset) + op.bytes.size() > kChartScratchBytes) {
                error = "chart scratch out of range";
                return false;
            }
            std::copy(op.bytes.begin(), op.bytes.end(),
                      workspace.chart_scratch().begin() + op.offset);
            return true;
        }
        case ScratchKind::HeadLocal: {
            if (static_cast<std::size_t>(op.offset) + op.bytes.size() > kHeadLocalBytes) {
                error = "head local scratch out of range";
                return false;
            }
            HeadScratch& s = workspace.head_scratch(op.head);
            std::copy(op.bytes.begin(), op.bytes.end(), s.local() + op.offset);
            const auto used = static_cast<std::uint16_t>(op.offset + op.bytes.size());
            if (used > workspace.head(op.head).scratch_used) {
                workspace.head(op.head).scratch_used = used;
            }
            return true;
        }
        case ScratchKind::HeadWork: {
            if (static_cast<std::size_t>(op.offset) + op.bytes.size() >
                kHeadScratchBytes - kHeadLocalBytes) {
                error = "head work scratch out of range";
                return false;
            }
            HeadScratch& s = workspace.head_scratch(op.head);
            std::copy(op.bytes.begin(), op.bytes.end(), s.work() + op.offset);
            const auto used = static_cast<std::uint16_t>(kHeadLocalBytes + op.offset +
                                                         op.bytes.size());
            if (used > workspace.head(op.head).scratch_used) {
                workspace.head(op.head).scratch_used = used;
            }
            return true;
        }
    }
    error = "unknown scratch kind";
    return false;
}

ConsolidationResult ConsolidationEngine::consolidate(const ScratchJournal& journal,
                                                     std::uint8_t actor) {
    std::lock_guard<std::mutex> lock(mutex_);
    ConsolidationResult result;

    if (applied_.count(journal.id) != 0) {
        result.ok = true;
        result.duplicate = true;
        return result;
    }

    const auto* entry = pages_->entry(journal.page);
    if (!entry) {
        result.error = "page not present";
        return result;
    }

    const Hash256 base = entry->page->digest();
    result.before = base;
    if (!(base == journal.base)) {
        result.error = "stale base hash";
        return result;
    }

    auto workspace = std::make_shared<Universe>(*entry->page);
    for (const ScratchOp& op : journal.ops) {
        if (!apply_op(*workspace, op, result.error)) return result;
    }

    const Hash256 after = workspace->digest();
    result.after = after;

    if (!pages_->replace(journal.page, workspace, base)) {
        result.error = "page replacement failed (stale base)";
        return result;
    }

    ledger_->append(actor, kEventConsolidate, 0, base, after, journal.epoch);

    Manifest current = manifests_->snapshot();
    Manifest next = current;
    next.generation = current.generation + 1u;
    next.page = journal.page;
    next.base = base;
    next.root = pages_->root_hash();
    next.epoch = current.epoch + 1u;
    next.pages = pages_->pages();
    if (!manifests_->publish(next, current.generation)) {
        // One retry with the latest generation. The page and ledger are
        // already committed; the manifest is a derived pointer, not a second
        // source of truth.
        current = manifests_->snapshot();
        next.generation = current.generation + 1u;
        next.page = journal.page;
        next.base = base;
        next.root = pages_->root_hash();
        next.epoch = current.epoch + 1u;
        next.pages = pages_->pages();
        if (!manifests_->publish(next, current.generation)) {
            result.error = "manifest generation conflict";
            return result;
        }
    }

    applied_.insert(journal.id);
    result.ok = true;
    result.generation = next.generation;
    return result;
}

} // namespace nanlm
