# Proposed PTME page and pair-cell format

This is a logical format sketch, not a stable binary ABI.

## Block header

| Field | Purpose |
|---|---|
| magic | Identify PTME block |
| version | Format version |
| transform_mask | Enabled address transformations |
| logical_address_bits | 16 in this prototype |
| cell_count | Number of pair/fixed-point cells |
| page_cells | Cells per logical page |
| epoch | Current logical epoch |
| flags | Shared/dual mode and feature flags |

## Pair-cell descriptor

| Field | Purpose |
|---|---|
| cell_id | Stable canonical cell identifier |
| canonical_address | Minimum address in selected orbit |
| member_count | Orbit size: 1, 2, or 4 |
| members | Address members of orbit |
| orientation | Transform/member selector |
| generation | Reject stale references |
| epoch | Version/time coordinate |
| branch_id | Temporal branch |
| payload_ref | Shared or per-orientation payload |
| transition_rule_id | State transition rule |
| predecessor/successor | Optional topology links |
| flags | Dirty, fixed-point, control, pinned, etc. |

## Page descriptor

| Field | Purpose |
|---|---|
| page_id | Logical page number |
| first_cell | First cell index |
| cell_count | Valid cells in page |
| occupancy | Allocation bitmap |
| generation | Page reuse generation |
| backing_ref | Sparse backing-store reference |
| dirty_epoch | Last mutation epoch |
| checksum | Optional integrity metadata |

## Shared versus dual payload

- Shared mode stores one payload per cell and exposes multiple oriented ports/views.
- Dual mode stores independent payloads per direction/member.
- Temporal versions are stored as deltas, before-images, inverse records, or checkpoints.

A logical alias must not silently imply independent storage. Writes need explicit ownership, atomicity, and conflict semantics.

## Temporal event record

A minimal event log needs at least:

- cell ID
- epoch and branch
- operation kind
- prior value or sufficient inverse information
- resulting value or delta
- generation
- optional integrity digest

An operation that loses information cannot be reversed unless the missing information is retained.
