#!/usr/bin/env python3
"""Checks a model can actually be benchmarked, before a run starts.

Three things have to be true, and each fails differently if it is not checked
here. The model has to be one the agent CLI can reach, or the run burns an
hour producing failures that look like the model being bad at Swift. It has to
be in the pinned catalog, or the report publishes no cost and the omission is
invisible next to models that have one. And the reasoning effort has to be the
strongest the model exposes, because a model held below a rival's effort is
not being compared with it.

Prints the effort to use on stdout, so the caller can pass it straight to the
runner; everything else goes to stderr. Exits non-zero when the run should not
start.

Usage:
    validate-model.py <model-id> [--agent opencode] [--effort <level>]
"""

# Annotations are deferred so these run under the system python3 (3.9),
# which has no `X | None` type syntax. The scripts are called by shebang, so
# whichever python3 is first on PATH is the one that has to cope.
from __future__ import annotations
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Data/model-catalog.json"


def note(message: str) -> None:
    print(message, file=sys.stderr)


def catalog_entry(model: str) -> tuple[dict, str] | None:
    """The pinned entry for a model, matched the way ids actually arrive."""
    if not CATALOG.exists():
        return None
    models = json.loads(CATALOG.read_text()).get("models", {})
    if model in models:
        return models[model], model
    wanted = model.split("/")[-1].lower()
    for identifier, entry in models.items():
        if identifier.split("/")[-1].lower() == wanted:
            return entry, identifier
    return None


def agent_models(agent: str) -> list[str] | None:
    """What the agent CLI says it can reach, or None if it cannot be asked.

    Not being able to ask is different from the model being absent: a missing
    CLI is the operator's problem to see, not grounds to claim the model does
    not exist.
    """
    if agent != "opencode":
        return None
    try:
        result = subprocess.run(
            ["opencode", "models"], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    listed = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    # An empty catalogue is not evidence that a model is missing. `opencode
    # models` fetches its list, and a slow or failed fetch can exit zero with
    # nothing on stdout — which read as "this model does not exist" and
    # refused a run for a model that was there all along.
    return listed or None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("model")
    parser.add_argument("--agent", default="opencode")
    parser.add_argument(
        "--effort",
        help="Override the effort. Checked against the model's ladder and refused when it is not one of its levels.",
    )
    args = parser.parse_args()

    problems: list[str] = []

    # 1. The agent CLI has to be able to reach it.
    available = agent_models(args.agent)
    if available is None:
        note(f"?  {args.agent} returned no model list, so availability is unchecked")
    elif args.model in available:
        note(f"ok {args.model} is available to {args.agent}")
    else:
        near = [m for m in available if args.model.split("/")[-1][:8].lower() in m.lower()]
        problems.append(
            f"{args.agent} does not list {args.model}."
            + (f" Closest: {', '.join(near[:5])}" if near else "")
        )

    # 2. It has to be priced, or the report quietly publishes no cost.
    found = catalog_entry(args.model)
    if found is None:
        problems.append(
            f"{args.model} is not in Data/model-catalog.json, so the run would publish no cost. "
            f"Add it with:  ./Scripts/update-model-catalog.py {args.model}"
        )
        entry, identifier = {}, args.model
    else:
        entry, identifier = found
        rates = entry.get("cost_per_million", {})
        note(f"ok priced as {identifier}: ${rates.get('input')}/${rates.get('output')} per Mtok")

    # 3. Effort has to be the strongest the model exposes.
    ladder: list[str] = []
    for option in entry.get("reasoning_options") or []:
        if option.get("type") == "effort" and option.get("values"):
            ladder = option["values"]
    maximum = entry.get("max_effort")

    effort = args.effort or maximum
    if args.effort and ladder and args.effort not in ladder:
        problems.append(
            f"{args.model} has no effort level {args.effort!r}; it exposes {', '.join(ladder)}."
        )
    elif args.effort and maximum and args.effort != maximum:
        # Allowed, but never silently: the number this produces is not
        # comparable with a run of another model at its own maximum.
        note(f"!! effort {args.effort} is below this model's maximum ({maximum}); scores will not be comparable")
    elif maximum:
        note(f"ok effort {effort}, the strongest of {', '.join(ladder)}")
    elif found is not None:
        note("ok no selectable effort level; the provider default is the only setting")

    if problems:
        note("")
        for problem in problems:
            note(f"error: {problem}")
        return 1


    print(effort or "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
