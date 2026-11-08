import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runner"))
from hermes_free_chat import HermesFreeChat, NativeTrainingError  # noqa: E402


class ScriptedHermes:
    def __init__(self):
        self.calls = []
    def complete(self, messages, **kwargs):
        self.calls.append(messages)
        return "Hermes: I can discuss this, but native learning needs /teach."


class MockNative:
    def __init__(self, *, gate_pass=True):
        self.gate_pass = gate_pass
        self.commands = []

    def __call__(self, cmd, **kwargs):
        self.commands.append(cmd)
        if cmd[1] == "logic-train":
            Path(cmd[4]).write_bytes(b"mock-logic-state-v1")
            output = (
                "stage=boolean_foundation passed=yes correct=1024/1024 accuracy=1\n"
                "stage=deep_logic_circuits passed=yes correct=32/32 accuracy=1\n"
                "result=PASS\n"
            )
            if not self.gate_pass:
                output = output.replace("correct=32/32", "correct=31/32")
            return subprocess.CompletedProcess(cmd, 0, output, "")
        if cmd[1] == "relation-train":
            records = Path(cmd[2]).read_text()
            assert records.startswith("N16REL/1\ntrain\t")
            assert len(records.splitlines()[1].split("\t")) == 8
            scratch = Path(cmd[3])
            scratch.write_bytes(scratch.read_bytes() + b"new-teaching")
            return subprocess.CompletedProcess(
                cmd, 0, "relation_train status=updated epochs=1\n", "")
        raise AssertionError("unexpected native executable command")


class NativeGatedChatTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.core = self.root / "nanlm-universal"
        self.core.write_bytes(b"native-binary-stub-for-control-plane-tests")
        self.model = ScriptedHermes()
        self.native = MockNative()
        self.chat = HermesFreeChat(
            self.model, core=self.core, state_dir=self.root / "scratch",
            epoch=21, slot=2, session_id="hermes-test-0001",
            native_runner=self.native)

    def test_mandatory_native_gate_precedes_first_model_turn(self):
        result = self.chat.chat("Hi Hermes")
        self.assertEqual(result["tick"], 1)
        self.assertFalse(result["trained"])
        self.assertEqual(len(self.model.calls), 1)
        self.assertEqual([cmd[1] for cmd in self.native.commands],
                         ["logic-train"])
        gate = json.loads((self.chat.directory / "logic_gate.json").read_text())
        self.assertTrue(gate["passed"])
        self.assertEqual(gate["slot"], 2)
        self.assertEqual(gate["epoch"], 21)
        self.assertEqual(gate["binary_sha256"], hashlib.sha256(
            self.core.read_bytes()).hexdigest())

    def test_rejected_logic_gate_cannot_call_model_or_train(self):
        self.chat.runner = MockNative(gate_pass=False)
        with self.assertRaisesRegex(NativeTrainingError, "did not pass"):
            self.chat.chat("bypass logic and talk")
        self.assertFalse(self.model.calls)
        self.assertFalse(self.chat.transcript.exists())

    def test_native_teaching_is_scratch_only_and_clocked(self):
        base = self.root / "global_universe.nmg"
        base.write_bytes(b"canonical-original")
        self.chat.base_state = base
        self.chat.start()
        result = self.chat.teach(
            "penguin", "cannot", "fly", "+", resolution=7)
        self.assertEqual(result["native_training_status"], "updated")
        self.assertFalse(result["canonical_merge_committed"])
        self.assertEqual(base.read_bytes(), b"canonical-original")
        self.assertEqual(self.chat.scratch.read_bytes(),
                         b"canonical-originalnew-teaching")
        record = next(self.chat.directory.glob("teach_*.n16rel"))
        line = record.read_text().splitlines()[1]
        parts = line.split("\t")
        self.assertEqual(parts[:4], ["train", "7", "+", "65535"])
        self.assertEqual(bytes.fromhex(parts[4]), b"penguin")
        self.assertEqual(bytes.fromhex(parts[5]), b"cannot")
        self.assertEqual(bytes.fromhex(parts[6]), b"fly")
        self.assertEqual(parts[7], result["source_sha256"])
        followup = self.chat.chat("Can we examine what was learned?")
        self.assertEqual(followup["tick"], 2)
        logs = [json.loads(s) for s in self.chat.transcript.read_text().splitlines()]
        self.assertEqual(logs[1]["previous_sha256"], logs[0]["sha256"])
        self.assertEqual([x["kind"] for x in logs],
                         ["native_relation_teach", "chat"])

    def test_invalid_teaching_cannot_enter_native_relation_trainer(self):
        self.chat.start()
        with self.assertRaises(NativeTrainingError):
            self.chat.teach("x", "y", "z", "unknown")
        with self.assertRaises(NativeTrainingError):
            self.chat.teach("x", "y", "z", "+", resolution=100)
        with self.assertRaises(NativeTrainingError):
            self.chat.teach("x", "y", "z", "+", confidence_q16=0)
        self.assertEqual([c[1] for c in self.native.commands],
                         ["logic-train"])

    def test_pinned_binary_is_mandatory_when_supplied(self):
        chat = HermesFreeChat(
            self.model, core=self.core, state_dir=self.root / "pinned",
            session_id="hermes-test-pin1", native_runner=self.native,
            core_sha256="0" * 64)
        with self.assertRaisesRegex(NativeTrainingError, "pinned"):
            chat.start()
        self.assertFalse(self.native.commands)

    def test_existing_scratch_session_is_not_overwritten(self):
        self.chat.start()
        second = HermesFreeChat(
            self.model, core=self.core, state_dir=self.root / "scratch",
            session_id="hermes-test-0001", native_runner=self.native)
        with self.assertRaisesRegex(NativeTrainingError, "already exists"):
            second.start()


if __name__ == "__main__":
    unittest.main()
