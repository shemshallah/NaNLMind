# Two-rate learning mesh

## 1. Why two learners

The bootstrap and overbootstrap are not the same learner at different sizes.
They need different math and different timescales.

```text
bootstrap (8 MiB)
  fast, local, byte/token
  sparse Hopfield slots
  changes every token/epoch

overbootstrap (2 GiB map / meta layer)
  slower, global, head reliability and routing
  evidence counters and layer policy
  changes every trace/merge
```

Overbootstrap is the **mind/meta layer**: it decides which heads are reliable
and which routes to reinforce. Bootstrap is the fast local association layer.

## 2. Mesh loop

```text
bootstrap query
  -> prediction + active heads
  -> BootstrapTrace
  -> overbootstrap observes correctness
  -> bounded head bias
  -> bootstrap top-k/routing changes
```

The feedback is deliberately bounded to ±8 so overbootstrap cannot overwrite
bootstrap's local slots. It steers; it does not replace the fast learner.

## 3. Different mathematics

| layer | state | learner |
|---|---|---|
| bootstrap | head vectors, pair keys, strengths | sparse Hopfield / Hebbian |
| overbootstrap | head evidence, correct/wrong counts, routes | integer evidence/confidence counters |

Overbootstrap is **not** a larger Hopfield matrix. It learns at the meta level:
which head activations were correct, which were wrong, and what bias to send
back. The 2 GiB map is where its layer payloads and routes belong; this test
keeps only the small evidence state.

## 4. Test

`tests/test_learning_mesh.cpp`:

- trains an 8-token cycle for 10 passes through the mesh;
- checks bootstrap still predicts 8/8;
- checks overbootstrap observed 80 traces;
- checks evidence and bounded bias are present;
- checks meta digest is deterministic.

```text
PASS two-rate bootstrap/overbootstrap learning mesh
```

This proves the mesh mechanics, not language understanding. The next step is to
store the overbootstrap evidence/routes in the 2 GiB layer payloads and feed the
merged biases back after a Koyeb merge.

## 5. Layer policy hook

Overbootstrap should eventually own a `LayerPolicy` per abstraction layer:

```text
bit/byte  -> bootstrap local
word      -> bootstrap + vector bins
logic     -> overbootstrap rule/meta
code      -> overbootstrap exact/tests
corpus    -> corpus supercluster retrieval
```

The mesh exposes `bootstrap()` and `mind()` separately so each layer can choose
which side learns and which side only routes.
