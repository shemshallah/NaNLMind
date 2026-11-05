# Behavior gates and the logic challenge

## 1. Archived behavior gates

These are the old penguin/logic suites. They run from the archived source and
are reproducible:

```sh
make penguin   # Round 14 bird/eagle/penguin
make logic     # Round 19 hard cognition, Round 20 extreme cognition
make legacy    # current R19-R23 behavior gate
```

| gate | result |
|---|---|
| R14 penguin | 17/17 |
| R19 hard cognition | 18/18 |
| R20 extreme cognition | 10/10 |
| current legacy | cog 9/9, hard 8/8, extreme 8/8, formal 9/9, puzzles 7/7, modal 8/8 |

The penguin core prints:

```text
Can penguins fly? yes=0 found=1 exc=1 contrad=0
PASS: penguins cannot fly (exception wins)
```

**What this does not prove:** these suites use host-symbolic rules. They pass
because the rules are explicitly implemented, not because the byte topology
learned them. They are behavior specifications and regression gates, not
evidence of emergent reasoning.

## 2. The challenge

`tests/test_logic_challenge.cpp` is a falsification probe for the current byte
structure. It is deliberately **not** in `make test`.

Training stream (all facts are true):

- fish can swim; birds can fly;
- exceptions: penguin, ostrich, kiwi, emu, cassowary cannot fly;
- answered questions for `robin`, `eagle`, `penguin`, `ostrich`, `salmon`,
  `shark`, `kiwi`, `carp`.

Held-out questions use entities that appear in the facts but never in an
answered question:

```text
sparrow fly -> yes     ostrich fly -> no
magpie fly  -> yes     kiwi fly    -> no
trout swim  -> yes     emu fly     -> no
cod swim    -> yes     cassowary fly -> no
```

The test has four yes and four no labels. The prompt ends with the entity
immediately before the answer, so the model can use the last two bytes of the
entity name if it has counts for them.

Run:

```sh
make challenge
```

Result on the current structure:

| case | expected | model | p(yes) | p(no) |
|---|---|---|---|---|
| sparrow fly | yes | yes | 0.01556 | 0.01040 |
| magpie fly | yes | yes | 0.01519 | 0.01003 |
| trout swim | yes | yes | 0.01451 | 0.00981 |
| cod swim | yes | yes | 0.01533 | 0.01027 |
| ostrich fly | no | **yes** | 0.01470 | 0.01027 |
| kiwi fly | no | **yes** | 0.01490 | 0.01032 |
| emu fly | no | **yes** | 0.01533 | 0.01027 |
| cassowary fly | no | **yes** | 0.01533 | 0.01027 |

```text
model accuracy = 0.500
symbolic accuracy = 1.000
threshold = 0.875
FAIL challenge
```

The model answers **yes** for every held-out query. The labels are balanced and
true, and a simple host-symbolic baseline gets 8/8. The failure is real: an
order-2 byte model cannot bind the entity to its fact or the exception, and the
answer position has almost no entity-specific evidence.

An earlier version used fish exceptions such as “carp cannot swim.” That was
factually wrong; carp can swim. The challenge now uses true fish and bird facts.

This is the point of the challenge. It gives the next architecture step a
concrete thing to beat instead of another suite that is green by construction.

## 3. What would count as progress

Not "make the test green" by adding the held-out answers to training. Progress
means one of:

1. a word/token layer that binds the entity, fact, and exception over a longer
   context, then passes the same held-out cases;
2. a symbolic rule memory that is queried by the byte interface and passes;
3. a gradient-trained model on the same split that passes, used as a control,
   not as a claim about the topology.

The challenge stays fixed. The model changes.
