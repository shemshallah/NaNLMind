# NaNLMind architecture requirements

## 1. What `nanlm-universal` means

`nanlm-universal` is the **CLI/driver name**, not a claim that one compiled
binary is architecture-independent. The `universal` refers to:

- one universal topology;
- the universal-machine and address algebra;
- the native trainer/interpreter surface.

The executable is still built for one target ABI. Android/Termux currently
produces an aarch64 Android/bionic binary; Linux/x86 builds must produce their
own executable.

Proposed naming:

```text
nanlm              portable CLI name
nanlm-universal    compatibility alias / full topology+UTM profile
```

Do not ship the Termux-built binary into an Alpine/musl or x86 image.

## 2. Supported target matrix

| target | ABI | status | special requirement |
|---|---|---|---|
| Linux x86_64 | glibc/musl, 64-bit little-endian | primary demo/server target | full 2 GiB overbootstrap allowed for bootstrap |
| Linux aarch64 | glibc/musl | primary edge/server target | full map only on bootstrap |
| Android aarch64 | bionic | current Termux target | 8 MiB chart; no 2 GiB constructor |
| Windows x86_64 | MSVC/MinGW | planned | no POSIX paging shortcuts |
| macOS arm64/x86_64 | Darwin | planned | page/allocator abstraction |
| armv7 | 32-bit | experimental | 64-bit offsets still required in tape/ledger paths |

## 3. Build invariants

Every target must provide:

- C++20 compiler and standard library;
- 64-bit file/offset types (`std::uint64_t`, `std::int64_t`);
- little-endian byte encoding for serialized pages/ledger;
- 64-bit atomics for the handoff/clock paths;
- virtual memory or an explicit paged allocator;
- no host floating point in replay/decision state;
- deterministic integer hashes and checksums.

The core may use host SIMD as an accelerator, but the serialized result and
decision trajectory must match the scalar path.

## 4. Memory requirements

```text
single chart              8 MiB
bootstrap overbootstrap  2 GiB only on bootstrap targets
Android edge             8 MiB; no overbootstrap constructor
page size                8 MiB chart page
```

The 2 GiB map is a bootstrap placement feature, not an implicit allocation on
edge or Android. API compatibility must preserve the compile-time guard:

```cpp
#if defined(__ANDROID__)
// OverbootstrapMap is unavailable.
#endif
```

## 5. Build commands

Native host:

```sh
make -j2 BUILD=build/native
./build/native/nanlm-universal verify
```

Architecture-isolated build directory:

```sh
make -j2 BUILD=build/linux-x86_64 CXX=g++ CXXFLAGS='-std=c++20 -O2 -Iinclude'
```

Cross-compilation must set both `CXX` and the target sysroot; do not reuse a
Termux object directory for a different ABI.

## 6. CI gates per target

1. compile and link;
2. `verify`;
3. `genesis`;
4. `scale`;
5. `heads`;
6. headshift snapshot smoke;
7. serialized page round-trip;
8. architecture-specific memory guard test;
9. deterministic digest equality across two builds of the same target.

Cross-architecture digest comparison is required only after endianness and
integer-width checks pass.

## 7. What is not portable yet

- the build currently writes one `build/` tree; architecture-isolated
  `BUILD=` directories are required;
- there is no x86 CI runner matrix yet;
- Termux binaries are Android/bionic and cannot run in Alpine/musl;
- the overbootstrap 2 GiB path is intentionally absent on Android.

This branch is the architecture contract; implementation changes should land
here and be merged back to `main` only after the matrix gates pass.
