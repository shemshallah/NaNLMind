// Frame synchronization on the forward/rollback rails.
//
// A runner asks for a frame window: positive delta = forward rail (s+),
// negative delta = rollback rail (s-). Two windows meet at a common frame.
// The next runner in the ring gets precedence at the meeting point.
#pragma once

#include <cstdint>
#include <string>

namespace nanlm {

struct FrameRequest {
    std::uint8_t runner = 0;
    std::int64_t start = 0;
    std::int32_t delta = 0; // +4 = four frames forward, -3 = three frames back
    std::uint8_t flags = 0;
};

struct FrameMeeting {
    bool ok = false;
    std::int64_t frame = 0;
    std::uint8_t winner = 0;
    std::string reason;
};

class FrameSync {
public:
    static std::int64_t target(const FrameRequest& request);

    // The two requests meet when their target frames coincide. The passed
    // next_runner is the precedence holder at the meeting frame.
    static FrameMeeting meet(const FrameRequest& a, const FrameRequest& b,
                             std::uint8_t next_runner);

    // Window form: [start, target] for forward, [target, start] for rollback.
    // The earliest common frame wins; ties go to next_runner.
    static FrameMeeting meet_window(const FrameRequest& a, const FrameRequest& b,
                                    std::uint8_t next_runner);
};

} // namespace nanlm
