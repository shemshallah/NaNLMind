#!/usr/bin/env python3
"""Print the exact scaling table for the one global topology.

A chart is 8 MiB: 65,536 address registers (32 B) + 32,896 shared registers
(64 B) + descriptors + tables + extension. Charts branch through the 256
palindromic heads; depth d has 256^d charts.
"""

ADDRESSES = 1 << 16
FIXED = 1 << 8
PAIRS = (ADDRESSES - FIXED) // 2
CANONICAL = PAIRS + FIXED
PAGE = 8 * 1024 * 1024
ADDRESS_REGS = ADDRESSES * 32
SHARED_REGS = CANONICAL * 64


def human(n: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"]
    x = float(n)
    i = 0
    while x >= 1024 and i < len(units) - 1:
        x /= 1024
        i += 1
    return f"{x:.3f} {units[i]}"


def main() -> None:
    print("NaNLM Universal — exact scaling")
    print(f"addresses        {ADDRESSES:,}")
    print(f"fixed points     {FIXED:,}")
    print(f"mirror pairs     {PAIRS:,}")
    print(f"canonical cells  {CANONICAL:,}")
    print(f"address regs     {ADDRESS_REGS:,} B ({human(ADDRESS_REGS)})")
    print(f"shared regs      {SHARED_REGS:,} B ({human(SHARED_REGS)})")
    print(f"chart            {PAGE:,} B ({human(PAGE)})")
    print()
    print("depth  charts          addresses          canonical          pairs              dense")
    for d in range(0, 9):
        u = 256 ** d
        print(
            f"{d:>5}  {u:>15,}  {u*ADDRESSES:>18,}  {u*CANONICAL:>18,}  "
            f"{u*PAIRS:>18,}  {human(u*PAGE)}"
        )
    print()
    print("5 replicas, 7 GiB each:")
    for d in range(0, 5):
        u = 256 ** d
        per = (u + 4) // 5
        print(f"  depth {d}: total {human(u*PAGE):>12}  per replica {human(per*PAGE):>12}")


if __name__ == "__main__":
    main()
