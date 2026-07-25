#!/usr/bin/env bash
# Beginner gauntlet fault b14-iptables-01 (B14.5) — plants ONE fault in the
# packet-filter layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-iptables-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
UNIT=gauntlet-web.service
PORT=8082

echo "============================================================"
echo " Beginner gauntlet — fault b14-iptables-01"
echo " About to BREAK: reachability of a service that stays healthy"
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
install -d -m 755 /srv/gauntlet/www
echo 'gauntlet-web is serving' > /srv/gauntlet/www/index.html
cat > /etc/systemd/system/"$UNIT" <<UNITEOF
[Unit]
Description=B14 gauntlet web server
[Service]
ExecStart=/usr/bin/python3 -m http.server $PORT --directory /srv/gauntlet/www
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl restart "$UNIT"
sleep 2
if ! curl -sf --max-time 3 "http://127.0.0.1:$PORT/" >/dev/null; then
  echo "ABORT: the web server is not reachable even before the fault." >&2
  echo "Check 'systemctl status $UNIT' and re-run." >&2; exit 1
fi

mkdir -p "$BACKUPS"
iptables-save > "$BACKUPS/iptables-01.rules.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
iptables -I INPUT -p tcp --dport "$PORT" -j DROP

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $UNIT is running and healthy — check it, and believe it."
echo "  2. Reproduce the symptom:  curl -s --max-time 3 http://127.0.0.1:$PORT/"
echo "  3. Note what it does (and does NOT do) compared with a refused connection."
echo "  4. Fix the root cause, then verify:"
echo "       curl -s --max-time 3 http://127.0.0.1:$PORT/   →  gauntlet-web is serving"
echo "  5. Do not flush every table wholesale — remove the offending rule only."
echo
echo "Escape hatch (only if hopelessly stuck): the pre-fault ruleset is in"
echo "$BACKUPS/iptables-01.rules.* and can be replayed with iptables-restore."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
