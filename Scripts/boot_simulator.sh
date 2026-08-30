#!/usr/bin/env bash
#
# Boots a simulator by device name, waits until its boot services are up, and
# prints the device UDID on stdout.
#
# `xcodebuild -destination 'name=...,OS=latest'` boots the device implicitly and
# starts attaching the UI-test runner while the simulator is still bringing up
# services. When accessibility is not ready in time the runner dies with
# `Timed out waiting for AX loaded notification` and zero tests execute. Booting
# first and waiting on `simctl bootstatus` removes that race, and passing the
# resulting UDID as `id=` keeps xcodebuild on the device we warmed up.
#
# Usage: udid="$(Scripts/boot_simulator.sh 'iPad Air 11-inch (M4)')"
set -euo pipefail

if (( $# != 1 )); then
  printf 'usage: %s <simulator device name>\n' "$0" >&2
  exit 2
fi

device_name="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

udid="$(
  xcrun simctl list devices available --json \
    | python3 "${script_dir}/select_simulator.py" "${device_name}"
)"

# Printed before the wait so the resolved device survives a bootstatus failure.
printf 'Booting %s (%s)\n' "${device_name}" "${udid}" >&2
# `-b` boots the device when it is shut down, then waits for boot services.
# `bootstatus` polls without a deadline of its own; the caller's job
# `timeout-minutes` is the deliberate bound, so a device that never finishes
# booting fails the job rather than this script.
xcrun simctl bootstatus "${udid}" -b >&2

printf '%s\n' "${udid}"
