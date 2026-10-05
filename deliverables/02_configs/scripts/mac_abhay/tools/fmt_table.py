#!/usr/bin/env python3
"""Align '|'-separated tshark field output (-T fields -E separator='|' -E header=y) into a readable table.
Empty fields become '-' so columns never shift."""
import sys

rows = [line.rstrip("\n").split("|") for line in sys.stdin if line.strip()]
if rows:
    n = max(len(r) for r in rows)
    rows = [[(c.strip() or "-") for c in r] + ["-"] * (n - len(r)) for r in rows]
    widths = [max(len(r[i]) for r in rows) for i in range(n)]
    for r in rows:
        print("  ".join(c.ljust(w) for c, w in zip(r, widths)).rstrip())
