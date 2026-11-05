// Router chart: the meta-layer of the one global topology.
//
// The 256 palindromic points of a router chart are portals to child universes.
// The 32,640 pair cells are routes between them. The two rails are forward and
// reverse routes; the four NaN classes encode quiet/signaling and sign; the
// far/near faces give the BE/LE direction. The payload is data; aux carries
// route flags and the operation code.
//
// This is not a separate mind or a new geometry: it is a chart whose heads are
// universe roots. The same 256x256 algebra applies at every layer.
#pragma once

#include "nanlm/global.hpp"
#include "nanlm/nan16.hpp"

#include <cstdint>
#include <string>

namespace nanlm {

enum class PortalOp : std::uint8_t {
    ReadForward = 0,  // +qNaN, BE/FUTURE, quiet read
    ReadReverse = 1,  // -qNaN, LE/PAST, quiet read
    WriteForward = 2, // +sNaN, BE/FUTURE, signaling write
    WriteReverse = 3, // -sNaN, LE/PAST, signaling write
    AckForward = 4,   // +qNaN, BE/FUTURE, quiet ack
    AckReverse = 5,   // -qNaN, LE/PAST, quiet ack
    Open = 6,         // +sNaN, BE/FUTURE, open route
    Close = 7,        // -sNaN, LE/PAST, close route
};

constexpr NanType portal_nan_type(PortalOp op) {
    switch (op) {
        case PortalOp::ReadForward: return NanType::QuietPositive;
        case PortalOp::ReadReverse: return NanType::QuietNegative;
        case PortalOp::WriteForward: return NanType::SignalPositive;
        case PortalOp::WriteReverse: return NanType::SignalNegative;
        case PortalOp::AckForward: return NanType::QuietPositive;
        case PortalOp::AckReverse: return NanType::QuietNegative;
        case PortalOp::Open: return NanType::SignalPositive;
        case PortalOp::Close: return NanType::SignalNegative;
    }
    return NanType::QuietPositive;
}

constexpr bool portal_is_write(PortalOp op) {
    return op == PortalOp::WriteForward || op == PortalOp::WriteReverse ||
           op == PortalOp::Open || op == PortalOp::Close;
}

constexpr bool portal_is_forward(PortalOp op) {
    return op == PortalOp::ReadForward || op == PortalOp::WriteForward ||
           op == PortalOp::AckForward || op == PortalOp::Open;
}

// A route word carried in a pair cell. The payload is data; flags are in aux.
struct PortalWord {
    PortalOp op = PortalOp::ReadForward;
    std::uint8_t flags = 0;
    std::uint32_t data = 0;

    NanWord encode() const {
        const NanType t = portal_nan_type(op);
        return NanWord::make(t, t, data);
    }
    static PortalWord decode(const NanWord& word, std::uint16_t aux) {
        PortalWord p;
        p.flags = static_cast<std::uint8_t>(aux & 0xFFu);
        p.data = word.payload();
        const std::uint8_t coded = static_cast<std::uint8_t>((aux >> 8) & 0xFFu);
        if (coded <= static_cast<std::uint8_t>(PortalOp::Close)) {
            p.op = static_cast<PortalOp>(coded);
            return p;
        }
        const std::uint8_t c = word.far_class();
        const bool signaling = c == static_cast<std::uint8_t>(NanType::SignalPositive) ||
                               c == static_cast<std::uint8_t>(NanType::SignalNegative);
        const bool negative = c == static_cast<std::uint8_t>(NanType::SignalNegative) ||
                              c == static_cast<std::uint8_t>(NanType::QuietNegative);
        if (signaling && negative) p.op = PortalOp::WriteReverse;
        else if (signaling) p.op = PortalOp::WriteForward;
        else if (negative) p.op = PortalOp::ReadReverse;
        else p.op = PortalOp::ReadForward;
        return p;
    }
};

struct RouteResult {
    bool ok = false;
    PortalWord word{};
    std::string error;
};

class RouterChart {
public:
    RouterChart(GlobalTopology& topology, PageId chart);

    const PageId& chart() const { return chart_; }
    PageId universe(std::uint8_t head) const { return PageId::child(chart_, head); }
    bool has_universe(std::uint8_t head) const;

    // Route data/flags from src universe to dst universe. The pair cell is the
    // canonical cell for {src,dst}; forward uses s+, reverse uses s-.
    RouteResult route(std::uint8_t src, std::uint8_t dst, PortalOp op, std::uint32_t data,
                      std::uint8_t flags, std::uint64_t epoch);
    RouteResult read(std::uint8_t src, std::uint8_t dst, bool forward) const;

    // Create the child chart for a portal head (on demand).
    bool open_universe(std::uint8_t head, std::uint64_t genome = 0);

private:
    GlobalTopology* topology_;
    PageId chart_;
};

} // namespace nanlm
