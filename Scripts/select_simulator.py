#!/usr/bin/env python3
"""Select a simulator UDID from `simctl list devices available --json`.

Reads the JSON document on stdin so the selection is testable without a
simulator host, and writes the chosen UDID to stdout. Among the devices whose
name matches exactly, the one on the newest iOS runtime wins.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any, Iterator

RUNTIME_PATTERN = re.compile(r"iOS-(\d+(?:-\d+)*)$")


class NoMatchingSimulator(Exception):
    """Raised when no available device carries the requested name."""


def runtime_version(identifier: str) -> tuple[int, ...] | None:
    """Return the iOS version of a runtime identifier, or None for other OSes."""
    match = RUNTIME_PATTERN.search(identifier)
    if match is None:
        return None
    return tuple(int(part) for part in match.group(1).split("-"))


def candidates(catalog: Any, device_name: str) -> Iterator[tuple[tuple[int, ...], str]]:
    devices = catalog.get("devices", {}) if isinstance(catalog, dict) else {}
    if not isinstance(devices, dict):
        return
    for runtime, entries in devices.items():
        version = runtime_version(runtime)
        if version is None or not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if entry.get("name") != device_name:
                continue
            if not entry.get("isAvailable", False):
                continue
            udid = entry.get("udid")
            if isinstance(udid, str) and udid:
                yield version, udid


def select_simulator(catalog: Any, device_name: str) -> str:
    matches = sorted(candidates(catalog, device_name))
    if not matches:
        raise NoMatchingSimulator(
            f"no available simulator named {device_name!r}"
        )
    return matches[-1][1]


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        sys.stderr.write(f"usage: {argv[0] if argv else 'select_simulator.py'} <device name>\n")
        return 2
    try:
        catalog = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        sys.stderr.write(f"could not parse the simulator catalog: {error}\n")
        return 1
    try:
        print(select_simulator(catalog, argv[1]))
    except NoMatchingSimulator as error:
        sys.stderr.write(f"{error}\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
