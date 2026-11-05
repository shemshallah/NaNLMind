#pragma once

#include <iostream>
#include <string>

inline std::ostream& operator<<(std::ostream& os, unsigned __int128 v) {
    if (v == 0) return os << '0';
    char buf[64];
    int i = 0;
    while (v > 0) {
        buf[i++] = static_cast<char>('0' + static_cast<int>(v % 10));
        v /= 10;
    }
    while (i > 0) os << buf[--i];
    return os;
}

inline int g_failures = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << "  " #cond   \
                      << "\n";                                                   \
            ++g_failures;                                                        \
        }                                                                        \
    } while (0)

#define CHECK_EQ(a, b)                                                           \
    do {                                                                         \
        const auto _a = (a);                                                     \
        const auto _b = (b);                                                     \
        if (!(_a == _b)) {                                                       \
            std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << "  " #a       \
                      << " == " #b << "  (" << _a << " vs " << _b << ")\n";      \
            ++g_failures;                                                        \
        }                                                                        \
    } while (0)

inline int test_done(const char* name) {
    if (g_failures == 0) {
        std::cout << "PASS " << name << "\n";
        return 0;
    }
    std::cerr << "FAIL " << name << " (" << g_failures << " checks)\n";
    return 1;
}
