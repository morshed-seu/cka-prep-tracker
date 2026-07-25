#!/usr/bin/env bash
# Beginner gauntlet fault b14-systemd-01 (B14.5) — plants ONE fault in the
# service-management layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-systemd-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
UNIT=gauntlet-api.service
DROPIN=/etc/systemd/system/${UNIT}.d
PORT=8084

echo "============================================================"
echo " Beginner gauntlet — fault b14-systemd-01"
echo " About to BREAK: a unit that will not start, for a reason its"
echo " own program never gets the chance to report"
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

# ---- wrong-box guards ----
if [ "$(id -u)" -ne 0 ]; then
  echo "ABORT: run with sudo." >&2; exit 1
fi
if [ "$(hostname)" != "sandbox" ]; then
  echo "ABORT: this host is '$(hostname)', not the throwaway 'sandbox' VM." >&2
  echo "Refusing to break a machine that isn't the sandbox." >&2; exit 1
fi
if [ -d /etc/kubernetes ]; then
  echo "ABORT: /etc/kubernetes exists — this looks like a cluster node." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent) ----
install -d -m 755 /srv/gauntlet/api
echo 'gauntlet-api is serving' > /srv/gauntlet/api/index.html
cat > /etc/systemd/system/"$UNIT" <<UNITEOF
[Unit]
Description=B14 gauntlet API
[Service]
ExecStart=/usr/bin/python3 -m http.server $PORT --directory /srv/gauntlet/api
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNITEOF
rm -rf "$DROPIN"
systemctl daemon-reload
systemctl restart "$UNIT"
sleep 2
if [ "$(systemctl is-active "$UNIT")" != "active" ]; then
  echo "ABORT: $UNIT will not run even before the fault is planted." >&2; exit 1
fi

mkdir -p "$BACKUPS"
systemctl cat "$UNIT" > "$BACKUPS/systemd-01.unit.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
mkdir -p "$DROPIN"
cat > "$DROPIN/10-gauntlet.conf" <<'DROPEOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/gauntlet-api --port 8084
DROPEOF
systemctl daemon-reload
systemctl restart "$UNIT" || true

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $UNIT was healthy a moment ago and now refuses to start."
echo "  2. 'journalctl -u $UNIT' contains nothing from the program itself."
echo "     That absence is evidence — work out what it tells you."
echo "  3. Read the failure with 'systemctl status $UNIT' and identify the"
echo "     stage that failed BEFORE any of the program's code ran."
echo "  4. Fix the root cause, then verify:"
echo "       systemctl is-active $UNIT                        →  active"
echo "       curl -s --max-time 3 http://127.0.0.1:$PORT/     →  gauntlet-api is serving"
echo "  5. Do not create a binary at the path in the failing command."
echo
echo "Escape hatch (only if hopelessly stuck): the pre-fault unit is recorded"
echo "in $BACKUPS/systemd-01.unit.* — comparing it with 'systemctl cat $UNIT' gives it away."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
