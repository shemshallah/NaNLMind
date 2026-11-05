# Security

This repository is research code. It is not a sandbox, an operating system, or
a hardened multi-tenant service.

## Reporting

Open a private security advisory on GitHub if you believe you have found a
memory-safety issue, a hash-chain collision, a page-permission bypass, or a
way for a replica to commit a state it does not host. Do not post exploit
details in a public issue.

## Scope

- The in-memory pager and register file are C++20 code and should be treated as
  untrusted-input parsers if you load serialized pages from elsewhere.
- `Universe::from_bytes` validates magic, counts, and structural invariants;
  still fuzz it before using it on hostile input.
- The ledger is tamper-evident, not tamper-proof. A pinned head protects
  against a rewritten history; an attacker who controls every replica and the
  pinned head controls the identity.
- SHA-256 is used for hashes, not for signatures. Publication of the head is
  the trust anchor.
