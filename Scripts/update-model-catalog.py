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

Usage:
    update-model-catalog.py --openrouter        every OpenRouter model opencode
                                                can reach (the usual refresh)
    update-model-catalog.py <model-id> ...      add named models
    update-model-catalog.py                     refresh what reports already scored

Models any published report has scored are always kept, so a refresh can never
drop the prices a published number was computed from.
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

    Ids reach us in three shapes and all three have to land on the same entry:

        minimax/MiniMax-M2.7                provider + model
        openrouter/meta/muse-spark-1.2      gateway + a model whose own id
                                            contains a slash
        opencode/muse-spark-1.3-...-free    the agent's own hosted catalogue

    So the first component is tried as the provider with the whole remainder as
    the model id — which is the only reading that works for the middle case —
    and a last-component match is the fallback for everything else.
    """
    head, _, rest = model.partition("/")
    block = catalog.get(head)
    if block and rest and rest in (block.get("models") or {}):
        return f"{head}/{rest}", block["models"][rest]

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


def page_candidates(source_id: str) -> list[str]:
    """Where a model's price page might live, best first.

    models.dev renders a page per model *owner*, not per route to it, so a
    gateway-prefixed id has no page of its own: `openrouter/anthropic/x`
    redirects to the homepage while `anthropic/x` is the real page. Linking the
    owner is also the more useful answer — it is where the price comes from.
    """
    candidates = [source_id]
    head, _, rest = source_id.partition("/")
    if head in {"openrouter", "opencode", "vercel", "nano-gpt"} and "/" in rest:
        candidates.append(rest)
    return [f"https://models.dev/models/{c}/" for c in candidates]


def verify_urls(source_ids) -> set[str]:
    """Which models.dev pages actually exist.

    A missing page redirects to the site root rather than answering 404, so a
    2xx alone is not proof — the request must not be redirected away.
    """
    from concurrent.futures import ThreadPoolExecutor

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *_args, **_kwargs):
            return None

    opener = urllib.request.build_opener(NoRedirect)

    def check(url: str) -> str | None:
        request = urllib.request.Request(
            url, method="HEAD", headers={"User-Agent": "applebench-harness"}
        )
        try:
            with opener.open(request, timeout=20) as response:
                return url if response.status == 200 else None
        except Exception:
            return None

    with ThreadPoolExecutor(max_workers=12) as pool:
        return {url for url in pool.map(check, source_ids) if url}


def agent_models(agent: str) -> set[str]:
    """Every model id the agent CLI says it can reach."""
    import subprocess

    if agent != "opencode":
        print(f"error: do not know how to list models for {agent}", file=sys.stderr)
        return set()
    try:
        result = subprocess.run(
            ["opencode", "models"], capture_output=True, text=True, timeout=120
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(f"error: could not run `opencode models`: {error}", file=sys.stderr)
        return set()
    if result.returncode != 0:
        print("error: `opencode models` failed", file=sys.stderr)
        return set()
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


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
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}

    # Whatever is already recorded stays recorded. Without this, adding one
    # model by name would rewrite the file with only that model in it and
    # silently un-price everything else — the next publish would drop cost
    # from every report that is not the one being worked on.
    existing: set[str] = set()
    if CATALOG.exists():
        existing = set(json.loads(CATALOG.read_text()).get("models", {}))

    wanted = set(arguments) | known_models() | existing
    if flags & {"--openrouter", "--all-agent-models"}:
        available = agent_models("opencode")
        if "--openrouter" in flags:
            # One gateway, so every model is reachable with the same key and
            # priced on the same page. Mixing routes into one catalog invites
            # a comparison between a model run direct and one run through a
            # gateway that prices it differently.
            available = {m for m in available if m.startswith("openrouter/")}
        wanted |= available
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

    # models.dev does not render a page for every provider it prices, and the
    # ones it lacks redirect to the homepage rather than 404. An unchecked link
    # would therefore look fine and land the reader nowhere, so each is
    # verified and only the ones that resolve are recorded.
    if models:
        candidates = {model: page_candidates(entry["source_id"]) for model, entry in models.items()}
        every = {url for options in candidates.values() for url in options}
        print(f"Checking {len(every)} price page(s)…", file=sys.stderr)
        verified = verify_urls(every)
        linked = 0
        for model, entry in models.items():
            for url in candidates[model]:
                if url in verified:
                    entry["url"] = url
                    linked += 1
                    break
        print(f"  {linked} of {len(models)} have a page to link.", file=sys.stderr)

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
