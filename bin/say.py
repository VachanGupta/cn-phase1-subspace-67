#!/usr/bin/env python3
"""Append a message to the bus message board: bin/say.py <to> <text...>  (share/outbox.jsonl, one JSON per line)."""
import datetime, json, os, sys
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
to, text = sys.argv[1], " ".join(sys.argv[2:])
line = {"from": "mac_vachan", "to": to, "time": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "text": text}
with open(os.path.join(PROJECT_DIR, "share", "outbox.jsonl"), "a") as f:
    f.write(json.dumps(line) + "\n")
print(json.dumps(line))
