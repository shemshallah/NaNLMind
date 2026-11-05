#include "nanlm/head.hpp"

#include <algorithm>
#include <bit>
#include <set>

namespace nanlm {

// ---------------------------------------------------------------------------
// HeadHistory
// ---------------------------------------------------------------------------
void HeadHistory::record(const HeadEvent& event) {
    events_[next_] = event;
    next_ = static_cast<std::uint8_t>((next_ + 1u) % kCapacity);
    if (count_ < kCapacity) ++count_;
}

void HeadHistory::clear() {
    events_ = {};
    count_ = 0;
    next_ = 0;
}

const HeadEvent& HeadHistory::at(std::size_t i) const {
    const std::size_t start = (next_ + kCapacity - count_) % kCapacity;
    return events_[(start + i) % kCapacity];
}

Hash256 HeadHistory::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'H', 'I', 'S', 'T', '1'};
    h.update(tag, sizeof(tag));
    for (std::size_t i = 0; i < count_; ++i) {
        const HeadEvent& e = at(i);
        h.update(&e.epoch, sizeof(e.epoch));
        h.update(&e.kind, sizeof(e.kind));
        h.update(&e.phase, sizeof(e.phase));
        h.update(&e.energy, sizeof(e.energy));
        h.update(&e.before, sizeof(e.before));
        h.update(&e.after, sizeof(e.after));
    }
    return h.final();
}

// ---------------------------------------------------------------------------
// HeadView
// ---------------------------------------------------------------------------
HeadAddress HeadView::address() const { return HeadAddress::from_index(index_); }

Head& HeadView::record() { return array_->universe().head(index_); }
const Head& HeadView::record() const { return array_->universe().head(index_); }

NanCell& HeadView::cell() { return array_->universe().head_cell(index_); }
const NanCell& HeadView::cell() const { return array_->universe().head_cell(index_); }

HeadLinks HeadView::links() const {
    HeadLinks l;
    l.row_count = static_cast<std::uint16_t>(255u - index_);
    l.col_count = index_;
    l.row_head = record().edge_head;
    l.col_head = (index_ == 0) ? 0xFFFFu : static_cast<std::uint16_t>(index_ - 1u);
    return l;
}

bool HeadView::adjacent_to(std::uint8_t other) const {
    return array_->universe().adjacent(index_, other);
}

std::uint8_t HeadView::transform_phase() const {
    return static_cast<std::uint8_t>(record().transform_phase & 3u);
}

void HeadView::set_transform_phase(std::uint8_t phase) {
    const std::uint8_t p = static_cast<std::uint8_t>(phase & 3u);
    record().transform_phase = p;
    std::uint8_t* local = scratch().local();
    local[0] = static_cast<std::uint8_t>((local[0] & ~0x03u) | p);
}

void HeadView::advance_transform_phase() {
    set_transform_phase(next_transform_phase(transform_phase()));
}

std::uint16_t HeadView::self_error() const { return record().self_error; }
std::uint8_t HeadView::error_streak() const { return record().error_streak; }
std::uint16_t HeadView::scratch_used() const { return record().scratch_used; }

void HeadView::set_self_error(std::uint16_t error) {
    record().self_error = error;
}

void HeadView::note_self_model_error(std::uint16_t error, std::uint16_t threshold,
                                     std::uint8_t required_streak) {
    Head& r = record();
    r.self_error = error;
    if (error >= threshold) {
        if (r.error_streak < 255) ++r.error_streak;
    } else {
        r.error_streak = 0;
    }
    (void)required_streak;
}

void HeadView::note_scratch_used(std::uint16_t used) {
    Head& r = record();
    if (used > r.scratch_used) r.scratch_used = used;
}

bool HeadView::should_grow(std::uint16_t error_threshold, std::uint8_t required_streak,
                           std::uint16_t scratch_threshold) const {
    const Head& r = record();
    if (r.scratch_used >= scratch_threshold) return true;
    return r.self_error >= error_threshold && r.error_streak >= required_streak;
}

bool HeadView::has_child() const { return record().child != 0; }

void HeadView::mark_grown() {
    Head& r = record();
    r.child = 1;
    r.self_error = 0;
    r.error_streak = 0;
    r.scratch_used = 0;
}

HeadPhase HeadView::phase() const {
    const std::uint8_t c = cell().s_plus().far_class();
    if (c == 0xFFu) return HeadPhase::QuietPositive;
    return phase_of(static_cast<NanType>(c));
}

void HeadView::set_phase(HeadPhase phase) {
    const NanType t = nan_type_of(phase);
    const std::uint32_t payload = cell().s_plus().payload();
    cell().s_plus() = NanWord::make(t, t, payload);
    cell().s_minus() = NanWord::make(t, t, ~payload);
    cell().generation = static_cast<std::uint16_t>(cell().generation + 1u);
    refresh();
}

void HeadView::phase_step(std::uint32_t delta) {
    Head& r = record();
    r.phase = (r.phase + delta) & 0xFFFFu;
    const std::uint64_t energy = static_cast<std::uint64_t>(r.energy) + (delta >> 8) + 1u;
    r.energy = static_cast<std::uint32_t>(std::min<std::uint64_t>(energy, 1u << 20));
    cell().generation = static_cast<std::uint16_t>(cell().generation + 1u);
    refresh();
}

void HeadView::refresh() {
    Descriptor& d = array_->universe().descriptor_at_addr(address().value);
    d.checksum = Universe::cell_checksum(cell());
    d.epoch = cell().epoch;
    d.generation = cell().generation;
}

HeadHistory& HeadView::history() { return array_->history(index_); }
const HeadHistory& HeadView::history() const { return array_->history(index_); }

HeadScratch& HeadView::scratch() { return array_->universe().head_scratch(index_); }
const HeadScratch& HeadView::scratch() const { return array_->universe().head_scratch(index_); }

std::uint16_t HeadView::boolean_mask() const { return cell().ops; }
std::uint8_t HeadView::boolean_rule() const { return cell().rule; }

bool HeadView::set_boolean_mask(std::uint16_t mask) {
    if (!array_->universe().address_reg(address().value).can_write()) return false;
    const std::uint16_t before = cell().ops;
    cell().ops = mask;
    cell().rule = mask == 0 ? 0 : static_cast<std::uint8_t>(std::countr_zero(mask));
    cell().generation = static_cast<std::uint16_t>(cell().generation + 1u);
    refresh();
    HeadEvent ev;
    ev.kind = 2; // Boolean mask change
    ev.before = before;
    ev.after = mask;
    ev.phase = record().phase;
    ev.energy = record().energy;
    history().record(ev);
    return true;
}

bool HeadView::self_modify_boolean(std::uint16_t patch) {
    return set_boolean_mask(static_cast<std::uint16_t>(cell().ops ^ patch));
}

std::uint32_t HeadView::eval_boolean_from_scratch() {
    const std::uint8_t* l = scratch().local();
    const std::uint32_t a = static_cast<std::uint32_t>(l[0]) |
                            (static_cast<std::uint32_t>(l[1]) << 8) |
                            (static_cast<std::uint32_t>(l[2]) << 16) |
                            (static_cast<std::uint32_t>(l[3]) << 24);
    const std::uint32_t b = static_cast<std::uint32_t>(l[4]) |
                            (static_cast<std::uint32_t>(l[5]) << 8) |
                            (static_cast<std::uint32_t>(l[6]) << 16) |
                            (static_cast<std::uint32_t>(l[7]) << 24);
    const std::uint32_t out = NanWord::eval_bool(cell().rule, a, b);
    std::uint8_t* w = scratch().work();
    w[0] = static_cast<std::uint8_t>(out & 0xFFu);
    w[1] = static_cast<std::uint8_t>((out >> 8) & 0xFFu);
    w[2] = static_cast<std::uint8_t>((out >> 16) & 0xFFu);
    w[3] = static_cast<std::uint8_t>((out >> 24) & 0xFFu);
    return out;
}

// ---------------------------------------------------------------------------
// HeadRunner
// ---------------------------------------------------------------------------
RunnerResult HeadRunner::run(std::uint8_t head, const HeadToken& token) {
    RunnerResult result;
    HeadView view = heads_->at(head);
    Head& record = view.record();

    // The temporal clock is a field of the same object. When present it stamps
    // the token epoch and contributes a phase bit, so head handoffs are
    // synchronized to the global oscillator.
    HeadToken effective = token;
    if (clock_ != nullptr) {
        const std::uint64_t ct = clock_->tick();
        if (effective.epoch < ct) effective.epoch = ct;
        effective.phase = (effective.phase + (clock_->phase() << 8)) & 0xFFFFu;
    }

    if (effective.epoch < view.cell().epoch) {
        result.error = "stale token epoch";
        return result;
    }

    const std::uint64_t before = view.cell().generation;
    view.cell().epoch = static_cast<std::uint32_t>(effective.epoch + 1u);
    view.cell().generation = static_cast<std::uint16_t>(view.cell().generation + 1u);
    const std::uint32_t load =
        static_cast<std::uint32_t>(record.load) + 1u + (effective.payload & 0xFFu);
    record.load = static_cast<std::uint16_t>(std::min<std::uint32_t>(load, 0xFFFFu));
    const std::uint64_t energy =
        static_cast<std::uint64_t>(record.energy) + 1024u + (effective.payload & 0xFFu);
    record.energy = static_cast<std::uint32_t>(std::min<std::uint64_t>(energy, 1u << 20));
    record.phase = (effective.phase + (effective.payload & 0xFFu)) & 0xFFFFu;
    view.advance_transform_phase();

    // Per-head scratchpad + optional Boolean self-modification.
    // High bit of payload = patch the 16-bit operator mask with the low word.
    bool modified = false;
    if ((effective.payload & 0x80000000u) != 0) {
        modified = view.self_modify_boolean(static_cast<std::uint16_t>(effective.payload & 0xFFFFu));
    }
    HeadScratch& scratch = view.scratch();
    scratch.local()[0] = static_cast<std::uint8_t>(effective.payload & 0xFFu);
    scratch.local()[1] = static_cast<std::uint8_t>((effective.payload >> 8) & 0xFFu);
    scratch.local()[2] = static_cast<std::uint8_t>((effective.payload >> 16) & 0xFFu);
    scratch.local()[3] = static_cast<std::uint8_t>((effective.payload >> 24) & 0xFFu);
    scratch.local()[4] = static_cast<std::uint8_t>(record.phase & 0xFFu);
    scratch.local()[5] = static_cast<std::uint8_t>((record.phase >> 8) & 0xFFu);
    const std::uint32_t boolean_out = view.eval_boolean_from_scratch();
    scratch.work()[4] = static_cast<std::uint8_t>(boolean_out & 0xFFu);
    scratch.work()[5] = static_cast<std::uint8_t>((boolean_out >> 8) & 0xFFu);
    scratch.work()[6] = static_cast<std::uint8_t>((boolean_out >> 16) & 0xFFu);
    scratch.work()[7] = static_cast<std::uint8_t>((boolean_out >> 24) & 0xFFu);

    // Follow the first topology link. Head 255 has no row list, so it uses its
    // first column link. This is a real pair-cell edge, not an arbitrary index.
    std::uint8_t next = head;
    if (head < 255 && record.edge_head != 0xFFFFu) {
        next = heads_->universe().descriptor_pair(record.edge_head).head_b;
    } else if (head > 0) {
        next = heads_->universe().descriptor_pair(static_cast<std::uint32_t>(head - 1u)).head_a;
    }

    if (temporal_ != nullptr) {
        const BitAddress past{chart_, HeadAddress::from_index(head).value, 0, 0};
        const BitAddress future{chart_, HeadAddress::from_index(next).value, 0, 0};
        temporal_->link(Ref::from_bit(past), Ref::from_bit(future), effective.epoch,
                        kTemporalReversible);
    }

    HeadEvent event;
    event.epoch = effective.epoch;
    event.kind = 1;
    event.phase = record.phase;
    event.energy = record.energy;
    event.before = before;
    event.after = view.cell().generation;
    view.history().record(event);
    view.refresh();

    result.ok = true;
    result.modified = modified;
    result.next = next;
    result.out.id = effective.id;
    result.out.payload = effective.payload;
    result.out.epoch = effective.epoch + 1u;
    result.out.phase = record.phase;

    if (clock_ != nullptr) clock_->step();
    return result;
}

// ---------------------------------------------------------------------------
// HeadArray
// ---------------------------------------------------------------------------
HeadArray::HeadArray(Universe& universe, PageId chart)
    : universe_(&universe), chart_(std::move(chart)) {}

HeadView HeadArray::at(std::uint8_t index) { return HeadView(*this, index); }

HeadView HeadArray::by_address(std::uint16_t address) {
    if (!HeadAddress::valid(address)) return HeadView(*this, 0);
    return HeadView(*this, static_cast<std::uint8_t>(matrix_row(address)));
}

bool HeadArray::verify(std::string* error) const {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    std::string uerr;
    if (!universe_->verify(&uerr)) return fail("universe: " + uerr);

    std::set<std::uint16_t> addresses;
    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        const auto idx = static_cast<std::uint8_t>(i);
        HeadView view(const_cast<HeadArray&>(*this), idx);
        const HeadAddress expected = HeadAddress::from_index(idx);
        if (!HeadAddress::valid(expected.value)) return fail("head address not palindromic");
        if (!addresses.insert(expected.value).second) return fail("duplicate head address");
        if (universe_->head(idx).fixed_addr != expected.value) return fail("head fixed address");
        if (!universe_->head_cell(idx).is_head()) return fail("head cell flag");
        if (!universe_->descriptor_at_addr(expected.value).is_head()) {
            return fail("head descriptor flag");
        }
        if (universe_->head(idx).edge_count != 255) return fail("head edge count");
        const HeadLinks links = view.links();
        if (links.total() != 255) return fail("head links total");
        if (links.row_count != 255u - idx) return fail("head row count");
        if (links.col_count != idx) return fail("head column count");
    }
    if (addresses.size() != kHeadCount) return fail("head count");
    if (error) error->clear();
    return true;
}

Hash256 HeadArray::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'H', 'E', 'A', 'D', '1'};
    h.update(tag, sizeof(tag));
    const std::uint32_t impl = kImplementationId;
    h.update(&impl, sizeof(impl));
    h.update(&chart_.depth, sizeof(chart_.depth));
    h.update(chart_.path.data(), chart_.path.size());
    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        const Head& r = universe_->head(static_cast<std::uint8_t>(i));
        const NanCell& c = universe_->head_cell(static_cast<std::uint8_t>(i));
        const HeadScratch& s = universe_->head_scratch(static_cast<std::uint8_t>(i));
        h.update(&r, sizeof(r));
        h.update(&c, sizeof(c));
        h.update(s.bytes.data(), s.bytes.size());
    }
    return h.final();
}

Hash256 HeadArray::history_digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'H', 'I', 'S', 'T', '2'};
    h.update(tag, sizeof(tag));
    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        const Hash256 d = histories_[i].digest();
        h.update(d.data(), d.size());
    }
    return h.final();
}

} // namespace nanlm
