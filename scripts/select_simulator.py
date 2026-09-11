#!/usr/bin/env python3
"""Select an available iPhone simulator with runtime >= the app's iOS 26 minimum."""
import json
import re
import subprocess

inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
candidates = []
for runtime, devices in inventory["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match or int(match[1]) < 26:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((int(match[1]), int(match[2])), device["name"], device["udid"]))
if not candidates:
    raise SystemExit("No available iPhone simulator with iOS >= 26; install a compatible runtime.")
print(sorted(candidates)[-1][2])
