# Conversational training loop

## What the loop does

```text
HERMES/model turn
  -> JSON training intent
  -> staged NaNLMind pipeline
  -> measured accuracy
  -> reflection turn
  -> next training intent
```

The loop is implemented in `runner/conversation_trainer.py`.

## Model clients

- `OpenAICompatibleClient` — any `/chat/completions` endpoint;
- `HermesModelClient` — wraps a HERMES context with `ctx.llm.complete`;
- `DeterministicPlanner` — local fallback for Termux and tests.

The model is asked for a stage and a conversational message. If it returns
invalid JSON, the loop falls back to the configured stage.

## Run

```sh
python3 runner/conversation_trainer.py \
  --rounds 5 --seconds 0.5 --max-samples 1024 \
  --message "Train logic first, then words."
```

With an OpenAI-compatible model:

```sh
NANLM_MODEL_URL=https://... NANLM_MODEL_TOKEN=... \
python3 runner/conversation_trainer.py --model hermes
```

The loop writes a per-round JSONL transcript and a summary:

```text
state/conversation_training/conversation_<epoch>_<slot>.jsonl
state/conversation_training/summary_<epoch>_<slot>.json
```

## HERMES integration

```python
from conversation_trainer import (
    ConversationConfig, ConversationTrainer, HermesModelClient)

trainer = ConversationTrainer(
    HermesModelClient(ctx),
    ConversationConfig(rounds=5, seconds=0.5),
)
result = trainer.run("Train deep logic, then word choice.")
```

`MemoryMergeClient` posts the aggregate stage score to the Koyeb merge endpoint
when `NANLM_MERGE_URL` / `NANLM_MERGE_TOKEN` are configured.

## Interpretation

This is a real host/model→pipeline→metrics→model loop. It is not proof that the
conversational model learned the corpus; each round records the pipeline metric
and reflection separately so the two claims stay distinguishable.
