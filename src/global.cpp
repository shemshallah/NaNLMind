#include "nanlm/global.hpp"

#include <stdexcept>
#include <cstring>

namespace nanlm {

GlobalTopology::GlobalTopology() : GlobalTopology(0) {}

GlobalTopology::GlobalTopology(std::uint64_t genome) {
    auto root = std::make_shared<Universe>(genome);
    pages_.map(PageId::root(), root);
    Hash256 genesis = root->digest();
    ledger_ = Ledger(genesis);
    clock_.init();
    manifests_.reset(PageId::root(), pages_.root_hash());
}

PageId GlobalTopology::add_chart(const PageId& parent, std::uint8_t head,
                                 std::uint64_t genome) {
    if (!pages_.contains(parent)) return {};
    const PageId child = PageId::child(parent, head);
    if (pages_.contains(child)) return child;
    auto page = std::make_shared<Universe>(genome);
    if (!pages_.map(child, page)) return {};
    const Hash256 before = ledger_.head();
    const Hash256 after = page->digest();
    ledger_.append(1, kEventChart, static_cast<std::uint64_t>(head), before, after,
                   clock_.tick());
    publish_manifest(child);
    return child;
}

bool GlobalTopology::has_chart(const PageId& id) const { return pages_.contains(id); }

HeadArray GlobalTopology::head_array(const PageId& chart) {
    auto page = pages_.resolve(chart);
    if (!page) throw std::runtime_error("chart not found");
    return HeadArray(*page, chart);
}

std::vector<PageId> GlobalTopology::charts() const { return pages_.pages(); }

bool GlobalTopology::read_bit(const BitAddress& address, bool& out) const {
    return pages_.read_bit(address, out);
}

bool GlobalTopology::write_bit(const BitAddress& address, bool value, bool cow) {
    return pages_.write_bit(address, value, cow);
}

NanCell* GlobalTopology::cell(const PageId& chart, std::uint16_t addr) {
    auto page = pages_.resolve(chart);
    return page ? &page->at_addr(addr) : nullptr;
}

const NanCell* GlobalTopology::cell(const PageId& chart, std::uint16_t addr) const {
    const auto* entry = pages_.entry(chart);
    return entry ? &entry->page->at_addr(addr) : nullptr;
}

BitAddress GlobalTopology::mirror(const BitAddress& address) {
    BitAddress out = address;
    out.cell = reverse16(address.cell);
    return out;
}

void GlobalTopology::publish_manifest(const PageId& changed) {
    Manifest current = manifests_.snapshot();
    Manifest next = current;
    next.generation = current.generation + 1u;
    next.page = changed;
    next.root = pages_.root_hash();
    next.epoch = current.epoch + 1u;
    next.pages = pages_.pages();
    manifests_.publish(next, current.generation);
}

GrowthDecision GlobalTopology::evaluate_growth(const PageId& chart, std::uint8_t head,
                                                const GrowthPolicy& policy) {
    GrowthDecision d;
    d.chart = chart;
    d.head = head;
    auto page = pages_.resolve(chart);
    if (!page) {
        d.reason = "chart not present";
        return d;
    }
    if (chart.depth >= policy.max_depth) {
        d.reason = "max depth reached";
        return d;
    }
    HeadArray heads(*page, chart);
    HeadView h = heads.at(head);
    if (h.has_child()) {
        d.reason = "head already has a child";
        return d;
    }
    if (h.scratch_used() >= policy.scratch_threshold) {
        d.grow = true;
        d.reason = "scratch high-water mark";
        return d;
    }
    if (h.self_error() >= policy.self_error_threshold &&
        h.error_streak() >= policy.error_streak_required) {
        d.grow = true;
        d.reason = "sustained self-model error";
        return d;
    }
    d.reason = "below threshold";
    return d;
}

std::vector<GrowthDecision> GlobalTopology::scan_growth(const PageId& chart,
                                                        const GrowthPolicy& policy) {
    std::vector<GrowthDecision> out;
    for (std::uint32_t i = 0; i < kHeadCount; ++i) {
        GrowthDecision d = evaluate_growth(chart, static_cast<std::uint8_t>(i), policy);
        if (d.grow) out.push_back(d);
    }
    return out;
}

PageId GlobalTopology::grow_head(const PageId& chart, std::uint8_t head,
                                 const GrowthPolicy& policy, std::uint64_t genome) {
    const GrowthDecision d = evaluate_growth(chart, head, policy);
    if (!d.grow) return {};
    const PageId child = add_chart(chart, head, genome);
    if (!(child.depth != 0)) return {};
    auto page = pages_.resolve(chart);
    if (page) {
        HeadArray heads(*page, chart);
        HeadView h = heads.at(head);
        h.mark_grown();
        const Hash256 after = page->digest();
        ledger_.append(1, kEventGrowth, static_cast<std::uint64_t>(head), {}, after,
                       clock_.tick());
        publish_manifest(chart);
    }
    return child;
}

ConsolidationResult GlobalTopology::consolidate(const ScratchJournal& journal,
                                                std::uint8_t actor) {
    return consolidation_.consolidate(journal, actor);
}

Hash256 GlobalTopology::global_digest() const {
    Sha256 h;
    const char tag[8] = {'N', 'L', 'M', 'G', 'L', 'O', 'B', '1'};
    h.update(tag, sizeof(tag));
    const Hash256 pages = pages_.root_hash();
    const Hash256 hy = hypergraph_.digest();
    const Hash256 tm = temporal_.digest();
    const Hash256 lg = ledger_.head();
    const Hash256 jf = journals_.root();
    const Hash256 ck = clock_.digest();
    const Hash256 mf = manifests_.snapshot().digest();
    h.update(pages.data(), pages.size());
    h.update(hy.data(), hy.size());
    h.update(tm.data(), tm.size());
    h.update(lg.data(), lg.size());
    h.update(jf.data(), jf.size());
    h.update(ck.data(), ck.size());
    h.update(mf.data(), mf.size());
    return h.final();
}

JournalRecord GlobalTopology::commit_shard(std::uint32_t shard, std::uint64_t epoch, std::uint8_t kind,
                                           Hash256 subject, Hash256 payload, Hash256 causal_parent) {
    return journals_.append(shard, epoch, kind, subject, payload, causal_parent);
}

Event GlobalTopology::commit(std::uint8_t actor, std::uint8_t kind, std::uint64_t addr,
                             Hash256 before, Hash256 after, std::uint64_t epoch) {
    const std::uint64_t logical_epoch = epoch == 0 ? clock_.tick() : epoch;
    return ledger_.append(actor, kind, addr, before, after, logical_epoch);
}


namespace {
void gp(std::vector<std::uint8_t>& o,std::uint64_t v,unsigned n){for(unsigned i=0;i<n;++i)o.push_back(static_cast<std::uint8_t>(v>>(8*i)));}
bool gg(const std::uint8_t*d,std::size_t n,std::size_t&p,unsigned b,std::uint64_t&v){if(p>n||n-p<b)return false;v=0;for(unsigned i=0;i<b;++i)v|=static_cast<std::uint64_t>(d[p++])<<(8*i);return true;}
void gpage(std::vector<std::uint8_t>&o,const PageId&id){o.push_back(id.depth);for(auto x:id.path)o.push_back(x);}
bool rpage(const std::uint8_t*d,std::size_t n,std::size_t&p,PageId&id){if(p>n||n-p<5)return false;id.depth=d[p++];for(auto&x:id.path)x=d[p++];return id.depth<=4;}
}
std::vector<std::uint8_t> GlobalTopology::serialize() const {
 std::vector<std::uint8_t>o{'N','L','M','G','L','O','B','3'};const auto ids=pages_.pages();gp(o,ids.size(),4);
 for(const auto&id:ids){const auto*e=pages_.entry(id);if(!e||!e->page)return {};gpage(o,id);auto b=e->page->serialize();gp(o,b.size(),8);o.insert(o.end(),b.begin(),b.end());}
 auto blob=[&](const std::vector<std::uint8_t>&b){gp(o,b.size(),8);o.insert(o.end(),b.begin(),b.end());};
 blob(hypergraph_.serialize());blob(temporal_.serialize());blob(ledger_.serialize());blob(journals_.serialize());
 gp(o,clock_.tick(),8);const auto&a=atomic_.anchor();gp(o,a.wall_ns,8);gp(o,a.uncertainty_ns,8);gp(o,a.captured_at_ns,8);gp(o,a.source_mask,4);o.push_back(a.valid?1:0);
 const auto&m=manifests_.snapshot();gp(o,m.generation,8);gpage(o,m.page);o.insert(o.end(),m.base.begin(),m.base.end());o.insert(o.end(),m.root.begin(),m.root.end());gp(o,m.epoch,8);gp(o,m.pages.size(),4);for(const auto&id:m.pages)gpage(o,id);
 return o;
}
std::unique_ptr<GlobalTopology> GlobalTopology::from_bytes(const std::uint8_t*d,std::size_t n) {
 if(!d||n<12||std::memcmp(d,"NLMGLOB3",8)!=0)return nullptr;std::size_t p=8;std::uint64_t count=0;
 if(!gg(d,n,p,4,count)||count==0||count>(n-p)/13)return nullptr;
 auto out=std::make_unique<GlobalTopology>();std::vector<PageId> loaded;loaded.reserve(count);
 for(std::uint64_t i=0;i<count;++i){PageId id;std::uint64_t sz=0;if(!rpage(d,n,p,id)||!gg(d,n,p,8,sz)||sz>n-p)return nullptr;
  auto u=Universe::from_bytes(d+p,static_cast<std::size_t>(sz));if(!u)return nullptr;std::string page_error;if(!u->verify(&page_error))return nullptr;const auto canonical=u->serialize();if(canonical.size()!=sz||std::memcmp(canonical.data(),d+p,static_cast<std::size_t>(sz))!=0)return nullptr;p+=static_cast<std::size_t>(sz);
  if(!out->pages_.map(id,std::shared_ptr<Universe>(std::move(u))))return nullptr;loaded.push_back(id);}
 if(p>n||n-p<32)return nullptr;
 Hash256 snapshot_root{};std::memcpy(snapshot_root.data(),d+p,32);p+=32;
 if(!(snapshot_root==out->pages_.root_hash()))return nullptr;
 auto read_blob=[&](std::vector<std::uint8_t>&b){std::uint64_t sz=0;if(!gg(d,n,p,8,sz)||sz>n-p)return false;b.assign(d+p,d+p+static_cast<std::size_t>(sz));p+=static_cast<std::size_t>(sz);return true;};
 std::vector<std::uint8_t>hy,tm,lg,jf;if(!read_blob(hy)||!read_blob(tm)||!read_blob(lg)||!read_blob(jf))return nullptr;
 out->hypergraph_=Hypergraph::from_bytes(hy.data(),hy.size());out->temporal_=BidirectionalMemory::from_bytes(tm.data(),tm.size());
 out->ledger_=Ledger::from_bytes(lg.data(),lg.size());out->journals_=JournalForest::from_bytes(jf.data(),jf.size());
 std::string error;if(!out->ledger_.verify(&error)||!out->journals_.verify(&error))return nullptr;
 if(out->hypergraph_.serialize()!=hy||out->temporal_.serialize()!=tm||out->journals_.serialize()!=jf)return nullptr;
 std::uint64_t tick=0,v=0;if(!gg(d,n,p,8,tick))return nullptr;out->clock_.rewind_to(tick);
 AtomicAnchor a;if(!gg(d,n,p,8,a.wall_ns)||!gg(d,n,p,8,a.uncertainty_ns)||!gg(d,n,p,8,a.captured_at_ns)||!gg(d,n,p,4,v)||p>=n)return nullptr;
 a.source_mask=static_cast<std::uint32_t>(v);a.valid=d[p++]!=0;out->atomic_.set(a);
 Manifest m;if(!gg(d,n,p,8,m.generation)||!rpage(d,n,p,m.page)||p>n||n-p<64)return nullptr;
 std::memcpy(m.base.data(),d+p,32);p+=32;std::memcpy(m.root.data(),d+p,32);p+=32;
 if(!gg(d,n,p,8,m.epoch)||!gg(d,n,p,4,v)||v>(n-p)/5)return nullptr;
 for(std::uint64_t i=0;i<v;++i){PageId id;if(!rpage(d,n,p,id))return nullptr;m.pages.push_back(id);}
 if(p!=n||m.pages.size()!=loaded.size()||out->pages_.size()!=loaded.size()||!out->pages_.contains(PageId::root())||!out->pages_.contains(m.page))return nullptr;
 for(const auto&id:m.pages)if(!out->pages_.contains(id))return nullptr;
 if(!out->manifests_.restore(m))return nullptr;
 return out;
}

} // namespace nanlm
