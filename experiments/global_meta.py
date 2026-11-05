#!/usr/bin/env python3
"""Print the 256 x 256 x 256 global-meta envelope. Design arithmetic only."""
LEVELS = [
    ("system", 1),
    ("cluster", 256),
    ("supercluster", 256 * 256),
    ("meta-universe", 256 * 256 * 256),
    ("global", 256 * 256 * 256 * 256),
]
PAGE = 8 * 1024 * 1024
HEADS = 256


def human(n):
    units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"]
    x = float(n)
    i = 0
    while x >= 1024 and i < len(units) - 1:
        x /= 1024
        i += 1
    return f"{x:.3f} {units[i]}"


def main():
    print("level          systems          universes (1/system)   heads        dense")
    for name, systems in LEVELS:
        universes = systems
        heads = universes * HEADS
        print(f"{name:<14} {systems:>15,} {universes:>23,} {heads:>12,} {human(universes * PAGE):>12}")
    print()
    print("regional reading: one universe per supercluster")
    superclusters = 256 * 256
    print(f"  superclusters {superclusters:,}")
    print(f"  universes     {superclusters:,}")
    print(f"  heads         {superclusters * HEADS:,}")
    print(f"  dense         {human(superclusters * PAGE)}")


if __name__ == "__main__":
    main()
