#include "nanlm/frame_sync.hpp"
#include "test_util.hpp"

using namespace nanlm;

int main() {
    // runner 0: frame 0, +4 -> frame 4
    // runner 1: frame 7, -3 -> frame 4
    FrameRequest a{0, 0, +4, 0};
    FrameRequest b{1, 7, -3, 0};
    const FrameMeeting m = FrameSync::meet(a, b, 2);
    CHECK(m.ok);
    CHECK_EQ(m.frame, 4);
    CHECK_EQ(m.winner, 2u);

    // Same rail is not a meeting.
    FrameRequest c{2, 0, +2, 0};
    CHECK(!FrameSync::meet(a, c, 3).ok);

    // Windows overlap: [0,4] and [2,7] -> 2.
    FrameRequest d{1, 7, -5, 0};
    const FrameMeeting w = FrameSync::meet_window(a, d, 3);
    CHECK(w.ok);
    CHECK_EQ(w.frame, 2);
    CHECK_EQ(w.winner, 3u);

    // Disjoint windows.
    FrameRequest e{1, 20, -2, 0};
    CHECK(!FrameSync::meet_window(a, e, 4).ok);

    return test_done("forward/rollback frame sync");
}
