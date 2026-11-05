#!/usr/bin/env python3
"""e13_spef_coupling.py — crosstalk exposure from the post-route OpenRCX SPEF.

For every *D_NET the SPEF gives a total capacitance and a *CAP section whose
lines are either grounded caps ("id node value") or coupling caps
("id node1 node2 value").  This script sums both kinds per net and reports,
for clock nets and for all other nets, how much of the wire capacitance is
coupling to a neighbour (the part that crosstalk can modulate: x0 when the
aggressor switches in the same direction, x2 when it switches opposite).

Clock nets are taken from runs/<run>/reports/.../e13_clock_nets.txt (written
by scripts/e13_xtalk.tcl from the ODB: every net between the clock source and
a register CK pin), so useful-skew delay-buffer nets count as clock nets too.

It also checks whether each coupling cap is listed in both nets' sections
(how OpenSTA applies -coupling_reduction_factor depends on that).

usage: scripts/e13_spef_coupling.py RUN [RUN ...]   -> results/e13_coupling.csv
       scripts/e13_spef_coupling.py --scale RUN K OUT.spef [clock|all]
            write a copy of RUN's SPEF with the coupling caps in the *CAP
            sections of clock nets only (default) or of all nets multiplied
            by K (grounded caps unchanged); the D_NET total is updated.
            Needed because read_spef -coupling_reduction_factor does not work
            for factors other than 0 and 1 in this OpenSTA: the member that
            stores it is declared `bool coupling_cap_factor_;`
            (parasitics/SpefReaderPvt.hh), so 0.5, 1.5 and 2 all act as 1.
"""
import csv
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# other designs: RUNS_DIR=runs_big E13_SUB=nangate45/ariane133/base E13_OUT=...
import os
RUNS = os.environ.get("RUNS_DIR", "runs")
SUB = Path(os.environ.get("E13_SUB", "nangate45/ibex/base"))


def spef_path(run):
    return REPO / RUNS / run / "results" / SUB / "6_final.spef"


def clock_nets(run):
    p = REPO / RUNS / run / "reports" / SUB / "e13_clock_nets.txt"
    return {l.strip() for l in p.read_text().splitlines() if l.strip()}


def parse(run):
    """yield (net_name, total, ground, coupling, [other-net ids]) per D_NET."""
    names = {}
    sect = None
    net = tot = gnd = cpl = None
    partners = []
    with open(spef_path(run)) as f:
        for line in f:
            if line.startswith("*NAME_MAP"):
                sect = "map"; continue
            if line.startswith("*D_NET"):
                _, nid, t = line.split()
                net, tot, gnd, cpl, partners = nid, float(t), 0.0, 0.0, []
                sect = "net"; continue
            if sect == "map":
                if line.startswith("*") and not line.startswith("*PORTS"):
                    k, v = line.split(None, 1)
                    names[k] = v.strip()
                elif line.startswith("*PORTS"):
                    sect = None
                continue
            if sect == "net":
                if line.startswith("*CAP"):
                    sect = "cap"; continue
            if sect == "cap":
                if line.startswith("*RES") or line.startswith("*END"):
                    yield names.get(net, net), tot, gnd, cpl, partners
                    sect = None if line.startswith("*END") else "res"
                    continue
                p = line.split()
                if len(p) == 3:
                    gnd += float(p[2])
                elif len(p) == 4:
                    cpl += float(p[3])
                    # the node that is not on this net names the aggressor
                    for n in (p[1], p[2]):
                        nn = n.split(":")[0]
                        if nn != net:
                            partners.append(nn)
            if sect == "res" and line.startswith("*END"):
                sect = None


def summarize(run):
    ck = clock_nets(run)
    agg = {"clock": [0, 0.0, 0.0, 0.0], "other": [0, 0.0, 0.0, 0.0]}
    per = []
    for name, tot, gnd, cpl, _ in parse(run):
        k = "clock" if name in ck else "other"
        a = agg[k]
        a[0] += 1; a[1] += tot; a[2] += gnd; a[3] += cpl
        if k == "clock":
            per.append(cpl / (gnd + cpl) if gnd + cpl > 0 else 0.0)
    per.sort()
    med = per[len(per) // 2] if per else 0.0
    rows = []
    for k in ("clock", "other"):
        n, tot, gnd, cpl = agg[k]
        rows.append({
            "run": run, "nets": k, "count": n,
            "total_cap_pF": f"{tot:.4f}", "ground_cap_pF": f"{gnd:.4f}",
            "coupling_cap_pF": f"{cpl:.4f}",
            "coupling_frac": f"{cpl / (gnd + cpl):.4f}" if gnd + cpl else "",
            "median_net_coupling_frac": f"{med:.4f}" if k == "clock" else "",
            "clock_nets_found": len(ck) if k == "clock" else "",
        })
    return rows


def both_sides(run, sample=20000):
    """fraction of coupling caps (first `sample` seen) listed in both nets."""
    seen = {}
    with open(spef_path(run)) as f:
        net = None; incap = False
        for line in f:
            if line.startswith("*D_NET"):
                net = line.split()[1]; incap = False; continue
            if line.startswith("*CAP"):
                incap = True; continue
            if line.startswith("*RES") or line.startswith("*END"):
                incap = False; continue
            if incap:
                p = line.split()
                if len(p) == 4:
                    key = tuple(sorted((p[1], p[2])))
                    seen.setdefault(key, set()).add(net)
    pairs = list(seen.values())
    both = sum(1 for s in pairs if len(s) >= 2)
    return both, len(pairs)


def scale(run, k, out, which="clock"):
    ck = clock_nets(run)
    names = {}
    lines = open(spef_path(run)).read().splitlines(keepends=True)
    # pass 1: name map
    inmap = False
    for line in lines:
        if line.startswith("*NAME_MAP"):
            inmap = True; continue
        if inmap:
            if line.startswith("*PORTS") or line.startswith("*D_NET"):
                break
            if line.startswith("*"):
                a, b = line.split(None, 1); names[a] = b.strip()
    # pass 2: rewrite, buffering each net so its total can be fixed up
    w = open(out, "w")
    i = 0; n_scaled = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith("*D_NET"):
            w.write(line); i += 1; continue
        _, nid, t = line.split()
        is_ck = which == "all" or names.get(nid, nid) in ck
        buf = []; add = 0.0; j = i + 1; incap = False
        while True:
            l = lines[j]
            if l.startswith("*CAP"):
                incap = True
            elif l.startswith("*RES") or l.startswith("*END"):
                incap = False
            elif incap and is_ck:
                p = l.split()
                if len(p) == 4:
                    v = float(p[3]); add += v * (k - 1)
                    l = f"{p[0]} {p[1]} {p[2]} {v * k:g}\n"
            buf.append(l)
            j += 1
            if l.startswith("*END"):
                break
        if is_ck:
            n_scaled += 1
        w.write(f"*D_NET {nid} {float(t) + add:g}\n")
        w.writelines(buf)
        i = j
    w.close()
    print(f"scaled coupling x{k} on {n_scaled} {which} nets of {run} -> {out}")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--scale":
        scale(sys.argv[2], float(sys.argv[3]), sys.argv[4],
              sys.argv[5] if len(sys.argv) > 5 else "clock"); return
    if len(sys.argv) >= 2 and sys.argv[1] == "--both":
        for r in sys.argv[2:]:
            b, n = both_sides(r)
            print(f"{r}: coupling caps listed in both nets' sections: {b}/{n}")
        return
    rows = []
    for r in sys.argv[1:]:
        rows += summarize(r)
        print(rows[-2]); print(rows[-1])
    out = REPO / "results" / os.environ.get("E13_OUT", "e13_coupling.csv")
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader(); wr.writerows(rows)
    print("wrote", out)


if __name__ == "__main__":
    main()
