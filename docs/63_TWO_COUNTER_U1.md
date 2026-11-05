# U1: bounded two-counter machine in chart registers

## 1. What is stored where

All machine state is in `AddressReg::meta`:

```text
state_base + 0   HALT
state_base + 1   IP
state_base + 2   counter 0
state_base + 3   counter 1
program_base + i instruction (opcode + target)
```

No host counter map, no task-specific `if (task == ...)`. One `step()` decodes
the current program cell and writes the next state.

## 2. Instruction set

```text
INC0 INC1 DEC0 DEC1 JZ0 JZ1 JMP HALT
```

DEC at zero is a no-op. JZ jumps to target when its counter is zero.

## 3. Result

Program: copy C0 into C1.

```text
C0=5 C1=0
run
C0=0 C1=5 HALT
snapshot replay: C1=5 HALT
```

Increment-only program: 2 increments then HALT; C0=2.

```text
PASS bounded two-counter machine in chart registers
```

The exact step count is not asserted yet; state/counter simulation is.

## 4. Honest boundary

This is **U1**: bounded 64-bit counters in address-register metadata.
It is not yet:

- multi-limb counters in chart cells;
- atlas paging for unbounded counters;
- a TM encoder;
- a UTM claim.

## 5. Next

1. Move counters from `meta` to multi-limb cells.
2. Add the allocator/page link.
3. Add a reference 2CM orbit test.
4. Only then add TM encoding.
