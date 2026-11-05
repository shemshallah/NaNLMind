#include "nanlm/frame_sync.hpp"

#include <algorithm>
#include <utility>

namespace nanlm {
namespace {

std::pair<std::int64_t, std::int64_t> window(const FrameRequest& r) {
    const std::int64_t t = r.start + r.delta;
    return {std::min(r.start, t), std::max(r.start, t)};
}

} // namespace

std::int64_t FrameSync::target(const FrameRequest& request) {
    return request.start + request.delta;
}

FrameMeeting FrameSync::meet(const FrameRequest& a, const FrameRequest& b,
                             std::uint8_t next_runner) {
    FrameMeeting m;
    if (a.delta == 0 || b.delta == 0) {
        m.reason = "zero-length frame request";
        return m;
    }
    if ((a.delta > 0) == (b.delta > 0)) {
        m.reason = "both requests use the same rail";
        return m;
    }
    if (target(a) != target(b)) {
        m.reason = "no common frame";
        return m;
    }
    m.ok = true;
    m.frame = target(a);
    m.winner = next_runner;
    m.reason = "forward and rollback meet; next runner has precedence";
    return m;
}

FrameMeeting FrameSync::meet_window(const FrameRequest& a, const FrameRequest& b,
                                    std::uint8_t next_runner) {
    FrameMeeting m;
    if (a.delta == 0 || b.delta == 0) {
        m.reason = "zero-length frame request";
        return m;
    }
    if ((a.delta > 0) == (b.delta > 0)) {
        m.reason = "both requests use the same rail";
        return m;
    }
    const auto wa = window(a);
    const auto wb = window(b);
    const std::int64_t lo = std::max(wa.first, wb.first);
    const std::int64_t hi = std::min(wa.second, wb.second);
    if (lo > hi) {
        m.reason = "frame windows do not overlap";
        return m;
    }
    m.ok = true;
    m.frame = lo;
    m.winner = next_runner;
    m.reason = "frame windows overlap; next runner has precedence";
    return m;
}

} // namespace nanlm
