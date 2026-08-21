#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  printf 'No release logs were produced.\n' >&2
  exit 1
fi

logs=("$@")

reject_matches() {
  local rejection_message="$1"
  local scan_error_message="$2"
  shift 2

  local grep_status
  set +e
  grep -n "$@" -- "${logs[@]}"
  grep_status=$?
  set -e

  case "${grep_status}" in
    0)
      printf '%s\n' "${rejection_message}" >&2
      return 1
      ;;
    1)
      return 0
      ;;
    *)
      printf '%s\n' "${scan_error_message}" >&2
      return "${grep_status}"
      ;;
  esac
}

reject_matches \
  'Release-owned build warnings are not allowed.' \
  'Could not scan release logs for warnings.' \
  -i -E '(^|[[:space:]])warning:'

reject_matches \
  'SubscriptionCore runtime definitions must be loaded exactly once.' \
  'Could not scan release logs for duplicate runtime definitions.' \
  -E 'Class (_TtC16SubscriptionCore21SubscriptionWorkspace|_TtC16SubscriptionCore19WidgetSnapshotStore) is implemented in both'

reject_matches \
  'SQLite API-violation diagnostics are not allowed.' \
  'Could not scan release logs for SQLite API violations.' \
  -F 'BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API violation'
