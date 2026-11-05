#include "nanlm/journal_forest.hpp"
#include "test_util.hpp"
using namespace nanlm;
int main(){
 JournalForest a,b;Hash256 s{},p{},q{};s[0]=1;p[0]=2;q[0]=3;
 auto r0=a.append(0,1,1,s,p);auto r1=a.append(1,1,1,p,q);a.append(0,2,2,q,s,r0.hash);
 b.append(1,1,1,p,q);b.append(0,1,1,s,p);b.append(0,2,2,q,s,r0.hash);
 CHECK(a.verify());CHECK(b.verify());CHECK(a.root()==b.root());CHECK_EQ(a.size(),3u);
 auto order=a.ordered();CHECK_EQ(order.size(),3u);CHECK_EQ(order[0].shard,0u);
 auto bytes=a.serialize();auto copy=JournalForest::from_bytes(bytes.data(),bytes.size());
 CHECK_EQ(copy.size(),3u);CHECK(copy.root()==a.root());CHECK(copy.verify());
 auto bad=bytes;bad.pop_back();CHECK_EQ(JournalForest::from_bytes(bad.data(),bad.size()).size(),0u);
 return test_done("global sharded journal forest");
}
