#include "nanlm/hypergraph.hpp"

#include <algorithm>
#include <set>
#include <cstring>

namespace nanlm {

std::uint32_t Hypergraph::add(Hyperedge edge) {
    if (edge.members.size() < 2) return 0;
    std::set<Ref, bool (*)(const Ref&, const Ref&)> unique(
        [](const Ref& a, const Ref& b) { return a.to_string() < b.to_string(); });
    for (const auto& m : edge.members) unique.insert(m);
    if (unique.size() < 2) return 0;

    edge.id = next_id_++;
    if (edge.weight == 0) edge.weight = 65536;

    bool cross = false;
    for (const auto& m : edge.members) {
        if (!(m.page == edge.members.front().page)) cross = true;
    }
    if (cross) edge.flags = static_cast<std::uint16_t>(edge.flags | kHyperCrossSpace);

    for (const auto& m : edge.members) incidence_[m].push_back(edge.id);
    edges_.emplace(edge.id, std::move(edge));
    return next_id_ - 1;
}

bool Hypergraph::remove(std::uint32_t id) {
    auto it = edges_.find(id);
    if (it == edges_.end()) return false;
    for (const auto& m : it->second.members) {
        auto inc = incidence_.find(m);
        if (inc == incidence_.end()) continue;
        auto& v = inc->second;
        v.erase(std::remove(v.begin(), v.end(), id), v.end());
        if (v.empty()) incidence_.erase(inc);
    }
    edges_.erase(it);
    return true;
}

const Hyperedge* Hypergraph::get(std::uint32_t id) const {
    auto it = edges_.find(id);
    return it == edges_.end() ? nullptr : &it->second;
}

std::vector<std::uint32_t> Hypergraph::incident(const Ref& member) const {
    auto it = incidence_.find(member);
    return it == incidence_.end() ? std::vector<std::uint32_t>{} : it->second;
}

std::vector<Ref> Hypergraph::neighbors(const Ref& member) const {
    std::vector<Ref> out;
    std::set<std::string> seen;
    for (std::uint32_t id : incident(member)) {
        const Hyperedge* e = get(id);
        if (!e) continue;
        for (const auto& m : e->members) {
            if (m == member) continue;
            const std::string key = m.to_string();
            if (seen.insert(key).second) out.push_back(m);
        }
    }
    return out;
}

std::vector<Ref> Hypergraph::members_of(std::uint32_t id) const {
    const Hyperedge* e = get(id);
    return e ? e->members : std::vector<Ref>{};
}

std::vector<std::uint32_t> Hypergraph::at_epoch(std::uint64_t epoch) const {
    std::vector<std::uint32_t> out;
    for (const auto& kv : edges_) {
        if (kv.second.epoch == epoch) out.push_back(kv.first);
    }
    std::sort(out.begin(), out.end());
    return out;
}

std::vector<std::uint32_t> Hypergraph::between(std::uint64_t begin, std::uint64_t end) const {
    std::vector<std::uint32_t> out;
    for (const auto& kv : edges_) {
        if (kv.second.epoch >= begin && kv.second.epoch < end) out.push_back(kv.first);
    }
    std::sort(out.begin(), out.end());
    return out;
}

std::unordered_map<Ref, std::int32_t, RefHash>
Hypergraph::diffuse(const std::unordered_map<Ref, std::int32_t, RefHash>& energy) const {
    std::unordered_map<Ref, std::int64_t, RefHash> sum;
    std::unordered_map<Ref, std::int64_t, RefHash> weight;

    for (const auto& kv : edges_) {
        const Hyperedge& e = kv.second;
        if (e.members.size() < 2) continue;
        const std::int64_t share = e.weight / static_cast<std::int64_t>(e.members.size());
        for (const auto& m : e.members) {
            if (energy.find(m) == energy.end()) continue;
            for (const auto& other : e.members) {
                if (other == m) continue;
                auto oit = energy.find(other);
                if (oit == energy.end()) continue;
                sum[m] += (share * oit->second) >> 16;
                weight[m] += share;
            }
        }
    }

    std::unordered_map<Ref, std::int32_t, RefHash> next;
    for (const auto& kv : energy) next[kv.first] = kv.second;
    for (const auto& kv : sum) {
        const std::int64_t w = weight[kv.first];
        if (w <= 0) continue;
        auto eit = energy.find(kv.first);
        if (eit == energy.end()) continue;
        std::int64_t blended = (static_cast<std::int64_t>(eit->second) * 3 + kv.second) / 4;
        if (blended > (1 << 20)) blended = 1 << 20;
        next[kv.first] = static_cast<std::int32_t>(blended);
    }
    return next;
}

Hash256 Hypergraph::digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'H', 'Y', 'P', 'E', '1'};
    h.update(tag, sizeof(tag));
    std::vector<std::uint32_t> ids;
    ids.reserve(edges_.size());
    for (const auto& kv : edges_) ids.push_back(kv.first);
    std::sort(ids.begin(), ids.end());
    for (std::uint32_t id : ids) {
        const Hyperedge& e = edges_.at(id);
        h.update(&e.id, sizeof(e.id));
        h.update(&e.flags, sizeof(e.flags));
        h.update(&e.weight, sizeof(e.weight));
        h.update(&e.label, sizeof(e.label));
        h.update(&e.epoch, sizeof(e.epoch));
        const auto arity = static_cast<std::uint32_t>(e.members.size());
        h.update(&arity, sizeof(arity));
        for (const auto& m : e.members) {
            const std::uint8_t kind = static_cast<std::uint8_t>(m.kind);
            h.update(&kind, sizeof(kind));
            h.update(&m.flags, sizeof(m.flags));
            h.update(&m.offset, sizeof(m.offset));
            h.update(&m.page.depth, sizeof(m.page.depth));
            h.update(m.page.path.data(), m.page.path.size());
        }
    }
    return h.final();
}


namespace {
void hg_put(std::vector<std::uint8_t>& o, std::uint64_t v, unsigned n) {
    for (unsigned i=0;i<n;++i) o.push_back(static_cast<std::uint8_t>(v>>(8*i)));
}
bool hg_get(const std::uint8_t* d,std::size_t n,std::size_t& p,unsigned bytes,std::uint64_t& v) {
    if(p>n||n-p<bytes)return false;v=0;
    for(unsigned i=0;i<bytes;++i)v|=static_cast<std::uint64_t>(d[p++])<<(8*i);
    return true;
}
void hg_put_ref(std::vector<std::uint8_t>& o,const Ref& r) {
    o.push_back(static_cast<std::uint8_t>(r.kind));o.push_back(r.flags);
    hg_put(o,r.offset,8);o.push_back(r.page.depth);
    for(auto b:r.page.path)o.push_back(b);
}
bool hg_get_ref(const std::uint8_t*d,std::size_t n,std::size_t&p,Ref&r) {
    if(p>n||n-p<15)return false;
    r.kind=static_cast<Ref::Kind>(d[p++]);r.flags=d[p++];
    if(static_cast<unsigned>(r.kind)>static_cast<unsigned>(Ref::Kind::SuperPage))return false;
    std::uint64_t v=0;if(!hg_get(d,n,p,8,v))return false;r.offset=v;
    r.page.depth=d[p++];for(auto& b:r.page.path)b=d[p++];
    return r.page.depth<=4;
}
}
std::vector<std::uint8_t> Hypergraph::serialize() const {
    std::vector<std::uint8_t> o{'N','L','M','H','Y','P','G','2'};
    hg_put(o,next_id_,4);std::vector<std::uint32_t> ids;
    for(const auto& kv:edges_)ids.push_back(kv.first);std::sort(ids.begin(),ids.end());
    hg_put(o,ids.size(),4);
    for(auto id:ids){const auto&e=edges_.at(id);hg_put(o,e.id,4);hg_put(o,e.flags,2);
        hg_put(o,e.weight,4);hg_put(o,e.label,8);hg_put(o,e.epoch,8);
        hg_put(o,e.members.size(),4);for(const auto&m:e.members)hg_put_ref(o,m);}
    return o;
}
Hypergraph Hypergraph::from_bytes(const std::uint8_t*d,std::size_t n) {
    Hypergraph bad;if(!d||n<16||std::memcmp(d,"NLMHYPG2",8)!=0)return bad;
    std::size_t p=8;std::uint64_t v=0;
    if(!hg_get(d,n,p,4,v))return bad;const auto next=static_cast<std::uint32_t>(v);
    if(!hg_get(d,n,p,4,v)||v>(n-p)/30)return bad;const auto count=static_cast<std::size_t>(v);
    Hypergraph out;
    for(std::size_t i=0;i<count;++i){Hyperedge e;
        if(!hg_get(d,n,p,4,v))return bad;e.id=static_cast<std::uint32_t>(v);
        if(!hg_get(d,n,p,2,v))return bad;e.flags=static_cast<std::uint16_t>(v);
        if(!hg_get(d,n,p,4,v))return bad;e.weight=static_cast<std::uint32_t>(v);
        if(!hg_get(d,n,p,8,e.label)||!hg_get(d,n,p,8,e.epoch)||!hg_get(d,n,p,4,v))return bad;
        const auto arity=static_cast<std::size_t>(v);if(arity<2||arity>(n-p)/15)return bad;
        for(std::size_t j=0;j<arity;++j){Ref r;if(!hg_get_ref(d,n,p,r))return bad;e.members.push_back(r);}
        if(e.id==0||out.edges_.count(e.id))return bad;
        for(const auto&m:e.members)out.incidence_[m].push_back(e.id);
        out.edges_.emplace(e.id,std::move(e));
    }
    if(p!=n||next==0)return bad;
    for(const auto&kv:out.edges_)if(kv.first>=next)return bad;
    out.next_id_=next;return out;
}

} // namespace nanlm
