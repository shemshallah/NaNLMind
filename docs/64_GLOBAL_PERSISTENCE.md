# Global persistence and sharded history

GlobalTopology now exposes a versioned whole-object snapshot. It contains chart pages, hypergraph, bidirectional temporal links, the compatibility ledger, sharded journal forest, logical clock tick, wall-time anchor, and manifest. Restore validates page hashes, journal chains, and manifest membership.

JournalForest provides independent hash-chained append lanes. Its root commits to ordered shard IDs, counts, and shard heads. GlobalTopology::commit_shard is the data-plane append API; the existing Ledger remains the low-frequency compatibility/control-plane chain. Full migration of replica commits and consolidation remains future work.

TuringTape serializes sparse tape pages. A resumable machine checkpoint combines the chart Universe snapshot (transition table and control registers) with the tape snapshot. Invalid transition tables are rejected, stale table entries are cleared on load, and set_tape clears old tape pages.

Persistent runner mode requires NANLM_USE_CORE=1 and executes six C++ headshift shards sequentially against one evolving chart.nmc within the same job workspace. It fails closed rather than emitting synthetic packets. This is not yet crash-safe cross-job persistence or distributed multi-writer consensus.

NTF publish and resolve require a configured signature verifier over a canonical versioned digest. The test callback is not production cryptography; production must install Ed25519 or an equivalent verifier. Universe IDs parse as hexadecimal to match to_string; regions are decimal.

Remaining work: move replica and consolidation writes to shard journals; add fencing leases and idempotent retries; connect whole-object snapshots to durable shared storage; implement production key lifecycle; and replace fixed-layout page records with an explicitly endian-defined wire format and cross-compiler golden vectors.
