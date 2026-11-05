#include "nanlm/handoff.hpp"

#include "nanlm/global.hpp"

#include <algorithm>
#include <set>

namespace nanlm {

HeadMap::HeadMap(std::uint8_t runners) : runners_(runners) {
    if (runners_ == 0 || runners_ > kMaxRunners) {
        error_ = "runner count must be 1..6";
        return;
    }
    heads_.assign(runners_, {});
    owner_.assign(kHeadCount, 0);
    for (std::uint32_t h = 0; h < kHeadCount; ++h) {
        const auto r = static_cast<std::uint8_t>(h % runners_);
        owner_[h] = r;
        heads_[r].push_back(static_cast<std::uint8_t>(h));
    }
    std::vector<std::uint32_t> counts(runners_, 0);
    for (std::uint32_t h = 0; h < kHeadCount; ++h) ++counts[owner_[h]];
    std::uint32_t total = 0;
    for (std::uint8_t r = 0; r < runners_; ++r) {
        if (heads_[r].empty()) {
            error_ = "a runner has no heads";
            return;
        }
        total += static_cast<std::uint32_t>(heads_[r].size());
    }
    if (total != kHeadCount) {
        error_ = "head map does not cover 256 heads";
        return;
    }
    valid_ = true;
}

const std::vector<std::uint8_t>& HeadMap::heads_for(std::uint8_t runner) const {
    static const std::vector<std::uint8_t> empty;
    return runner < runners_ ? heads_[runner] : empty;
}

std::uint8_t HeadMap::owner_of(std::uint8_t head) const { return owner_[head]; }

HandoffRound::HandoffRound(std::uint64_t epoch, std::uint8_t runners)
    : epoch_(epoch), runners_(runners) {}

bool HandoffRound::prepare(std::uint8_t runner, const std::vector<HeadPacket>& packets,
                           std::string* error) {
    auto fail = [&](const std::string& msg) {
        error_ = msg;
        if (error) *error = msg;
        return false;
    };
    if (runner >= runners_) return fail("runner out of range");
    if (prepared_[runner]) return fail("runner already prepared");
    if (packets.empty()) return fail("empty packet list");

    HeadMap map(runners_);
    if (!map.valid()) return fail(map.error());

    std::set<std::uint8_t> seen;
    for (const HeadPacket& p : packets) {
        if (p.epoch != epoch_) return fail("packet epoch mismatch");
        if (map.owner_of(p.head) != runner) return fail("packet owned by another runner");
        if (!seen.insert(p.head).second) return fail("duplicate head in runner packets");
    }
    packets_[runner] = packets;
    prepared_[runner] = true;
    return true;
}

bool HandoffRound::commit(std::uint8_t runner, std::string* error) {
    if (runner >= runners_) {
        if (error) *error = "runner out of range";
        return false;
    }
    if (!prepared_[runner]) {
        if (error) *error = "runner has not prepared";
        return false;
    }
    committed_[runner] = true;
    return true;
}

bool HandoffRound::ready() const {
    for (std::uint8_t r = 0; r < runners_; ++r) {
        if (!prepared_[r]) return false;
    }
    return true;
}

bool HandoffRound::complete() const {
    for (std::uint8_t r = 0; r < runners_; ++r) {
        if (!committed_[r]) return false;
    }
    return true;
}

const std::vector<HeadPacket>& HandoffRound::packets(std::uint8_t runner) const {
    static const std::vector<HeadPacket> empty;
    return runner < runners_ ? packets_[runner] : empty;
}

std::vector<HeadPacket> HandoffRound::all_packets() const {
    std::vector<HeadPacket> out;
    out.reserve(kHeadCount);
    for (std::uint8_t r = 0; r < runners_; ++r) {
        out.insert(out.end(), packets_[r].begin(), packets_[r].end());
    }
    std::sort(out.begin(), out.end(), [](const HeadPacket& a, const HeadPacket& b) {
        return a.head < b.head;
    });
    return out;
}

bool HandoffRound::verify(std::string* error) const {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    HeadMap map(runners_);
    if (!map.valid()) return fail(map.error());
    std::vector<bool> seen(kHeadCount, false);
    std::size_t total = 0;
    for (std::uint8_t r = 0; r < runners_; ++r) {
        for (const HeadPacket& p : packets_[r]) {
            if (p.epoch != epoch_) return fail("packet epoch mismatch");
                if (seen[p.head]) return fail("duplicate head across runners");
            if (map.owner_of(p.head) != r) return fail("head in wrong runner");
            seen[p.head] = true;
            ++total;
        }
    }
    if (total != kHeadCount) return fail("round does not cover 256 heads");
    for (bool s : seen) {
        if (!s) return fail("missing head");
    }
    if (error) error->clear();
    return true;
}

Hash256 HandoffRound::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'H', 'A', 'N', 'D', '1'};
    h.update(tag, sizeof(tag));
    h.update(&epoch_, sizeof(epoch_));
    h.update(&runners_, sizeof(runners_));
    for (const HeadPacket& p : all_packets()) {
        h.update(&p.head, sizeof(p.head));
        h.update(&p.epoch, sizeof(p.epoch));
        h.update(&p.phase, sizeof(p.phase));
        h.update(&p.transform_phase, sizeof(p.transform_phase));
        h.update(&p.self_error, sizeof(p.self_error));
        h.update(&p.scratch_used, sizeof(p.scratch_used));
        h.update(&p.state_hash, sizeof(p.state_hash));
        h.update(p.output.data(), p.output.size());
    }
    return h.final();
}

bool record_handoff(GlobalTopology& topology, const HandoffRound& round,
                    std::uint8_t actor, std::string* error) {
    std::string err;
    if (!round.verify(&err)) {
        if (error) *error = err;
        return false;
    }
    const Hash256 d = round.digest();
    topology.commit(actor, kEventHandoff, 0, d, d, round.epoch());
    return true;
}

} // namespace nanlm
