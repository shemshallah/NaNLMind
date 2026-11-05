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

Training stream:

- facts: entities are birds or fish; birds can fly; fish can swim;
- exceptions: penguin, ostrich, kiwi cannot fly; eel, carp cannot swim;
- answered questions for `robin`, `eagle`, `penguin`, `salmon`, `shark`.

Held-out questions use entities that appear in the facts but never in an
answered question:

```text
sparrow -> yes    ostrich -> no
trout   -> yes    eel     -> no
magpie  -> yes    kiwi    -> no
cod     -> yes    carp    -> no
```

The prompt ends with the entity immediately before the answer, so the model can
use the last two bytes of the entity name if it has counts for them.

Run:

```sh
make challenge
```

Result on the current structure:

| case | expected | model | p(yes) | p(no) |
|---|---|---|---|---|
| sparrow fly | yes | yes | 0.01377 | 0.00555 |
| ostrich fly | no | **yes** | 0.01339 | 0.00549 |
| trout swim | yes | yes | 0.01288 | 0.00540 |
| eel swim | no | **yes** | 0.01358 | 0.00552 |
| magpie fly | yes | yes | 0.01350 | 0.00546 |
| kiwi fly | no | **yes** | 0.01358 | 0.00552 |
| cod swim | yes | yes | 0.01358 | 0.00552 |
| carp swim | no | **yes** | 0.01358 | 0.00552 |

```text
model accuracy = 0.500
symbolic accuracy = 1.000
threshold = 0.875
FAIL challenge
```

The model answers **yes** for every held-out query. The logic labels are
balanced, and a simple host-symbolic baseline gets 8/8. The failure is real:
an order-2 byte model cannot bind the entity to its fact or the exception, and
the answer position has almost no entity-specific evidence.

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
