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
`GlobalTopology::commit_shard` and verifies the forest. The checkpoint can then
be restored into a fresh `UniversalTuringMachine` by restoring the serialized
tape bytes.

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

This binds tape contents to a page root and a journal record, and can allocate
new pages through the atlas. The journal does **not** own the page map, and atlas
pages are not yet first-class persisted ledger objects. That is still open.
