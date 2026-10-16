"""Charts of prices over time from a headless run (tools/economy_sim.gd), for docs/economy_report.md.

    bin/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/economy_sim.gd -- --years 20 --seed 1
    python tools/economy_report.py

Writes docs/economy/*.png: one chart per key port, prices as a multiple of each good's base price, with the
historical events marked.
"""
import csv
import json
from datetime import date
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "economy"
OUT.mkdir(parents=True, exist_ok=True)

rows = list(csv.DictReader(open(ROOT / "tools" / "out" / "economy.csv")))
history = json.loads((ROOT / "data" / "history.json").read_text(encoding="utf-8"))


def year_of(r):
    d = date.fromisoformat(r["date"])
    return d.year + (d.timetuple().tm_yday - 1) / 365.0


def series(port, good):
    rs = [r for r in rows if r["port"] == port and r["good"] == good]
    return [year_of(r) for r in rs], [float(r["mult"]) for r in rs]


first = year_of(rows[0])
last = year_of(rows[-1])
marks = [(date.fromisoformat(v["date"]), v.get("text", "").split(":")[0].split(".")[0][:40]) for k, v in history.items()
         if not k.startswith("_") and first <= date.fromisoformat(v["date"]).year + 0.5 <= last]


def chart(name, title, lines, note):
    fig, ax = plt.subplots(figsize=(11, 3.6))
    for port, good, label in lines:
        x, y = series(port, good)
        ax.plot(x, y, label=label, linewidth=1.3)
    ax.axhline(1.0, color="#999", linewidth=0.8, linestyle=":")
    for d, text in marks:
        x = d.year + (d.timetuple().tm_yday - 1) / 365.0
        ax.axvline(x, color="#b04030", linewidth=0.8, alpha=0.5)
        ax.text(x, ax.get_ylim()[1] * 0.97, " " + text, rotation=90, va="top", fontsize=7, color="#b04030")
    ax.set_title(title, fontsize=11, loc="left")
    ax.set_ylabel("x base price")
    ax.legend(fontsize=8, loc="upper right", ncol=4)
    ax.text(0.0, -0.22, note, transform=ax.transAxes, fontsize=8, color="#555")
    fig.tight_layout()
    fig.savefig(OUT / f"{name}.png", dpi=90)
    plt.close(fig)
    print("wrote", OUT / f"{name}.png")


chart("port_royal", "Port Royal: an English capital, rich in sugar, hungry for European goods",
      [("port_royal", "sugar", "sugar"), ("port_royal", "rum", "rum"), ("port_royal", "cloth", "cloth"), ("port_royal", "food", "provisions")],
      "The 1692 earthquake wrecks the warehouses: everything spikes, then trade restores supply over months.")
chart("cartagena", "Cartagena: the galeones' fair town",
      [("cartagena", "cloth", "cloth"), ("cartagena", "tools", "tools"), ("cartagena", "silver", "silver"), ("cartagena", "cocoa", "cocoa")],
      "Each spring the fleet floods in European goods (they dip), then sails with the silver (it climbs). The French sack it in 1697.")
chart("smuggling_gap", "The smuggling run: cloth at the Dutch free ports and on the Spanish Main",
      [("st_eustatius", "cloth", "St. Eustatius"), ("willemstad", "cloth", "Willemstad"), ("port_royal", "cloth", "Port Royal"), ("maracaibo", "cloth", "Maracaibo"), ("havana", "cloth", "Havana")],
      "Spain forbids foreign goods: the gap is the smuggler's premium, held open by the guarda costas' seizures.")
chart("bridgetown", "Bridgetown: a sugar island",
      [("bridgetown", "sugar", "sugar"), ("bridgetown", "molasses", "molasses"), ("bridgetown", "food", "provisions"), ("bridgetown", "tools", "tools")],
      "Sugar is cheapest after the harvest (spring) and dearest before it; the summer convoy buys it up. A plantation island pays dear for food and tools.")
