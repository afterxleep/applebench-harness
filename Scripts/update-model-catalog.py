#!/usr/bin/env python3
"""Refreshes the pinned model catalog from models.dev.

A benchmark that reports cost has to say whose cost it is. The agent CLI
reports what *it* was billed, which moves with the caller's provider, plan and
discounts: fitting a price to the MiniMax runs opencode reported gives a
*negative* input rate, which no real tariff has. Numbers like that cannot be
compared between two models, let alone published.

So cost is computed here instead, from tokens the harness counted and the
model owner's list price. models.dev is the registry opencode itself reads,
it is open source, and it carries the two things a run needs to be described
honestly:

  cost               list price per million tokens, as the owner charges
  reasoning_options  the effort ladder the model actually exposes

The snapshot is *pinned*, not fetched at export time. A published score must
not move because a provider changed its prices on a Tuesday; re-running this
script is a deliberate act that shows up as a diff, with `retrieved` saying
when the prices were true.

Only models the benchmark has actually scored are written, so the file stays
small enough to read in a review. Pass model ids to add new ones.

Usage:
    update-model-catalog.py [model-id ...]
"""
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Data/model-catalog.json"
SOURCE = "https://models.dev/api.json"


def known_models() -> set[str]:
    """Every model id any published report has scored."""
    found = set()
    for path in (ROOT / "Reports").glob("*.json"):
        try:
            document = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        for run in document.get("runs", []):
            model = run.get("agent", {}).get("model")
            if model:
                found.add(model)
    return found


def resolve(catalog: dict, model: str) -> tuple[str, dict] | None:
    """Find a models.dev entry for one of our model ids.

    Ids reach us in several shapes — `minimax/MiniMax-M2.7`, and the same model
    through a gateway as `openrouter/minimax/minimax-m3` — so the last path
    component is matched case-insensitively, preferring the provider we named.
    """
    parts = model.split("/")
    wanted = parts[-1].lower()
    preferred = parts[-2].lower() if len(parts) > 1 else None

    matches = []
    for provider, block in catalog.items():
        for identifier, entry in (block.get("models") or {}).items():
            if identifier.lower() == wanted:
                matches.append((provider, identifier, entry))
    if not matches:
        return None
    for provider, identifier, entry in matches:
        if provider.lower() == preferred:
            return f"{provider}/{identifier}", entry
    provider, identifier, entry = matches[0]
    return f"{provider}/{identifier}", entry


def max_effort(entry: dict) -> str | None:
    """The strongest setting the model exposes, or None when it exposes none.

    A model with no `effort` option has no ladder to climb. Saying "max" for it
    would claim a setting that does not exist, so the honest answer is nothing
    and the report says the provider default was used.
    """
    for option in entry.get("reasoning_options") or []:
        if option.get("type") == "effort" and option.get("values"):
            return option["values"][-1]
    return None


def main() -> int:
    wanted = set(sys.argv[1:]) | known_models()
    if not wanted:
        print("error: no models to record; pass ids or publish a report first", file=sys.stderr)
        return 1

    print(f"Fetching {SOURCE} …", file=sys.stderr)
    # models.dev answers 403 to urllib's default agent; identify the caller.
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "applebench-harness"})
    with urllib.request.urlopen(request, timeout=60) as response:
        catalog = json.load(response)

    models, missing = {}, []
    for model in sorted(wanted):
        found = resolve(catalog, model)
        if not found:
            missing.append(model)
            continue
        source_id, entry = found
        cost = entry.get("cost") or {}
        # `is None`, not falsiness: a free tier is priced at 0, and 0 is a
        # real price. Treating it as missing would drop the model from the
        # catalog entirely, and the run would then publish no cost at all
        # rather than the zero it actually cost.
        if cost.get("input") is None or cost.get("output") is None:
            missing.append(model)
            continue
        models[model] = {
            "source_id": source_id,
            "name": entry.get("name"),
            "cost_per_million": {
                "input": cost["input"],
                "output": cost["output"],
                **({"cache_read": cost["cache_read"]} if cost.get("cache_read") else {}),
            },
            "reasoning": bool(entry.get("reasoning")),
            "reasoning_options": entry.get("reasoning_options") or [],
            "max_effort": max_effort(entry),
        }

    # The date models.dev states for itself, not today: it is the day these
    # prices were true, and re-running the script on an unchanged upstream
    # should not produce a diff that claims otherwise.
    document = {
        "source": SOURCE,
        "source_note": "Model owners' list prices, in USD per million tokens.",
        "retrieved": __import__("datetime").date.today().isoformat(),
        "models": models,
    }
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")

    print(f"Wrote {CATALOG.relative_to(ROOT)} with {len(models)} model(s).")
    for model, entry in models.items():
        rates = entry["cost_per_million"]
        effort = entry["max_effort"] or "none exposed"
        print(f"  {model:34} ${rates['input']}/${rates['output']} per Mtok · max effort: {effort}")
    for model in missing:
        print(f"  !! no priced entry on models.dev for {model}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
