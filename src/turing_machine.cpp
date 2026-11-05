#include "nanlm/turing_machine.hpp"

#include <algorithm>
#include <cstring>

namespace nanlm {
namespace {
constexpr std::uint16_t kStateSlot = 0;
constexpr std::uint16_t kHeadSlot = 1;
constexpr std::uint16_t kHaltSlot = 2;

std::pair<std::int64_t, std::int64_t> split_position(std::int64_t position) {
    std::int64_t page = position / TuringTape::kCellsPerPage;
    std::int64_t offset = position % TuringTape::kCellsPerPage;
    if (offset < 0) { offset += TuringTape::kCellsPerPage; --page; }
    return {page, offset};
}
} // namespace

std::uint8_t TuringTape::read(std::int64_t position) const {
    const auto [page, offset] = split_position(position);
    const auto it = pages_.find(page);
    if (it == pages_.end()) return 2; // blank symbol
    return static_cast<std::uint8_t>(
        it->second->address_reg(static_cast<std::uint16_t>(offset)).meta & 0xFFu);
}

void TuringTape::write(std::int64_t position, std::uint8_t symbol) {
    const auto [page, offset] = split_position(position);
    auto& ptr = pages_[page];
    if (!ptr) {
        ptr = std::make_unique<Universe>(0x544D5047u + static_cast<std::uint64_t>(page));
        for (std::uint16_t i = 0; i < 0x1000u; ++i) ptr->set_address_meta(i, 2);
    }
    ptr->set_address_meta(static_cast<std::uint16_t>(offset), symbol);
}

std::string TuringTape::slice(std::int64_t begin, std::int64_t end) const {
    std::string out;
    for (std::int64_t p = begin; p < end; ++p) {
        const std::uint8_t s = read(p);
        out.push_back(s == 0 ? '0' : s == 1 ? '1' : ' ');
    }
    return out;
}

bool TuringMachine::load(const std::vector<TmTransition>& transitions) {
    for (const auto& t : transitions) {
        if (t.from >= kMaxStates || t.read >= kAlphabet || t.write >= kAlphabet ||
            t.to >= kMaxStates || t.move < -1 || t.move > 1) return false;
    }
    for (std::uint16_t i = 0; i < kMaxStates * 8u; ++i)
        universe_->set_address_meta(static_cast<std::uint16_t>(kTableBase + i), 0);
    for (const auto& t : transitions) {
        const std::uint64_t move = static_cast<std::uint64_t>(t.move + 1);
        const auto addr = static_cast<std::uint16_t>(kTableBase + t.from * 8u + t.read);
        const std::uint64_t encoded = static_cast<std::uint64_t>(t.write) |
            (static_cast<std::uint64_t>(t.to) << 8) | (move << 16) |
            (1ull << 20) | (t.halt ? (1ull << 21) : 0ull);
        universe_->set_address_meta(addr, encoded);
    }
    universe_->set_address_meta(kControlBase + kHaltSlot, 0);
    universe_->set_address_meta(kControlBase + kStateSlot, 0);
    universe_->set_address_meta(kControlBase + kHeadSlot, 0);
    return true;
}

void TuringMachine::set_tape(const std::string& tape, std::int64_t head) {
    tape_.clear();
    for (std::int64_t i = 0; i < static_cast<std::int64_t>(tape.size()); ++i) {
        const char c = tape[static_cast<std::size_t>(i)];
        tape_.write(i, c == '0' ? 0 : c == '1' ? 1 : 2);
    }
    universe_->set_address_meta(kControlBase + kHeadSlot, static_cast<std::uint64_t>(head));
    universe_->set_address_meta(kControlBase + kStateSlot, 0);
    universe_->set_address_meta(kControlBase + kHaltSlot, 0);
}

bool TuringMachine::halted() const {
    return universe_->address_reg(kControlBase + kHaltSlot).meta != 0;
}

std::uint8_t TuringMachine::state() const {
    return static_cast<std::uint8_t>(universe_->address_reg(kControlBase + kStateSlot).meta);
}

std::int64_t TuringMachine::head() const {
    return static_cast<std::int64_t>(universe_->address_reg(kControlBase + kHeadSlot).meta);
}

std::string TuringMachine::tape(std::int64_t begin, std::int64_t end) const {
    return tape_.slice(begin, end);
}

bool TuringMachine::step() {
    if (halted()) return false;
    const std::uint8_t s = state();
    const std::int64_t h = head();
    const std::uint8_t read = tape_.read(h);
    if (s >= kMaxStates || read >= kAlphabet) {
        universe_->set_address_meta(kControlBase + kHaltSlot, 1);
        return false;
    }
    const std::uint64_t raw =
        universe_->address_reg(static_cast<std::uint16_t>(kTableBase + s * 8u + read)).meta;
    if ((raw & (1ull << 20)) == 0) {
        universe_->set_address_meta(kControlBase + kHaltSlot, 1);
        return false;
    }
    const std::uint8_t write = static_cast<std::uint8_t>(raw & 0xFFu);
    const std::uint8_t to = static_cast<std::uint8_t>((raw >> 8) & 0xFFu);
    const std::int8_t move = static_cast<std::int8_t>(static_cast<int>((raw >> 16) & 0x3u) - 1);
    tape_.write(h, write);
    universe_->set_address_meta(kControlBase + kStateSlot, to);
    universe_->set_address_meta(kControlBase + kHeadSlot, static_cast<std::uint64_t>(h + move));
    if ((raw & (1ull << 21)) != 0) {
        universe_->set_address_meta(kControlBase + kHaltSlot, 1);
        return false;
    }
    return true;
}

std::size_t TuringMachine::run(std::size_t max_steps) {
    std::size_t n = 0;
    while (n < max_steps && step()) ++n;
    return n;
}

std::vector<std::uint8_t> TuringTape::serialize() const {
    std::vector<std::uint8_t> out{'N','L','M','T','A','P','E','1'};
    auto put=[&](std::uint64_t v,unsigned n){for(unsigned i=0;i<n;++i)out.push_back(static_cast<std::uint8_t>(v>>(8*i)));};
    std::vector<std::int64_t> keys;keys.reserve(pages_.size());
    for(const auto& kv:pages_)keys.push_back(kv.first);
    std::sort(keys.begin(),keys.end());put(keys.size(),4);
    for(auto key:keys){const auto bytes=pages_.at(key)->serialize();put(static_cast<std::uint64_t>(key),8);put(bytes.size(),8);out.insert(out.end(),bytes.begin(),bytes.end());}
    return out;
}
bool TuringTape::restore(const std::uint8_t* data,std::size_t len) {
    if(!data||len<12||std::memcmp(data,"NLMTAPE1",8)!=0)return false;
    std::size_t p=8;
    auto get=[&](unsigned n,std::uint64_t&v){if(p>len||len-p<n)return false;v=0;for(unsigned i=0;i<n;++i)v|=static_cast<std::uint64_t>(data[p++])<<(8*i);return true;};
    std::uint64_t count=0;if(!get(4,count)||count>(len-p)/16)return false;
    std::unordered_map<std::int64_t,std::unique_ptr<Universe>> restored;
    for(std::uint64_t i=0;i<count;++i){std::uint64_t key=0,size=0;if(!get(8,key)||!get(8,size)||size>len-p)return false;
        auto page=Universe::from_bytes(data+p,static_cast<std::size_t>(size));if(!page)return false;
        std::string error;if(!page->verify(&error))return false;
        const auto canonical=page->serialize();if(canonical.size()!=size||std::memcmp(canonical.data(),data+p,static_cast<std::size_t>(size))!=0)return false;
        p+=static_cast<std::size_t>(size);const auto signed_key=static_cast<std::int64_t>(key);
        if(!restored.emplace(signed_key,std::move(page)).second)return false;}
    if(p!=len)return false;pages_=std::move(restored);return true;
}

} // namespace nanlm

