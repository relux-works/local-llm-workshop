#!/usr/bin/env python3
"""Merge the workshop providers into ~/.pi/agent/models.json, keeping existing providers; backs the file up first."""
import json, os, shutil, sys, time
src = sys.argv[1] if len(sys.argv) > 1 else "pi-models.json"
dst = os.path.expanduser("~/.pi/agent/models.json")
os.makedirs(os.path.dirname(dst), exist_ok=True)
cur = {"providers": {}}
if os.path.exists(dst):
    shutil.copy2(dst, dst + time.strftime(".bak-%Y%m%dT%H%M%S"))
    cur = json.load(open(dst))
cur.setdefault("providers", {}).update(json.load(open(src))["providers"])
json.dump(cur, open(dst, "w"), indent=2)
print("providers now:", ", ".join(sorted(cur["providers"])))
