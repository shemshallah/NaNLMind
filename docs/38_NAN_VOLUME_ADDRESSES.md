# Canonical 64-bit NaN volume addresses

Status: implementation proposal on `nan-volume-addresses`, based on the
existing NaN16 `NanWord` codec and the four-tier rawroute mount design.
This does not mutate Koyeb services or volumes.

## Decision: one NaN type, two endian placements

Use **positive signaling NaN (+sNaN, head `0x7FF1`) at both ends**.

- Far head: encoded in the NaN16 far-face big-endian byte placement.
- Near head: encoded in the near-face little-endian byte placement.
- Both heads have the same semantic type. The near head is not qNaN and is
  not a second NaN type; its bytes are placed according to the existing
  `NanWord::make` rule.
- Do not call whole-word `BSWAPM` to obtain the inverse endpoint. BSWAPM
  reverses all eight bytes, including the payload, and is a different
  operation.
- The address is a typed **data identity**, never an executable instruction.
  Its same-type class nibble happens to be 0; callers must not dispatch it
  through the instruction/BOOL executor.

Canonical 64-bit integer spelling:

```
0x7FF1_PPPPPPPP_F17F
```

Canonical mount path removes separators and adds a slash:

```
/0x7FF1PPPPPPPPF17F
```

This agrees with the actual `NanWord` byte placement: in the raw integer
spelling, the **prefix `7FF1` is the near head in the high 16 bits**, and the
**suffix `F17F` is the far head stored byte-swapped in the low 16 bits**.
When viewed as the actual eight memory bytes on the specified little-endian
representation, the order is far-head bytes `7F F1`, four payload bytes in
little-endian order, then near-head bytes `F1 7F`. The existing `.nan`
display convention is a separate presentation convention and must not be
confused with the raw integer/path spelling.

## 32-bit payload

| Bits | Width | Meaning |
|---|---:|---|
| 31..24 | 8 | Magic `0x4E` (`N`) |
| 23..20 | 4 | Address format version, currently `1` |
| 19..16 | 4 | Tier: BS0=1, MC0=2, SC0=3, GM0=4 |
| 15..8 | 8 | Shard number: 0..255 |
| 7..0 | 8 | CRC-8/ATM over the upper 24 payload bits |

CRC-8 is only a transcription/corruption check. It is not a signature,
authorization token, or physical-volume identity. Authenticated route
metadata and generation checks remain authoritative.

## Four primary Koyeb volume identities

All four are shard 0, format 1, +sNaN/+sNaN:

| Tier | Payload | 64-bit address | Logical mount path | Existing DB file |
|---|---|---|---|---|
| BS0 | `4E1100E8` | `0x7FF14E1100E8F17F` | `/0x7FF14E1100E8F17F` | `bs0db.sqlite3` |
| MC0 | `4E1200D7` | `0x7FF14E1200D7F17F` | `/0x7FF14E1200D7F17F` | `mc0db.sqlite3` |
| SC0 | `4E1300C2` | `0x7FF14E1300C2F17F` | `/0x7FF14E1300C2F17F` | `sc0db.sqlite3` |
| GM0 | `4E1400A9` | `0x7FF14E1400A9F17F` | `/0x7FF14E1400A9F17F` | `gm0db.sqlite3` |

The SQLite filenames remain stable aliases inside their mount roots. The
64-bit path is the mount-root name; it does not replace the DB filename.

Shard numbers are stable logical identities within a tier. For example,
`MC0 shard 1` has the same format and tier fields but a different shard byte
and CRC. Reserve shard 0 for the first Koyeb volume; allocate later shard
numbers monotonically and never recycle one while references may remain.

## Logical identity versus Koyeb physical identity

Do **not** encode a Koyeb-generated volume UUID into the NaN address. The
logical address must survive a volume being recreated, snapshotted, restored,
or moved. Instead, maintain a signed/versioned mount manifest:

```json
{
  "format": 1,
  "nan_type": "+sNaN",
  "volumes": {
    "0x7FF14E1100E8F17F": {
      "tier": "BS0",
      "shard": 0,
      "mount_path": "/0x7FF14E1100E8F17F",
      "database": "bs0db.sqlite3",
      "provider": "koyeb",
      "provider_volume_id": "<actual Koyeb volume ID>",
      "generation": 1
    },
    "0x7FF14E1200D7F17F": {
      "tier": "MC0",
      "shard": 0,
      "mount_path": "/0x7FF14E1200D7F17F",
      "database": "mc0db.sqlite3",
      "provider": "koyeb",
      "provider_volume_id": "<actual Koyeb volume ID>",
      "generation": 1
    },
    "0x7FF14E1300C2F17F": {
      "tier": "SC0",
      "shard": 0,
      "mount_path": "/0x7FF14E1300C2F17F",
      "database": "sc0db.sqlite3",
      "provider": "koyeb",
      "provider_volume_id": "<actual Koyeb volume ID>",
      "generation": 1
    },
    "0x7FF14E1400A9F17F": {
      "tier": "GM0",
      "shard": 0,
      "mount_path": "/0x7FF14E1400A9F17F",
      "database": "gm0db.sqlite3",
      "provider": "koyeb",
      "provider_volume_id": "<actual Koyeb volume ID>",
      "generation": 1
    }
  }
}
```

The placeholders above must be replaced with actual Koyeb IDs from the
control plane. Never deploy literal placeholders.

## Mount arrangement

Recommended Koyeb mount destinations:

```
BS0 volume -> /0x7FF14E1100E8F17F/bs0db.sqlite3
MC0 volume -> /0x7FF14E1200D7F17F/mc0db.sqlite3
SC0 volume -> /0x7FF14E1300C2F17F/sc0db.sqlite3
GM0 volume -> /0x7FF14E1400A9F17F/gm0db.sqlite3
```

A provider mount destination is a POSIX path, not a hardware memory address.
The NaN path is a namespace convention implemented by the container filesystem
layout and router. Koyeb's volume documentation confirms persistent volumes
are attached to a service at a selected path, are region-scoped, currently
single-instance, and in public preview; it does not document a restriction
against hex-only path components. Validate the chosen path in a non-destructive
deployment before moving production data.

## Router integration and safety invariants

1. Parse and validate the full 64-bit address before routing.
2. Require both heads to be +sNaN; reject qNaN and -sNaN forms.
3. Validate magic, format, tier, shard and CRC.
4. Require the manifest entry to agree with the address's tier and shard.
5. Resolve the logical address to the actual mounted directory; never derive
   arbitrary filesystem paths from untrusted payload bits.
6. Require each tier to have a distinct absolute mount path.
7. Require the expected provider volume ID / generation to match the signed
   deployment manifest before writes.
8. Keep the existing rawroute rendezvous placement and route identities
   independent of the physical mount location.
9. Fail closed on missing, duplicate, stale, unmounted or mismatched mappings.
10. Back up the Koyeb volumes: Koyeb documents them as public-preview,
    single-instance local volumes without built-in redundancy.

## Rollout

1. Deploy the code and manifest support with the existing paths still active.
2. Verify all four mount roots and DB files, read-only first.
3. Snapshot/backup each volume.
4. Change mount destinations only after the service accepts the new path and
   the four databases pass integrity checks.
5. Keep a reversible mapping from old `/bs0db`, `/mc0db`, `/sc0db`,
   `/gm0db` paths to the new NaN paths for rollback.
6. Do not delete or recreate any volume as part of this code change.
