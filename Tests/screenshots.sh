#!/usr/bin/env bash
# Boots an iPhone simulator, runs the app with sample data and saves a screenshot of each screen.
set -uo pipefail
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

size() { stat -f%z "$1" 2>/dev/null || echo 0; }

# A screenshot under ~150 KB is the plain launch screen: the app hasn't drawn yet.
capture() {
  local name="$1"
  for attempt in 1 2 3 4 5 6; do
    xcrun simctl io "$UDID" screenshot "screenshots/$name.png" >/dev/null 2>&1
    if [ "$(size "screenshots/$name.png")" -gt 150000 ]; then echo "saved $name"; return 0; fi
    sleep 3
  done
  echo "WARNING: $name still blank after waiting"
  local pid
  pid=$(pgrep -f "PerkKeeper.app/PerkKeeper" | head -1)
  if [ -n "$pid" ]; then
    echo "app pid $pid is running; sampling its threads"
    sample "$pid" 3 -file "screenshots/hang-$name.txt" >/dev/null 2>&1 || true
  else
    echo "app is not running (crashed?)"
  fi
  return 1
}

shoot() {
  local name="$1" wait="$2"; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  capture "$name"
}

shoot 1-today 7 -demo -tab home
shoot 2-credits 7 -demo -tab credits
shoot 3-offers 6 -demo -tab offers
shoot 4-cards 6 -demo -tab cards
shoot 5-settings 6 -demo -tab settings
shoot 6-sync-start 9 -demo -demoSync
sleep 12; capture 7-sync-adding
sleep 24; capture 8-sync-done
xcrun simctl ui "$UDID" appearance dark || true
shoot 9-today-dark 7 -demo -tab home
shoot 10-credits-dark 7 -demo -tab credits
shoot 11-offers-added-dark 6 -demo -tab offers.added

cp ~/Library/Logs/DiagnosticReports/PerkKeeper* screenshots/ 2>/dev/null || true
xcrun simctl spawn "$UDID" log show --last 6m --style compact --predicate 'process == "PerkKeeper" AND messageType >= 16' > screenshots/app-errors.log 2>/dev/null || true
ls -la screenshots
exit 0
