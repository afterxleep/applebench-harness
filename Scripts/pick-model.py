#!/usr/bin/env python3
"""Interactive model picker for the pinned catalog.

Typing a model id from memory is how a run ends up on a name the gateway does
not have, or on a model nobody priced. Everything offered here is in the
catalog, so it is reachable and it has a rate, and the effort comes from the
model's own ladder rather than from whoever is typing.

Type to filter, arrows or page keys to move, Enter to choose, Esc to cancel.
Prints `<model-id>\\t<effort>` on stdout; the effort is empty when the model
exposes no selectable level.

Usage:
    pick-model.py [--prefix openrouter/] [--query <text>]
"""
import argparse
import curses
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Data/model-catalog.json"


def load(prefix: str) -> list[dict]:
    if not CATALOG.exists():
        print(f"error: no catalog at {CATALOG}. Run Scripts/update-model-catalog.py --openrouter", file=sys.stderr)
        raise SystemExit(1)
    document = json.loads(CATALOG.read_text())
    rows = []
    for identifier, entry in document.get("models", {}).items():
        if prefix and not identifier.startswith(prefix):
            continue
        rates = entry.get("cost_per_million", {})
        rows.append({
            "id": identifier,
            "effort": entry.get("max_effort"),
            "input": rates.get("input"),
            "output": rates.get("output"),
        })
    # Cheapest first: the list is long, and price is the axis most likely to
    # decide a pick once the name has been narrowed down.
    return sorted(rows, key=lambda r: ((r["input"] or 0) + (r["output"] or 0), r["id"]))


def matches(rows: list[dict], query: str) -> list[dict]:
    """Every space-separated term must appear, in any order."""
    terms = query.lower().split()
    if not terms:
        return rows
    return [r for r in rows if all(t in r["id"].lower() for t in terms)]


def price(row: dict) -> str:
    if row["input"] == 0 and row["output"] == 0:
        return "free"
    return f"${row['input']:g}/${row['output']:g}"


def run(screen, rows: list[dict], query: str) -> dict | None:
    curses.curs_set(0)
    if curses.has_colors():
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)
        curses.init_pair(2, curses.COLOR_CYAN, -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)

    selected, offset = 0, 0
    while True:
        visible = matches(rows, query)
        selected = max(0, min(selected, len(visible) - 1))
        height, width = screen.getmaxyx()
        body = max(1, height - 4)
        # Keep the cursor inside the window rather than letting the list scroll
        # out from under it when the filter shrinks the results.
        offset = min(offset, max(0, len(visible) - body))
        if selected < offset:
            offset = selected
        elif selected >= offset + body:
            offset = selected - body + 1

        screen.erase()
        header = f" Select a model  ({len(visible)} of {len(rows)})"
        screen.addnstr(0, 0, header.ljust(width - 1), width - 1, curses.A_BOLD)
        screen.addnstr(1, 0, f" filter: {query}_".ljust(width - 1), width - 1,
                       curses.color_pair(2) if curses.has_colors() else 0)

        for index in range(offset, min(len(visible), offset + body)):
            row = visible[index]
            effort = row["effort"] or "—"
            line = f" {row['id']}"
            tail = f"{price(row):>18}  effort {effort:<8}"
            pad = max(1, width - 1 - len(line) - len(tail))
            text = (line + " " * pad + tail)[: width - 1]
            style = curses.color_pair(1) if index == selected and curses.has_colors() else (
                curses.A_REVERSE if index == selected else 0
            )
            screen.addnstr(2 + index - offset, 0, text.ljust(width - 1), width - 1, style)

        footer = " ↑↓ move · PgUp/PgDn · type to filter · Enter select · Esc cancel"
        screen.addnstr(height - 1, 0, footer.ljust(width - 1), width - 1,
                       curses.color_pair(3) if curses.has_colors() else curses.A_DIM)
        screen.refresh()

        key = screen.getch()
        if key in (27,):                                  # Esc
            return None
        if key in (curses.KEY_ENTER, 10, 13):
            return visible[selected] if visible else None
        if key == curses.KEY_UP:
            selected -= 1
        elif key == curses.KEY_DOWN:
            selected += 1
        elif key == curses.KEY_PPAGE:
            selected -= body
        elif key == curses.KEY_NPAGE:
            selected += body
        elif key == curses.KEY_HOME:
            selected = 0
        elif key == curses.KEY_END:
            selected = len(visible) - 1
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            query = query[:-1]
            selected = 0
        elif 32 <= key < 127:
            query += chr(key)
            selected = 0
        selected = max(0, selected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", default="openrouter/",
                        help="Only offer models whose id starts with this. Empty for all.")
    parser.add_argument("--query", default="", help="Start with this filter applied.")
    args = parser.parse_args()

    rows = load(args.prefix)
    if not rows:
        print(f"error: no models matching {args.prefix!r} in the catalog.", file=sys.stderr)
        return 1

    # The picker draws on the terminal, so it needs one. When stdout is a pipe
    # — which is how the caller reads the choice — curses still has to talk to
    # the tty directly.
    if not sys.stdin.isatty():
        print("error: no terminal to draw a picker on; pass --model instead.", file=sys.stderr)
        return 1

    chosen = curses.wrapper(run, rows, args.query)
    if chosen is None:
        print("Cancelled.", file=sys.stderr)
        return 130

    print(f"{chosen['id']}\t{chosen['effort'] or ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
