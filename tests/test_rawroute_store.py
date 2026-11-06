import tempfile
import unittest
from pathlib import Path

from nanlmind_nannet.bridge import RunnerRoute
from nanlmind_nannet.rawroute import parse_rawroute
from nanlmind_nannet.rawroute_store import (
    DEFAULT_QUOTA_BYTES,
    RawRouteDB,
    RawRouteMesh,
    RouteConflict,
    RouteQuotaExceeded,
)


class RawRouteStoreTests(unittest.TestCase):
    ROUTE = "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,2,3::vector1337"

    def test_four_namespaces_are_independent_and_sparse(self):
        with tempfile.TemporaryDirectory() as tmp:
            mesh = RawRouteMesh(tmp)
            health = mesh.health()
            self.assertEqual(set(health["namespaces"]), {"BS0", "MC0", "SC0", "GM0"})
            self.assertFalse(health["preallocated"])
            self.assertEqual(len(health["filesystems"]), 4)
            for item in health["namespaces"].values():
                self.assertEqual(item["quota_bytes"], DEFAULT_QUOTA_BYTES)
                self.assertEqual(item["logical_used_bytes"], 0)
                self.assertEqual(item["route_count"], 0)
                self.assertEqual(len(item["shards"]), 1)
                self.assertLess(item["shards"][0]["physical_bytes"], 1024 * 1024)
            names = {p.name for p in Path(tmp).iterdir()}
            self.assertTrue({"bs0db.sqlite3", "mc0db.sqlite3", "sc0db.sqlite3", "gm0db.sqlite3"}.issubset(names))


    def test_mount_manifest_and_volume_expansion_preserve_route_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mounts = {
                "BS0": [root / "bs0db"],
                "MC0": [root / "mc0db-a", root / "mc0db-b"],
                "SC0": [root / "sc0db"],
                "GM0": [root / "gm0db"],
            }
            mesh = RawRouteMesh(mounts=mounts, physical_reserve_bytes=0)
            route = parse_rawroute(self.ROUTE)
            first = mesh.commit("MC0", route, 0, 100,
                                idempotency_key="stable-route-1")
            self.assertEqual(first["generation"], 1)
            self.assertIn(first["shard"], {str(p) for p in mounts["MC0"]})

            expanded = dict(mounts)
            expanded["MC0"] = [*mounts["MC0"], root / "mc0db-c"]
            mesh2 = RawRouteMesh(mounts=expanded, physical_reserve_bytes=0)
            resolved = mesh2.resolve("MC0", route)
            self.assertIsNotNone(resolved)
            self.assertEqual(resolved["generation"], 1)
            second = mesh2.commit("MC0", route, 1, 101,
                                  idempotency_key="stable-route-2")
            self.assertEqual(second["generation"], 2)
            self.assertEqual(second["shard"], first["shard"])
            health = mesh2.health()["namespaces"]["MC0"]
            self.assertEqual(health["route_count"], 1)
            self.assertEqual(len(health["shards"]), 3)

    def test_mount_manifest_rejects_shared_or_relative_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shared = root / "shared"
            mounts = {ns: [shared] for ns in ("BS0", "MC0", "SC0", "GM0")}
            with self.assertRaises(ValueError):
                RawRouteMesh(mounts=mounts)
            mounts = {
                "BS0": ["relative-bs"], "MC0": [root / "mc"],
                "SC0": [root / "sc"], "GM0": [root / "gm"],
            }
            with self.assertRaises(ValueError):
                RawRouteMesh(mounts=mounts)

    def test_commit_resolve_reverse_lookup_and_idempotent_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = RawRouteDB(Path(tmp) / "bs0db.sqlite3", "BS0")
            route = parse_rawroute(self.ROUTE)
            transport = RunnerRoute(gm=0, sc=0, mc=0, bs=0, hw=0, bsr=2)
            first = db.commit(route, base_generation=0, nanclock_tick=44,
                              transport_route=transport,
                              runner_identity="github-actions:shemshallah/nanlm-cpu-3",
                              idempotency_key="round-1-route-1")
            self.assertTrue(first["accepted"])
            self.assertFalse(first["replay"])
            self.assertEqual(first["generation"], 1)

            replay = db.commit(route, base_generation=0, nanclock_tick=44,
                               transport_route=transport,
                               runner_identity="github-actions:shemshallah/nanlm-cpu-3",
                               idempotency_key="round-1-route-1")
            self.assertTrue(replay["replay"])
            self.assertEqual(replay["generation"], 1)

            resolved = db.resolve(route)
            self.assertTrue(resolved["resolved"])
            self.assertEqual(resolved["transport_route"], transport.text())
            self.assertEqual(resolved["runner_identity"],
                             "github-actions:shemshallah/nanlm-cpu-3")
            self.assertEqual(db.reverse_lookup("head", 2), [self.ROUTE])
            self.assertEqual(db.reverse_lookup("vector", 1337), [self.ROUTE])
            self.assertEqual(db.health()["event_count"], 1)

    def test_stale_generation_and_idempotency_collision_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = RawRouteDB(Path(tmp) / "mc0db.sqlite3", "MC0")
            route = parse_rawroute(self.ROUTE)
            db.commit(route, 0, 10, idempotency_key="same-key")
            with self.assertRaises(RouteConflict):
                db.commit(route, 0, 11, idempotency_key="new-key")
            with self.assertRaises(RouteConflict):
                db.commit(route, 0, 10, transport_route=RunnerRoute(bsr=1),
                          idempotency_key="same-key")

    def test_nanclock_must_not_move_backwards(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = RawRouteDB(Path(tmp) / "sc0db.sqlite3", "SC0")
            first = parse_rawroute(self.ROUTE)
            second = parse_rawroute(
                "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:4::hyperedge99")
            db.commit(first, 0, 20)
            with self.assertRaises(RouteConflict):
                db.commit(second, 0, 19)

    def test_unresolved_route_definition_is_not_misreported_as_resolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = RawRouteDB(Path(tmp) / "gm0db.sqlite3", "GM0")
            route = parse_rawroute(self.ROUTE)
            db.commit(route, 0, 1)
            resolved = db.resolve(route)
            self.assertFalse(resolved["resolved"])
            self.assertIsNone(resolved["transport_route"])

    def test_logical_quota_is_enforced_without_preallocation(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = RawRouteDB(Path(tmp) / "bs0db.sqlite3", "BS0", quota_bytes=32)
            route = parse_rawroute(self.ROUTE)
            with self.assertRaises(RouteQuotaExceeded):
                db.commit(route, 0, 1)
            health = db.health()
            self.assertEqual(health["logical_used_bytes"], 0)
            self.assertLess(health["physical_bytes"], 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
