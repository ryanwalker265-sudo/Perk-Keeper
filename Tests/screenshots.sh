#!/usr/bin/env bash
# Boots an iPhone simulator, runs the app with sample data and saves a screenshot of each screen.
set -euo pipefail
APP="$1"
BUNDLE=com.perkkeeper.app
mkdir -p screenshots

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = json.load(sys.stdin)["devices"]
best = None
for rt, items in devs.items():
    if "iOS" not in rt:
        continue
    for d in items:
        n = d["name"]
        if n.startswith("iPhone") and "Pro" in n and "Max" not in n:
            if best is None or rt > best[0]:
                best = (rt, d["udid"], n)
if best is None:
    for rt, items in devs.items():
        for d in items:
            if "iOS" in rt and d["name"].startswith("iPhone"):
                best = (rt, d["udid"], d["name"])
print(best[1] if best else "")
')
[ -n "$UDID" ] || { echo "No iPhone simulator found"; xcrun simctl list devices; exit 1; }
echo "Using simulator $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

shoot() {
  local name="$1" wait="$2"; shift 2
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "screenshots/$name.png" >/dev/null
  echo "saved $name"
}

shoot 1-today 7 -demo -tab home
shoot 2-credits 5 -demo -tab credits
shoot 3-offers 5 -demo -tab offers
shoot 4-cards 5 -demo -tab cards
shoot 5-settings 5 -demo -tab settings
shoot 6-sync-start 9 -demo -demoSync
sleep 14
xcrun simctl io "$UDID" screenshot screenshots/7-sync-adding.png >/dev/null && echo "saved 7-sync-adding"
sleep 22
xcrun simctl io "$UDID" screenshot screenshots/8-sync-done.png >/dev/null && echo "saved 8-sync-done"
xcrun simctl ui "$UDID" appearance dark || true
shoot 9-today-dark 6 -demo -tab home
shoot 10-offers-dark 5 -demo -tab offers.added
