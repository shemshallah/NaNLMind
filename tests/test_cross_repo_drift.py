"""Negative regression tests for NaN six-runner and shared-contract drift."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))
import cross_repo_drift as drift  # noqa: E402


def fake_cpu_workflow(number: int) -> str:
    n = number - 1
    portal = "$" + "{{ vars.BSR" + str(n) + "_PORTAL_API }}"
    return (
        "name: NaNLMind head runner\n"
        "on:\n  workflow_dispatch:\n    inputs:\n"
        "      slot:\n        description: runner slot 1..6\n"
        f'        type: string\n        default: "{number}"\n'
        "env:\n"
        f"  BSR{n}_PORTAL_API: {portal}\n"
        f"  NANNET_PORTAL_API: {portal}\n"
        f'  NANNET_BOOTSTRAP_SLOT: "{n}"\n'
        "jobs:\n  runner:\n    steps:\n      - run: echo fixed\n")


def manifest_for(root, names):
    result = {}
    for name in names:
        files = {}
        for path in (root / name).rglob("*"):
            if path.is_file():
                sha = hashlib.sha256(path.read_bytes()).hexdigest()
                files[str(path.relative_to(root / name))] = {
                    "sha256": sha, "bytes": path.stat().st_size}
        result[name] = {"head_sha": "0" * 40,
                        "tracked_file_count": len(files),
                        "tracked_files": files}
    return result


class CrossRepoDriftTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for i in range(6):
            self.write(f"nanrouter-runner-{i}", "slot", f"{i}\n")
            self.write(f"nanrouter-runner-{i}", "README.md",
                       f"# nanrouter-runner-{i}\n")
            for p in ("ring_runner.py", "ring_authority_client.py",
                      "slot_fabric.py", "tests/test_ring_runner.py",
                      ".github/workflows/ci.yml", "Dockerfile"):
                self.write(f"nanrouter-runner-{i}", p, "shared source\n")
        for i in range(1, 7):
            self.write(f"nanlm-cpu-{i}", "README.md", f"# nanlm-cpu-{i}\n")
            self.write(f"nanlm-cpu-{i}", ".github/workflows/runner.yml",
                       fake_cpu_workflow(i))

    def write(self, repo, name, content):
        path = self.root / repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def scan(self):
        return manifest_for(self.root, (
            *(f"nanrouter-runner-{i}" for i in range(6)),
            *(f"nanlm-cpu-{i}" for i in range(1, 7))))

    def test_expected_runner_and_cpu_slot_differences_pass(self):
        scan = self.scan()
        self.assertEqual(
            drift.verify_router_runner_family(self.root, scan)["status"], "PASS")
        self.assertEqual(
            drift.verify_cpu_worker_family(self.root, scan)["status"], "PASS")
        self.assertEqual(
            drift.normalize_cpu_workflow(fake_cpu_workflow(1), 1),
            drift.normalize_cpu_workflow(fake_cpu_workflow(6), 6))

    def test_rejects_divergent_router_code_and_inventory(self):
        self.write("nanrouter-runner-5", "ring_runner.py", "malicious drift\n")
        result = drift.verify_router_runner_family(self.root, self.scan())
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("ring_runner.py" in e for e in result["errors"]))
        self.write("nanrouter-runner-5", "new_helper.py", "unreviewed\n")
        result = drift.verify_router_runner_family(self.root, self.scan())
        self.assertTrue(any("source inventory differs" in e
                            for e in result["errors"]))

    def test_rejects_wrong_slot_and_wrong_worker_identity(self):
        self.write("nanrouter-runner-4", "slot", "3\n")
        self.write("nanrouter-runner-4", "README.md", "# nanrouter-runner-5\n")
        errors = drift.verify_router_runner_family(self.root, self.scan())["errors"]
        self.assertTrue(any("slot file" in e for e in errors))
        self.assertTrue(any("README" in e for e in errors))

    def test_rejects_cpu_workflow_drift_and_bad_alias(self):
        original = fake_cpu_workflow(3)
        self.write("nanlm-cpu-3", ".github/workflows/runner.yml",
                   original.replace("echo fixed", "echo different"))
        result = drift.verify_cpu_worker_family(self.root, self.scan())
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("workflow code drift" in e for e in result["errors"]))
        self.write("nanlm-cpu-3", ".github/workflows/runner.yml",
                   original.replace("BSR2_PORTAL_API", "BSR0_PORTAL_API"))
        result = drift.verify_cpu_worker_family(self.root, self.scan())
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(any("portal endpoint" in e for e in result["errors"]))

    def test_rejects_invalid_cpu_slot_identity(self):
        with self.assertRaises(drift.DriftError):
            drift.normalize_cpu_workflow(
                fake_cpu_workflow(2).replace('default: "2"', 'default: "1"'), 2)

    def test_cross_repo_native_contract_digest_mismatch(self):
        scan = {}
        for repo_a, left, repo_b, right in drift.EXACT_CONTRACTS:
            for repo, path in ((repo_a, left), (repo_b, right)):
                scan.setdefault(repo, {"tracked_files": {}})["tracked_files"][path] = {
                    "sha256": "0" * 64, "bytes": 42}
        self.assertEqual(drift.verify_exact_contracts(scan)["status"], "PASS")
        repo, path = drift.EXACT_CONTRACTS[0][:2]
        scan[repo]["tracked_files"][path]["sha256"] = "a" * 64
        report = drift.verify_exact_contracts(scan)
        self.assertEqual(report["status"], "FAIL")
        self.assertEqual(report["contracts"][0]["status"], "FAIL")

    def test_repository_inventory_keeps_empty_named_repo(self):
        self.assertEqual(len(drift.REPOSITORIES), 24)
        self.assertIn("nan0s-android", drift.EXPECTED_EMPTY)
        self.assertEqual(len(set(drift.REPOSITORIES)), 24)


if __name__ == "__main__":
    unittest.main()
