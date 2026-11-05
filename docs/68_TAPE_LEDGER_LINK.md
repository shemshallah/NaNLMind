# Tape page checkpoints and ledger link

## 1. Root construction

`TuringTape::digest()`:

```text
NLTAPE02
page-count
for each page in sorted key order:
    signed page key
    page Universe digest
```

`TapeCheckpointManager::make` records the root, sorted page keys, page hashes,
and page count.

## 2. Journal commit

`TapeCheckpointManager::commit` appends the root to the sharded journal through
`GlobalTopology::commit_shard`, then appends one `kPageKind` record per sorted
tape page. Each page record carries the page hash as subject, a hash of the
signed page key as payload, and the root record hash as causal parent. The
forest verifies the chain and `page_records` counts the per-page records.

Tested:

```text
PASS tape page checkpoint committed to sharded journal
```

After binary increment:

```text
tape root -> journal
fresh UTM -> restore_tape -> 1100
root(fresh) == root(original)
```

## 3. Atlas allocation

A tape can be attached to an atlas before it is used:

```text
Atlas atlas;
utm.tape_store().attach_atlas(atlas);
utm.load_machine(...);
```

New tape pages are then allocated through `Atlas::allocate_page()`, and the test
checks that the atlas owns at least the description and working-tape pages.
Pages created by `restore` are owned by the tape until explicitly migrated.

## 4. Honest boundary

This binds tape contents to a page root and per-page journal records. The
journal still stores page hashes, not the page data or a mutable atlas page
table, so a fully ledger-owned page map remains open.
