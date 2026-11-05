#include "nanlm/ncr.hpp"

#include <algorithm>

namespace nanlm {

void ClusterRuntime::load(ClusterProfile cluster) {
    cluster_ = std::move(cluster);
    for (auto& v : owners_) v.clear();
    generations_.fill(0);
    pending_.clear();
}

SystemProfile* ClusterRuntime::system(std::uint32_t id) {
    for (auto& s : cluster_.systems) {
        if (s.id == id) return &s;
    }
    return nullptr;
}

const SystemProfile* ClusterRuntime::system(std::uint32_t id) const {
    for (const auto& s : cluster_.systems) {
        if (s.id == id) return &s;
    }
    return nullptr;
}

bool ClusterRuntime::can_host(std::uint32_t id, const PlacementPolicy& policy) const {
    const SystemProfile* s = system(id);
    if (!s || !s->available) return false;
    return s->cores >= policy.head_cores && s->ram_bytes >= policy.head_ram_bytes &&
           s->gpu_units >= policy.head_gpu_units;
}

PlacementResult ClusterRuntime::place(const PlacementPolicy& policy) {
    PlacementResult result;
    for (auto& v : owners_) v.clear();
    generations_.fill(cluster_.generation);
    pending_.clear();

    std::vector<std::uint32_t> eligible;
    for (const auto& s : cluster_.systems) {
        if (can_host(s.id, policy)) eligible.push_back(s.id);
    }
    if (eligible.empty()) {
        result.error = "no eligible systems";
        return result;
    }

    std::unordered_map<std::uint32_t, std::uint32_t> load;
    const std::uint32_t max_per =
        policy.max_heads_per_system
            ? policy.max_heads_per_system
            : (policy.one_to_one && eligible.size() >= 256
                   ? 1u
                   : static_cast<std::uint32_t>(256));

    for (std::uint32_t h = 0; h < 256; ++h) {
        std::uint32_t best = 0;
        std::uint32_t best_load = 0xFFFFFFFFu;
        bool found = false;
        for (std::uint32_t id : eligible) {
            const SystemProfile* s = system(id);
            const std::uint32_t n = load[id];
            if (n >= max_per) continue;
            if (s->cores < (n + 1) * policy.head_cores) continue;
            if (s->ram_bytes < static_cast<std::uint64_t>(n + 1) * policy.head_ram_bytes)
                continue;
            if (s->gpu_units < (n + 1) * policy.head_gpu_units) continue;
            if (!found || n < best_load) {
                best = id;
                best_load = n;
                found = true;
            }
        }
        if (!found) {
            result.error = "not enough cluster capacity for 256 heads";
            owners_[h].clear();
            return result;
        }
        owners_[h] = {best};
        ++load[best];
        result.placements.push_back(
            HeadPlacement{static_cast<std::uint8_t>(h), best, cluster_.generation});
    }
    result.ok = true;
    return result;
}

bool ClusterRuntime::validate(std::string* error) const {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    for (std::uint32_t h = 0; h < 256; ++h) {
        if (owners_[h].size() != 1) return fail("head must have exactly one owner");
        const SystemProfile* s = system(owners_[h][0]);
        if (!s) return fail("head owner is not in the cluster");
        if (!s->available) return fail("head owner is unavailable");
    }
    if (!pending_.empty()) return fail("pending handoff at validation");
    if (error) error->clear();
    return true;
}

std::optional<std::uint32_t> ClusterRuntime::owner(std::uint8_t head) const {
    if (owners_[head].empty()) return std::nullopt;
    return owners_[head].front();
}

std::uint64_t ClusterRuntime::generation(std::uint8_t head) const {
    return generations_[head];
}

std::vector<std::uint8_t> ClusterRuntime::heads_on(std::uint32_t id) const {
    std::vector<std::uint8_t> out;
    for (std::uint32_t h = 0; h < 256; ++h) {
        if (!owners_[h].empty() && owners_[h].front() == id) {
            out.push_back(static_cast<std::uint8_t>(h));
        }
    }
    return out;
}

std::size_t ClusterRuntime::head_count_on(std::uint32_t id) const {
    return heads_on(id).size();
}

HandoffTicket ClusterRuntime::begin_handoff(std::uint8_t head, std::uint32_t to,
                                            std::uint64_t expected_generation,
                                            std::uint64_t new_generation,
                                            std::string* error) {
    HandoffTicket t;
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return t;
    };
    if (owners_[head].empty()) return fail("head has no owner");
    if (pending_.count(head)) return fail("head already has a pending handoff");
    if (owners_[head].front() == to) return fail("handoff to the same system");
    if (!can_host(to, PlacementPolicy{})) return fail("destination system unavailable");
    if (generations_[head] != expected_generation) return fail("stale head generation");
    if (new_generation <= expected_generation) return fail("generation must increase");

    t.head = head;
    t.from = owners_[head].front();
    t.to = to;
    t.from_generation = expected_generation;
    t.to_generation = new_generation;
    t.valid = true;
    pending_[head] = t;
    return t;
}

bool ClusterRuntime::commit_handoff(const HandoffTicket& ticket, std::string* error) {
    auto fail = [&](const std::string& msg) {
        if (error) *error = msg;
        return false;
    };
    auto it = pending_.find(ticket.head);
    if (it == pending_.end()) return fail("no pending handoff");
    if (!ticket.valid || it->second.to != ticket.to ||
        it->second.from_generation != ticket.from_generation ||
        it->second.to_generation != ticket.to_generation) {
        return fail("handoff ticket mismatch");
    }
    if (owners_[ticket.head].empty() || owners_[ticket.head].front() != ticket.from)
        return fail("source ownership changed");
    if (generations_[ticket.head] != ticket.from_generation)
        return fail("source generation changed");

    owners_[ticket.head] = {ticket.to};
    generations_[ticket.head] = ticket.to_generation;
    pending_.erase(it);
    return true;
}

bool ClusterRuntime::abort_handoff(const HandoffTicket& ticket, std::string* error) {
    auto it = pending_.find(ticket.head);
    if (it == pending_.end()) {
        if (error) *error = "no pending handoff";
        return false;
    }
    pending_.erase(it);
    return true;
}

bool ClusterRuntime::fail_system(std::uint32_t id, const PlacementPolicy& policy,
                                 std::vector<RecoveryEvent>* events, std::string* error) {
    SystemProfile* s = system(id);
    if (!s) {
        if (error) *error = "unknown system";
        return false;
    }
    s->available = false;
    bool all = true;
    for (std::uint32_t h = 0; h < 256; ++h) {
        if (owners_[h].empty() || owners_[h].front() != id) continue;
        std::optional<std::uint32_t> target;
        for (const auto& candidate : cluster_.systems) {
            if (candidate.id == id || !candidate.available) continue;
            if (!can_host(candidate.id, policy)) continue;
            target = candidate.id;
            break;
        }
        if (!target) {
            owners_[h].clear();
            all = false;
            continue;
        }
        owners_[h] = {*target};
        if (events) events->push_back(RecoveryEvent{static_cast<std::uint8_t>(h), id, *target,
                                                   generations_[h]});
    }
    if (!all) {
        if (error) *error = "some heads could not be reassigned";
        return false;
    }
    return true;
}

MigrationPlan ClusterRuntime::plan_migration(const ClusterProfile& destination,
                                             const PlacementPolicy& policy) const {
    MigrationPlan plan;
    plan.universe = cluster_.universe;
    plan.generation = cluster_.generation;
    ClusterRuntime tmp;
    tmp.load(destination);
    const PlacementResult placed = tmp.place(policy);
    if (!placed.ok) {
        plan.error = placed.error;
        return plan;
    }
    plan.ok = true;
    for (std::uint32_t h = 0; h < 256; ++h) plan.heads.push_back(static_cast<std::uint8_t>(h));
    return plan;
}

} // namespace nanlm
