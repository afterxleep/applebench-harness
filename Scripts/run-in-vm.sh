#!/bin/bash
# Run an AppleBench suite against a clean Tart VM.
#
# Why a VM: on this Mac the sandbox has to deny about ninety installed tools
# by name, so a score does not move with whatever the operator happens to have
# installed. A clean guest has none of them, so the denial list collapses to
# the one tool that must never be available: FlowDeck, because using it would
# measure FlowDeck rather than the model. Anything the model fetches for
# itself stays fair game: it pays the tokens to find, download and drive it.
#
# The guest holds Xcode, the iOS runtime, OpenCode and the provider
# definitions. It holds no credentials: the API key is read on the host and
# forwarded to the guest for the run only, so the image can be cloned and
# shared without carrying a secret.
#
# Usage:
#   ./Scripts/run-in-vm.sh --model minimax/MiniMax-M3 [--changed] [--suite gold]
#   ./Scripts/run-in-vm.sh --model … --vm-image applebench-runner
#
# Everything after the known flags is passed through to run-benchmark.sh.
set -euo pipefail

main() {
  root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
  image="applebench-runner"; user="admin"; password="admin"; passthrough=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --vm-image) image="$2"; shift 2 ;;
      --vm-user) user="$2"; shift 2 ;;
      --vm-password) password="$2"; shift 2 ;;
      -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) passthrough+=("$1"); shift ;;
    esac
  done

  for binary in tart sshpass; do
    command -v "$binary" >/dev/null || { echo "error: $binary is required (brew install hudochenkov/sshpass/sshpass)" >&2; exit 1; }
  done
  tart list --format json 2>/dev/null | grep -q "\"$image\"" || { echo "error: no Tart VM named '$image'" >&2; exit 1; }

  # The key never lives in the image. It is read here and handed to the guest
  # for this run only, so the image can be cloned and shared as it stands.
  key="$(python3 - <<'PY'
import json, os, re, sys
path = os.path.expanduser("~/.config/opencode/opencode.jsonc")
if not os.path.exists(path):
    sys.exit(0)
raw = re.sub(r"^\s*//.*$", "", open(path).read(), flags=re.M)
options = json.loads(raw).get("provider", {}).get("minimax", {}).get("options", {})
print(options.get("apiKey", ""))
PY
)"
  [ -n "$key" ] || echo "note: no minimax key found on this host; the guest will need one in its environment" >&2

  echo "AppleBench in a VM"
  echo "  image:  $image (clean guest: nothing installed but Xcode and OpenCode)"
  echo "  denied: flowdeck only"
  echo

  MINIMAX_API_KEY="$key" ./Scripts/run-benchmark.sh \
    --vm "$image" --vm-user "$user" --vm-password "$password" \
    --allow-env MINIMAX_API_KEY \
    "${passthrough[@]+"${passthrough[@]}"}"
}

main "$@"
