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

## Credentials

`DEEPREPO_PAT` is a **GitHub runner secret**. It is never shipped in an APK,
Android build, release artifact, container image, log, cache, or route diff. An
APK is extractable; treat every string, asset, preference, and native blob in it
as public.

Community nodes do **not** receive `DEEPREPO_PAT` or the ring secret. They talk
to the intake endpoint with a:

- short-lived credential;
- scoped to intake/route submission (no repo, release, workflow, or ring access);
- revocable per device or community node;
- separate audience from the GitHub runner ring;
- rotated on revocation, compromise, or expiry.

The Android client uses `NANLM_DEVICE_TOKEN` from the environment and
`NANLM_INTAKE_URL`. It never reads `DEEPREPO_PAT`.

`DEEPREPO_PAT` exists only in GitHub Actions secrets. It must have the minimum
permissions in [docs/18_HEAD_RING.md](docs/18_HEAD_RING.md). It is not available
to user-facing endpoints, APKs, or community clients.

Koyeb environment variables must use Koyeb secret references, not plaintext
values. A deployment-definition read can expose plaintext env values; if a
plaintext runner PAT was ever used there, rotate it and re-create the service
with a secret reference.

## Cryptography fallback

`nanlmind_nannet` can run without the `cryptography` package. It uses Ed25519,
AES-256-GCM, and HKDF-SHA256 from a dependency-free Fallback for minimal images
such as Termux. The fallback is not constant-time; use the optional
`cryptography` package or an HSM for production key custody.

```sh
pip install "nanlmind-hermes[auth]"
```

The fallback still signs and verifies Ed25519 tokens; it does not replace the
algorithm.

## Build hygiene

- `.nanlmind/` is an external source clone and is gitignored.
- Do not commit `.env`, token files, keystores, or local credentials.
- Route diffs contain node IDs, hashes, and route metadata, not raw input text.
- If a token leaks, revoke it first, then rotate. Deleting a file is not enough.
