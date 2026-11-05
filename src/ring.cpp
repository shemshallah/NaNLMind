#include "nanlm/ring.hpp"

#include <algorithm>
#include <cmath>

namespace nanlm {

std::string u128_to_string(u128 v) {
    if (v == 0) return "0";
    std::string out;
    while (v > 0) {
        out.push_back(static_cast<char>('0' + static_cast<int>(v % 10)));
        v /= 10;
    }
    std::reverse(out.begin(), out.end());
    return out;
}

std::string human_bytes(u128 v) {
    static const char* units[] = {"B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"};
    long double x = static_cast<long double>(v);
    int u = 0;
    while (x >= 1024.0L && u < 8) {
        x /= 1024.0L;
        ++u;
    }
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.3Lf %s", x, units[u]);
    return std::string(buf);
}

} // namespace nanlm
