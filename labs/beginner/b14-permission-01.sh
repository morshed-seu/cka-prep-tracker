#!/usr/bin/env bash
# Beginner gauntlet fault b14-permission-01 (B14.5) — plants ONE fault in the
# permission layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-permission-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
TARGET=/srv/gauntlet

echo "============================================================"
echo " Beginner gauntlet — fault b14-permission-01"
echo " About to BREAK: a service account's access to its own data"
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
id gauntlet >/dev/null 2>&1 || \
  useradd --system --no-create-home --shell /usr/sbin/nologin gauntlet
install -d -m 755 "$TARGET" "$TARGET/data"
echo 'the-answer-is-42' > "$TARGET/data/config.txt"
chmod 644 "$TARGET/data/config.txt"

if ! sudo -u gauntlet cat "$TARGET/data/config.txt" >/dev/null 2>&1; then
  echo "ABORT: the gauntlet user cannot read the file even before the fault." >&2
  echo "Clean up $TARGET and re-run." >&2; exit 1
fi

mkdir -p "$BACKUPS"
stat -c '%n %a %U:%G' "$TARGET" "$TARGET/data" "$TARGET/data/config.txt" \
  > "$BACKUPS/permission-01.modes.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
chmod 750 "$TARGET"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. The 'gauntlet' service account can no longer read its config file."
echo "  2. Reproduce it:  sudo -u gauntlet cat $TARGET/data/config.txt"
echo "  3. Fix the root cause, then verify the same command prints:"
echo "       the-answer-is-42"
echo "  4. Do not chmod 777 anything, and do not copy the file elsewhere."
echo
echo "Escape hatch (only if hopelessly stuck): the original modes are recorded"
echo "in $BACKUPS/permission-01.modes.* — restoring them un-plants the fault."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
