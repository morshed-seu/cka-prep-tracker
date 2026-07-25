#!/usr/bin/env bash
# Beginner gauntlet fault b14-cert-01 (B14.5) — plants ONE fault in the
# TLS/PKI layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-cert-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
TLS=/srv/gauntlet/tls
UNIT=gauntlet-tls.service
PORT=8443

echo "============================================================"
echo " Beginner gauntlet — fault b14-cert-01"
echo " About to BREAK: a TLS service that keeps running perfectly"
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
install -d -m 755 "$TLS"
cd "$TLS"
if [ ! -f ca.crt ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout ca.key -out ca.crt -subj '/CN=Gauntlet CA/O=sandbox' 2>/dev/null
  chmod 600 ca.key
fi
if [ ! -f server.key ]; then
  openssl genrsa -out server.key 2048 2>/dev/null
  chmod 600 server.key
fi
openssl req -new -key server.key -out server.csr -subj '/CN=localhost' 2>/dev/null
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > good.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 -extfile good.ext -out server.crt 2>/dev/null

cat > /etc/systemd/system/"$UNIT" <<UNITEOF
[Unit]
Description=B14 gauntlet TLS server
[Service]
ExecStart=/usr/bin/openssl s_server -accept $PORT -cert $TLS/server.crt -key $TLS/server.key -www
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl restart "$UNIT"
sleep 2
if ! curl -sf --max-time 3 --cacert "$TLS/ca.crt" "https://localhost:$PORT/" >/dev/null; then
  echo "ABORT: the TLS service does not verify cleanly even before the fault." >&2
  echo "Check 'systemctl status $UNIT' and re-run." >&2; exit 1
fi

mkdir -p "$BACKUPS"
openssl x509 -in server.crt -noout -text > "$BACKUPS/cert-01.cert.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:gauntlet-internal\n' > /tmp/b14-bad.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 -extfile /tmp/b14-bad.ext -out server.crt 2>/dev/null
rm -f /tmp/b14-bad.ext
systemctl restart "$UNIT"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $UNIT is running, listening, and serving TLS — verify that first."
echo "  2. Reproduce the symptom:"
echo "       curl -s --max-time 3 --cacert $TLS/ca.crt https://localhost:$PORT/"
echo "  3. Read the error precisely. Decide which of the two independent checks"
echo "     failed — the chain, or the name — because they have different fixes."
echo "  4. Fix the root cause (the CA key is still in $TLS), then verify:"
echo "       curl -s --max-time 3 --cacert $TLS/ca.crt https://localhost:$PORT/ | head -1"
echo "  5. Do not use --insecure, and do not add anything to the system trust store."
echo
echo "Escape hatch (only if hopelessly stuck): the pre-fault certificate is dumped"
echo "in $BACKUPS/cert-01.cert.* — comparing its extensions with the live one is the answer."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
