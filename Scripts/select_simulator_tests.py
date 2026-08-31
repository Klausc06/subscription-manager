"""Tests for Scripts/select_simulator.py."""

from __future__ import annotations

import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any

import importlib.util

MODULE_PATH = Path(__file__).with_name("select_simulator.py")
_spec = importlib.util.spec_from_file_location("select_simulator", MODULE_PATH)
assert _spec is not None and _spec.loader is not None
select_simulator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(select_simulator)


def catalog(*entries: tuple[str, str, str, bool]) -> dict[str, Any]:
    """Build a simctl-shaped catalog from (runtime, name, udid, available)."""
    devices: dict[str, list[dict[str, Any]]] = {}
    for runtime, name, udid, available in entries:
        devices.setdefault(runtime, []).append(
            {"name": name, "udid": udid, "isAvailable": available}
        )
    return {"devices": devices}


class SelectSimulatorTests(unittest.TestCase):
    def test_selects_the_matching_device(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPad Air 11-inch (M4)",
                "IPAD-UDID",
                True,
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPhone 17 Pro",
                "IPHONE-UDID",
                True,
            ),
        )
        self.assertEqual(
            select_simulator.select_simulator(document, "iPad Air 11-inch (M4)"),
            "IPAD-UDID",
        )

    def test_prefers_the_newest_ios_runtime(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-26-4",
                "iPhone 17 Pro",
                "OLD-UDID",
                True,
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPhone 17 Pro",
                "NEW-UDID",
                True,
            ),
        )
        self.assertEqual(
            select_simulator.select_simulator(document, "iPhone 17 Pro"),
            "NEW-UDID",
        )

    def test_orders_runtime_versions_numerically(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-10",
                "iPhone 17 Pro",
                "NEWEST-UDID",
                True,
            ),
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-9",
                "iPhone 17 Pro",
                "OLDER-UDID",
                True,
            ),
        )
        self.assertEqual(
            select_simulator.select_simulator(document, "iPhone 17 Pro"),
            "NEWEST-UDID",
        )

    def test_ignores_unavailable_devices(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPhone 17 Pro",
                "UNAVAILABLE-UDID",
                False,
            ),
        )
        with self.assertRaises(select_simulator.NoMatchingSimulator):
            select_simulator.select_simulator(document, "iPhone 17 Pro")

    def test_ignores_non_ios_runtimes(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.watchOS-27-0",
                "iPhone 17 Pro",
                "WATCH-UDID",
                True,
            ),
        )
        with self.assertRaises(select_simulator.NoMatchingSimulator):
            select_simulator.select_simulator(document, "iPhone 17 Pro")

    def test_requires_an_exact_name(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPad Air 13-inch (M4)",
                "THIRTEEN-UDID",
                True,
            ),
        )
        with self.assertRaises(select_simulator.NoMatchingSimulator):
            select_simulator.select_simulator(document, "iPad Air 11-inch (M4)")

    def test_main_writes_only_the_udid_to_stdout(self) -> None:
        document = catalog(
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "iPhone 17 Pro",
                "IPHONE-UDID",
                True,
            ),
        )
        stdout = io.StringIO()
        stderr = io.StringIO()
        original_stdin = select_simulator.sys.stdin
        select_simulator.sys.stdin = io.StringIO(json.dumps(document))
        try:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                status = select_simulator.main(
                    ["select_simulator.py", "iPhone 17 Pro"]
                )
        finally:
            select_simulator.sys.stdin = original_stdin
        self.assertEqual(status, 0)
        self.assertEqual(stdout.getvalue(), "IPHONE-UDID\n")
        self.assertEqual(stderr.getvalue(), "")

    def test_main_fails_closed_without_a_device_name(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            status = select_simulator.main(["select_simulator.py"])
        self.assertEqual(status, 2)
        self.assertIn("usage", stderr.getvalue())

    def test_main_fails_closed_on_unparsable_input(self) -> None:
        stderr = io.StringIO()
        original_stdin = select_simulator.sys.stdin
        select_simulator.sys.stdin = io.StringIO("not json")
        try:
            with redirect_stderr(stderr):
                status = select_simulator.main(
                    ["select_simulator.py", "iPhone 17 Pro"]
                )
        finally:
            select_simulator.sys.stdin = original_stdin
        self.assertEqual(status, 1)
        self.assertIn("could not parse", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
