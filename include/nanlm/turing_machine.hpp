// General Turing-machine runtime. Transition table and control state live in
// chart address registers; tape symbols live in allocated 8 MiB chart pages.
#pragma once

#include "nanlm/universe.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace nanlm {

struct TmTransition {
    std::uint8_t from = 0;
    std::uint8_t read = 0;
    std::uint8_t write = 0;
    std::int8_t move = 1; // -1 left, 0 stay, +1 right
    std::uint8_t to = 0;
    bool halt = false;
};

class TuringTape {
public:
    static constexpr std::int64_t kCellsPerPage = 4096;
    std::uint8_t read(std::int64_t position) const;
    void write(std::int64_t position, std::uint8_t symbol);
    std::size_t pages() const { return pages_.size(); }
    std::string slice(std::int64_t begin, std::int64_t end) const;

private:
    Universe& page_for(std::int64_t position) const;
    std::unordered_map<std::int64_t, std::unique_ptr<Universe>> pages_;
};

class TuringMachine {
public:
    static constexpr std::uint16_t kControlBase = 0x0800;
    static constexpr std::uint16_t kTableBase = 0x1000;
    static constexpr std::uint8_t kMaxStates = 16;
    static constexpr std::uint8_t kAlphabet = 4;

    explicit TuringMachine(Universe& universe) : universe_(&universe) {}

    void load(const std::vector<TmTransition>& transitions);
    void set_tape(const std::string& tape, std::int64_t head);
    bool step();
    std::size_t run(std::size_t max_steps = 1000000);
    bool halted() const;
    std::uint8_t state() const;
    std::int64_t head() const;
    std::string tape(std::int64_t begin, std::int64_t end) const;
    std::size_t tape_pages() const { return tape_.pages(); }

private:
    Universe* universe_;
    TuringTape tape_;
};

} // namespace nanlm
