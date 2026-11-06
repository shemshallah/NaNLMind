# Contributing

The repository has one rule above all others:

> There is one global topology. A chart is a coordinate region, not a separate
> mind. Do not add a component that introduces an independent semantic state
> space with its own private history or coordinator.

## Before you change code

1. Read `docs/02_ARCHITECTURE.md` and `docs/03_MATHEMATICAL_STRUCTURE.md`.
2. Run `make test`.
3. If you change an invariant, update the corresponding test and the
   falsification document. A check that cannot fail is not a check.

## Good first contributions

- Add a benchmark that compares a substrate rule against a host implementation.
- Add a fuzz target for `Universe::from_bytes` and the pager.
- Add a page format conformance test against the NaNLMind chart/page geometry.
- Add a cross-chart hyperedge experiment with a baseline.
- Add an aarch64/Termux CI job.

## Style

- C++20, integer-only core; no floating point in replay-critical paths.
- Deterministic encodings; do not hash raw structs across architectures without
  a canonical byte encoding.
- Every mutation that can become durable should be expressible as a ledger
  event with a before/after hash.
- Keep the 4 MiB chart geometry and the 32,896 canonical-cell count.

## Sign-off

By contributing you agree that your contribution is licensed under
Apache-2.0.
