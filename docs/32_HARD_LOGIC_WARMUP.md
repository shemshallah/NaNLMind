# Hard logic warmup

## 1. The harder problem

The fixed simple challenge is warmed with a nested relation corpus:

```text
emperor is a penguin
king is a penguin
penguin is a bird
penguin cannot fly
penguin can swim
ostrich is a bird
ostrich cannot fly
ostrich can run
salmon is a fish
fish can swim
fish cannot fly
```

The hard questions require inherited kind/exception handling:

| query | expected |
|---|---|
| emperor fly | no |
| emperor swim | yes |
| king fly | no |
| king swim | yes |
| penguin fly | no |
| penguin swim | yes |
| ostrich run | yes |
| ostrich fly | no |
| sparrow fly | yes |
| salmon fly | no |

Five yes, five no.

## 2. Byte warmup

`./build/nanlm-universal warmup 10` still trains the order-2 byte model on the
relation corpus for ten passes. The byte BPC is a diagnostic; the **system
answer** is routed through `WordMemory`.

| pass | bytes seen | byte BPC | byte top-1 | word accuracy |
|---:|---:|---:|---:|---:|
| 1 | 629 | 4.966 | 0.773 | 1.000 |
| 5 | 3,145 | 3.411 | 0.773 | 1.000 |
| 10 | 6,290 | 2.810 | 0.773 | 1.000 |

The BPC improves because repeated counting sharpens the probability model. The
byte top-1 stays flat.

The raw byte probe still collapses same-entity pairs: `emperor fly` and
`emperor swim` get the same local answer. That is why the aggregate
yes/no/uncertain counts are **not** used as the logic result anymore. They were
an artifact of the collapse.

## 3. Routed system decisions

Final-pass system answers:

| query | expected | system |
|---|---|---|
| emperor fly | no | no |
| emperor swim | yes | yes |
| king fly | no | no |
| king swim | yes | yes |
| penguin fly | no | no |
| penguin swim | yes | yes |
| ostrich run | yes | yes |
| ostrich fly | no | no |
| sparrow fly | yes | yes |
| salmon fly | no | no |

`WordMemory` binds the entity to its kind chain and checks exceptions along it:

```text
emperor -> penguin -> bird
penguin cannot fly
penguin can swim
```

The byte model still does not learn entity binding; the routed system does not
pretend it does.

## 4. Interpretation

- Byte BPC: improves with repeated exposure.
- Raw byte logic: still collapses same-entity pairs; diagnostic only.
- System logic: routed through word memory, 10/10 on the hard set.
- The fix is entity/kind binding, not more byte passes.
