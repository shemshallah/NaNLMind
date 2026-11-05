#!/usr/bin/env python3
"""Parameterized Earth-scale address planning. Assumptions, not a census."""
import argparse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", type=float, default=20e9)
    ap.add_argument("--x86", type=float, default=2e9)
    ap.add_argument("--riscv", type=float, default=0.5e9)
    ap.add_argument("--gpu", type=float, default=1e9)
    ap.add_argument("--contribution", type=float, default=0.01)
    a = ap.parse_args()
    total = a.arm + a.x86 + a.riscv + a.gpu
    units = total * a.contribution
    clusters = units / 256
    macros = clusters / 256
    iot = macros / 256
    meshes = iot / 256
    supers = meshes / 256
    print(f"assumed devices      {total:,.0f}")
    print(f"contribution         {a.contribution:.2%}")
    print(f"units                {units:,.0f}")
    print(f"clusters             {clusters:,.1f}")
    print(f"macroclusters        {macros:,.1f}")
    print(f"IoT spaces           {iot:,.2f}")
    print(f"global meshes        {meshes:,.4f}")
    print(f"superclusters        {supers:,.6f}")
    print("one global mesh has 256 IoT spaces = 4,294,967,296 units")


if __name__ == "__main__":
    main()
