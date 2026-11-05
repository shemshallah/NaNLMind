#include "test_util.hpp"

#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct TripleStore {
    std::unordered_map<std::string,
        std::unordered_map<std::string, std::vector<std::string>>> rel;

    void add(const std::string& s, const std::string& p, const std::string& o) {
        rel[s][p].push_back(o);
    }
    const std::vector<std::string>* objects(const std::string& s,
                                            const std::string& p) const {
        const auto it = rel.find(s);
        if (it == rel.end()) return nullptr;
        const auto jt = it->second.find(p);
        return jt == it->second.end() ? nullptr : &jt->second;
    }
    bool has(const std::string& s, const std::string& p, const std::string& o) const {
        const auto* v = objects(s, p);
        if (!v) return false;
        for (const auto& x : *v) if (x == o) return true;
        return false;
    }
};

bool answer_can(const TripleStore& kb, const std::string& entity,
                const std::string& ability) {
    std::vector<std::string> chain;
    std::string current = entity;
    for (int depth = 0; depth < 256; ++depth) {
        if (kb.has(current, "cannot", ability)) return false;
        chain.push_back(current);
        const auto* parents = kb.objects(current, "isa");
        if (!parents || parents->empty()) break;
        current = parents->front();
    }
    for (const auto& node : chain) {
        if (kb.has(node, "can", ability)) return true;
    }
    return false;
}

} // namespace

int main() {
    constexpr std::uint32_t kKinds = 256;
    constexpr std::uint32_t kEntities = 20000;
    constexpr std::uint32_t kQueries = 2000;
    TripleStore kb;

    // Kind chain: kind i isa kind (i+1), with a modest depth.
    for (std::uint32_t k = 0; k < kKinds; ++k) {
        const std::string kind = "kind" + std::to_string(k);
        kb.add(kind, "can", "ability0");
        if (k % 10 == 0) kb.add(kind, "can", "ability1");
        if (k + 1 < kKinds) kb.add(kind, "isa", "kind" + std::to_string(k + 1));
    }

    std::uint32_t facts = kKinds * 2;
    std::uint32_t exceptions = 0;
    for (std::uint32_t e = 0; e < kEntities; ++e) {
        const std::uint32_t k = (e * 37u + 11u) % kKinds;
        const std::string entity = "entity" + std::to_string(e);
        kb.add(entity, "isa", "kind" + std::to_string(k));
        ++facts;
        if (e % 7 == 0) {
            kb.add(entity, "cannot", "ability0");
            ++exceptions;
            ++facts;
        }
    }

    std::uint32_t correct = 0;
    const auto start = std::chrono::steady_clock::now();
    for (std::uint32_t q = 0; q < kQueries; ++q) {
        const std::uint32_t e = (q * 97u + 3u) % kEntities;
        const std::string entity = "entity" + std::to_string(e);
        const std::string ability = (q % 5 == 0) ? "ability1" : "ability0";
        const bool got = answer_can(kb, entity, ability);
        const std::uint32_t k = (e * 37u + 11u) % kKinds;
        bool kind_has_ability = (ability == "ability0");
        if (ability == "ability1") {
            for (std::uint32_t parent = k; parent < kKinds; ++parent) {
                if (parent % 10 == 0) { kind_has_ability = true; break; }
            }
        }
        const bool expected = kind_has_ability && (ability == "ability1" || e % 7 != 0);
        if (got == expected) ++correct;
    }
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << "logic-scale entities=" << kEntities << " kinds=" << kKinds
              << " facts=" << facts << " exceptions=" << exceptions
              << " queries=" << kQueries << " correct=" << correct
              << " ms=" << ms << "\n";
    CHECK_EQ(correct, kQueries);
    CHECK(facts > 20000u);
    return test_done("massive symbolic logic baseline");
}
