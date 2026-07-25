#!/usr/bin/env bash
# Beginner gauntlet fault b14-dns-01 (B14.5) — plants ONE fault in the
# name-resolution layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-dns-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
NSSWITCH=/etc/nsswitch.conf
NAME=gauntlet.svc
PORT=8082

echo "============================================================"
echo " Beginner gauntlet — fault b14-dns-01"
echo " About to BREAK: a name that is spelled correctly everywhere"
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
if ! grep -qE '^hosts:.*\bfiles\b' "$NSSWITCH"; then
  echo "ABORT: $NSSWITCH does not have a normal 'hosts:' line with 'files'." >&2
  echo "A fault may already be planted — restore it first." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent) ----
grep -q "[[:space:]]$NAME\$" /etc/hosts || echo "127.0.0.1 $NAME" >> /etc/hosts
if ! getent hosts "$NAME" >/dev/null; then
  echo "ABORT: $NAME does not resolve even before the fault." >&2; exit 1
fi

mkdir -p "$BACKUPS"
cp -a "$NSSWITCH" "$BACKUPS/dns-01.nsswitch.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
sed -i -E 's/^(hosts:.*)\bfiles\b[[:space:]]*/\1/' "$NSSWITCH"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. The name '$NAME' no longer resolves for any program."
echo "  2. Reproduce it:  getent hosts $NAME   (and: curl -s --max-time 3 http://$NAME:$PORT/)"
echo "  3. The entry mapping that name is still present, correct, and readable."
echo "     Prove that to yourself before you start editing anything."
echo "  4. Fix the root cause, then verify BOTH of these:"
echo "       getent hosts $NAME            →  127.0.0.1 $NAME"
echo "       ping -c1 $NAME                →  replies from 127.0.0.1"
echo "  5. Do not add the name to a DNS server — it never needed one."
echo
echo "Escape hatch (only if hopelessly stuck): the original file is in"
echo "$BACKUPS/dns-01.nsswitch.* — diffing it against the live one is the answer."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
