#!/usr/bin/env bash
# Beginner gauntlet fault b14-cgroup-01 (B14.5) — plants ONE fault in the
# resource-limit layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-cgroup-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
UNIT=gauntlet-worker.service
DROPIN=/etc/systemd/system/${UNIT}.d

echo "============================================================"
echo " Beginner gauntlet — fault b14-cgroup-01"
echo " About to BREAK: a working service, without touching its program"
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
cat > /etc/systemd/system/"$UNIT" <<'UNITEOF'
[Unit]
Description=B14 gauntlet worker (allocates 64 MiB, then idles)
[Service]
ExecStart=/usr/bin/python3 -c "b = bytearray(64*1024*1024); import time; time.sleep(3600)"
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNITEOF
rm -rf "$DROPIN"
systemctl daemon-reload
systemctl restart "$UNIT"
sleep 3
if [ "$(systemctl is-active "$UNIT")" != "active" ]; then
  echo "ABORT: the worker will not run even before the fault is planted." >&2
  echo "Check 'systemctl status $UNIT' and re-run." >&2; exit 1
fi

mkdir -p "$BACKUPS"
echo "$UNIT had no drop-in directory before the fault" \
  > "$BACKUPS/cgroup-01.note.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
mkdir -p "$DROPIN"
printf '[Service]\nMemoryMax=16M\n' > "$DROPIN/10-gauntlet.conf"
systemctl daemon-reload
systemctl restart "$UNIT" || true

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $UNIT was healthy a moment ago and is now failing."
echo "  2. Its own program was not modified, and its log says nothing useful."
echo "  3. Find why it dies, fix the root cause, then verify it stays up:"
echo "       systemctl is-active $UNIT   →  active"
echo "       sleep 60; systemctl is-active $UNIT   →  still active"
echo "  4. Do not edit the ExecStart line or shrink what the program allocates."
echo
echo "Escape hatch (only if hopelessly stuck): the fault is confined to a"
echo "drop-in under /etc/systemd/system/ — a note is in $BACKUPS/cgroup-01.note.*"
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
