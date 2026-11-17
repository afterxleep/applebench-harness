#!/usr/bin/env python3
"""Draw the charts for the Sonnet 5.5 vs GLM 5.3 Flash post from the published data.

Reads site/_data/reports/<model>.json and site/_data/benchmarks/<model>.csv and
writes three SVGs to site/assets/img/blog/. Nothing is typed in by hand.
"""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1] / "site"
OUT = ROOT / "assets/img/blog"
MODELS = [("claude-sonnet-5-5", "Sonnet 5.5 (High)", "Sonnet 5.5", "#9a6700"),
          ("glm-5-3-flash", "GLM 5.3 Flash (Max)", "GLM 5.3 Flash", "#005eb8")]
FONT = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"


def load(slug):
    rep = json.load(open(ROOT / f"_data/reports/{slug}.json"))
    pct = rep["score"]["percentage"]
    active = sum((r["metrics"].get("agent_duration_seconds") or r["result"].get("duration_seconds") or 0)
                 for r in rep["runs"])
    cost = sum(float(r["list_cost_usd"] or 0) for r in csv.DictReader(open(ROOT / f"_data/benchmarks/{slug}.csv")))
    return {"pct": pct, "cost": cost, "min_per_pt": active / pct / 60}


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'font-family="{FONT}"><rect width="{w}" height="{h}" fill="#ffffff"/>{body}</svg>\n')


def bars(title, sub, rows, fmt, maxv):
    w, h, x0, x1 = 720, 70 + 46 * len(rows), 190, 600
    out = [f'<text x="24" y="32" font-size="20" font-weight="700" fill="#1d1d1f">{title}</text>',
           f'<text x="24" y="52" font-size="13" fill="#6e6e73">{sub}</text>']
    for i, (label, v, color) in enumerate(rows):
        y = 78 + i * 46
        out += [f'<text x="24" y="{y + 15}" font-size="14" fill="#1d1d1f">{label}</text>',
                f'<rect x="{x0}" y="{y}" width="{x1 - x0}" height="20" rx="4" fill="#e8e8ed"/>',
                f'<rect x="{x0}" y="{y}" width="{(x1 - x0) * v / maxv:.1f}" height="20" rx="4" fill="{color}"/>',
                f'<text x="{x1 + 12}" y="{y + 15}" font-size="14" font-weight="600" fill="#1d1d1f">{fmt(v)}</text>']
    return svg(w, h, "".join(out))


def scatter(data):
    w, h, x0, x1, y0, y1 = 720, 330, 70, 680, 80, 270
    xmax = 7.0
    out = ['<text x="24" y="32" font-size="20" font-weight="700" fill="#1d1d1f">AppleBench score vs total cost</text>',
           '<text x="24" y="52" font-size="13" fill="#6e6e73">Up is a higher score. Left is cheaper.</text>']
    for p in (0, 25, 50, 75, 100):
        y = y1 - (y1 - y0) * p / 100
        out += [f'<line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}" stroke="#d2d2d7"/>',
                f'<text x="{x0 - 10}" y="{y + 4}" font-size="12" text-anchor="end" fill="#515154">{p}%</text>']
    for t in range(0, 8):
        x = x0 + (x1 - x0) * t / xmax
        out += [f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y1 + 5}" stroke="#a9a9af"/>',
                f'<text x="{x}" y="{y1 + 22}" font-size="12" text-anchor="middle" fill="#515154">${t}</text>']
    out.append(f'<text x="{x0}" y="{y1 + 48}" font-size="13" fill="#515154">Suite cost (list price)</text>')
    for slug, _, name, color in MODELS:
        d = data[slug]
        x = x0 + (x1 - x0) * d["cost"] / xmax
        y = y1 - (y1 - y0) * d["pct"] / 100
        out += [f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{color}"/>',
                f'<text x="{x + 14:.1f}" y="{y + 5:.1f}" font-size="15" font-weight="600" fill="{color}">{name}</text>',
                f'<text x="{x + 14:.1f}" y="{y + 22:.1f}" font-size="12" fill="#515154">{d["pct"]:.1f}% · ${d["cost"]:.2f}</text>']
    return svg(w, h, "".join(out))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = {slug: load(slug) for slug, *_ in MODELS}
    (OUT / "score.svg").write_text(bars(
        "AppleBench score", "Weighted capability score. Higher is better.",
        [(label, data[s]["pct"], c) for s, label, _, c in MODELS], lambda v: f"{v:.1f}%", 100))
    (OUT / "score-vs-cost.svg").write_text(scatter(data))
    (OUT / "time-per-point.svg").write_text(bars(
        "Active time per percentage point", "Agent time divided by score points. Lower is faster.",
        [(label, data[s]["min_per_pt"], c) for s, label, _, c in MODELS], lambda v: f"{v:.1f}m / pct pt",
        max(d["min_per_pt"] for d in data.values())))
    print({k: {a: round(b, 3) for a, b in v.items()} for k, v in data.items()})


main()
