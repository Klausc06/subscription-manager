#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verifier="${script_dir}/verify_release_logs.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "${verifier}" ]] || fail 'release-log verifier is missing or not executable'

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/verify-release-logs.XXXXXX")"
trap 'rm -rf -- "${fixture_dir}"' EXIT

if "${verifier}" >/dev/null 2>&1; then
  fail 'no log arguments must fail closed'
fi
printf 'PASS: no log arguments fail closed\n'

warning_log="${fixture_dir}/warning.log"
printf 'CompileSwift normal\nwarning: release-owned warning\n' > "${warning_log}"
if "${verifier}" "${warning_log}" >/dev/null 2>&1; then
  fail 'warning diagnostic must be rejected'
fi
printf 'PASS: warning diagnostic is rejected\n'

workspace_duplicate_log="${fixture_dir}/workspace-duplicate.log"
printf '%s\n' \
  'Class _TtC16SubscriptionCore21SubscriptionWorkspace is implemented in both /tmp/A and /tmp/B' \
  > "${workspace_duplicate_log}"
if "${verifier}" "${workspace_duplicate_log}" >/dev/null 2>&1; then
  fail 'SubscriptionWorkspace duplicate diagnostic must be rejected'
fi
printf 'PASS: SubscriptionWorkspace duplicate diagnostic is rejected\n'

widget_store_duplicate_log="${fixture_dir}/widget-store-duplicate.log"
printf '%s\n' \
  'Class _TtC16SubscriptionCore19WidgetSnapshotStore is implemented in both /tmp/A and /tmp/B' \
  > "${widget_store_duplicate_log}"
if "${verifier}" "${widget_store_duplicate_log}" >/dev/null 2>&1; then
  fail 'WidgetSnapshotStore duplicate diagnostic must be rejected'
fi
printf 'PASS: WidgetSnapshotStore duplicate diagnostic is rejected\n'

sqlite_diagnostic_log="${fixture_dir}/sqlite-diagnostic.log"
printf '%s\n' \
  'BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API violation: vnode unlinked while in use' \
  > "${sqlite_diagnostic_log}"
if "${verifier}" "${sqlite_diagnostic_log}" >/dev/null 2>&1; then
  fail 'SQLite API-violation diagnostic must be rejected'
fi
printf 'PASS: SQLite API-violation diagnostic is rejected\n'

clean_log="${fixture_dir}/clean.log"
printf 'Test Suite passed\nBuild Succeeded\n' > "${clean_log}"
if ! "${verifier}" "${clean_log}" >/dev/null 2>&1; then
  fail 'clean release log must pass'
fi
printf 'PASS: clean release log passes\n'

webkit_duplicate_log="${fixture_dir}/webkit-webcore-duplicate.log"
printf '%s\n' \
  'Class WKContentWorld is implemented in both /System/Library/Frameworks/WebKit.framework/WebKit and /tmp/WebCore.framework/WebCore' \
  > "${webkit_duplicate_log}"
if ! "${verifier}" "${webkit_duplicate_log}" >/dev/null 2>&1; then
  fail 'unrelated WebKit/WebCore duplicate diagnostic must pass'
fi
printf 'PASS: unrelated WebKit/WebCore duplicate diagnostic passes\n'
