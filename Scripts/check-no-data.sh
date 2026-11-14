#!/bin/bash
# Fails when this repository tracks data that belongs in the AppleBench project:
# reports, run artifacts, backups or archives. The published site data under
# site/_data and site/_benchmarks is the one exception, as redacted copies.
set -euo pipefail
cd "$(dirname "$0")/.."
bad="$(git ls-files | grep -E '^(Reports|Runs|\.applebench)/|\.bak(-|/|$)|(^|/)archive-[0-9]|\.xcresult(/|$)' || true)"
if [ -n "$bad" ]; then
    echo "error: this repository must not track data; move these to the AppleBench project:" >&2
    echo "$bad" | head -20 >&2
    exit 1
fi
echo "ok no data tracked"
