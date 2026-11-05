#include "nanlm/journal_forest.hpp"
#include <algorithm>
#include <cstring>
#include <set>
namespace nanlm {
namespace {
void put(std::vector<std::uint8_t>&o,std::uint64_t v,unsigned n){for(unsigned i=0;i<n;++i)o.push_back(static_cast<std::uint8_t>(v>>(8*i)));}
bool get(const std::uint8_t*d,std::size_t n,std::size_t&p,unsigned b,std::uint64_t&v){if(p>n||n-p<b)return false;v=0;for(unsigned i=0;i<b;++i)v|=static_cast<std::uint64_t>(d[p++])<<(8*i);return true;}
bool zero(const Hash256&h){for(auto b:h)if(b)return false;return true;}
Hash256 hash_record(const JournalRecord&r){
 std::vector<std::uint8_t>b;put(b,r.shard,4);put(b,r.sequence,8);put(b,r.epoch,8);b.push_back(r.kind);
 for(const auto*h:{&r.subject,&r.payload,&r.causal_parent,&r.parent})b.insert(b.end(),h->begin(),h->end());
 return Sha256::hash(b.data(),b.size());
}
}
JournalRecord JournalForest::append(std::uint32_t shard,std::uint64_t epoch,std::uint8_t kind,
 Hash256 subject,Hash256 payload,Hash256 causal_parent){
 auto&log=shards_[shard];JournalRecord r;r.shard=shard;r.sequence=log.size();r.epoch=epoch;r.kind=kind;
 r.subject=subject;r.payload=payload;r.causal_parent=causal_parent;
 if(!log.empty())r.parent=log.back().hash;r.hash=hash_record(r);log.push_back(r);return r;
}
bool JournalForest::verify(std::string*error)const{
 std::set<std::string> hashes;
 for(const auto&[id,log]:shards_){Hash256 parent{};for(std::size_t i=0;i<log.size();++i){const auto&r=log[i];
  if(r.shard!=id||r.sequence!=i||!(r.parent==parent)||!(r.hash==hash_record(r))){if(error)*error="invalid shard chain";return false;}
  hashes.insert(hex(r.hash));parent=r.hash;
 }}
 for(const auto&[id,log]:shards_)for(const auto&r:log)if(!zero(r.causal_parent)&&!hashes.count(hex(r.causal_parent))){if(error)*error="unresolved causal parent";return false;}
 if(error)error->clear();return true;
}
Hash256 JournalForest::root()const{
 Sha256 h;const char tag[8]={'N','L','M','J','F','O','R','2'};h.update(tag,8);
 for(const auto&[id,log]:shards_){std::vector<std::uint8_t>b;put(b,id,4);put(b,log.size(),8);h.update(b.data(),b.size());
  const Hash256 head=log.empty()?Hash256{}:log.back().hash;h.update(head.data(),head.size());}
 return h.final();
}
std::size_t JournalForest::size()const{std::size_t n=0;for(const auto&x:shards_)n+=x.second.size();return n;}
std::vector<JournalRecord> JournalForest::ordered()const{
 std::vector<JournalRecord>v;v.reserve(size());for(const auto&[id,log]:shards_){(void)id;v.insert(v.end(),log.begin(),log.end());}
 std::sort(v.begin(),v.end(),[](const auto&a,const auto&b){if(a.epoch!=b.epoch)return a.epoch<b.epoch;if(a.shard!=b.shard)return a.shard<b.shard;return a.sequence<b.sequence;});return v;
}
std::vector<std::uint8_t> JournalForest::serialize()const{
 std::vector<std::uint8_t>o{'N','L','M','J','F','O','R','2'};put(o,shards_.size(),4);put(o,size(),8);
 for(const auto&[id,log]:shards_)for(const auto&r:log){put(o,r.shard,4);put(o,r.sequence,8);put(o,r.epoch,8);o.push_back(r.kind);
  for(const auto*h:{&r.subject,&r.payload,&r.causal_parent,&r.parent,&r.hash})o.insert(o.end(),h->begin(),h->end());}
 return o;
}
JournalForest JournalForest::from_bytes(const std::uint8_t*d,std::size_t n){
 JournalForest bad;if(!d||n<20||std::memcmp(d,"NLMJFOR2",8)!=0)return bad;std::size_t p=8;std::uint64_t shards=0,count=0;
 constexpr std::size_t wire=181;
 if(!get(d,n,p,4,shards)||!get(d,n,p,8,count)||count>(n-p)/wire||n-p!=count*wire)return bad;
 JournalForest out;for(std::uint64_t i=0;i<count;++i){JournalRecord r;std::uint64_t v=0;
  if(!get(d,n,p,4,v))return bad;r.shard=static_cast<std::uint32_t>(v);
  if(!get(d,n,p,8,r.sequence)||!get(d,n,p,8,r.epoch)||p>=n)return bad;r.kind=d[p++];
  for(auto*h:{&r.subject,&r.payload,&r.causal_parent,&r.parent,&r.hash}){if(n-p<32)return bad;std::memcpy(h->data(),d+p,32);p+=32;}
  out.shards_[r.shard].push_back(r);
 }
 if(p!=n||out.shards_.size()!=shards||out.size()!=count||!out.verify())return bad;
 return out;
}
}
