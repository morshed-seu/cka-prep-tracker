#!/bin/bash
# run-verified.sh — refuse to run an image whose signature does not verify;
#                   otherwise run it with every I11 control turned on.
#
#   usage: run-verified.sh <registry/repo:tag|@digest> [command...]
#
# Controls applied, and the checkpoint each comes from:
#   I11.1  every capability dropped from the bounding set
#   I11.2  noNewPrivileges, plus a non-root uid
#   I11.3  a seccomp allow-list whose defaultAction returns ENOSYS
#   I11.5  a read-only rootfs, with a tmpfs over /tmp
#   I11.9  the signature must verify BEFORE anything is unpacked
#   I11.13 the reference is resolved to a digest and only the digest is used
set -euo pipefail

UNSAFE=0
if [ "${1:-}" = "--unsafe" ]; then UNSAFE=1; shift; fi
REF=${1:?usage: run-verified.sh [--unsafe] <image-ref> [command...]}; shift || true
KEY=${COSIGN_PUB:-$HOME/i11cs/cosign.pub}
WORK=${WORK:-$HOME/i11cs/verified}
SECCOMP=${SECCOMP:-$HOME/i11cs/allow.json}
UID_IN=${UID_IN:-1000}
say() { printf '%s\n' "== $*"; }
die() { printf 'run-verified: %s\n' "$*" >&2; exit 1; }

# --- 1. resolve the tag to a digest, and never mention the tag again ---------
REPO=${REF%%[:@]*}; REPO=${REF%@*}; REPO=${REPO%:*}
say "resolving $REF"
DIGEST=$(skopeo inspect --tls-verify=false "docker://$REF" | jq -r .Digest) \
  || die "cannot resolve $REF"
PINNED="$REPO@$DIGEST"
say "pinned to $PINNED"

# --- 2. verify the signature, and stop here if it does not ------------------
say "verifying signature with $KEY"
if ! cosign verify --key "$KEY" --allow-http-registry --insecure-ignore-tlog=true \
        "$PINNED" >/dev/null 2>verify.err; then
  printf '\n'
  die "REFUSING TO RUN — signature did not verify for $PINNED
                 $(grep -m1 -E '^(Error|error)' verify.err || head -1 verify.err)"
fi
say "signature OK"

# --- 3. only now unpack ------------------------------------------------------
sudo rm -rf "$WORK"; mkdir -p "$WORK/rootfs"
skopeo copy --src-tls-verify=false "docker://$PINNED" "oci:$WORK/oci:run" >/dev/null
IDX=$(jq -r '.manifests[0].digest' "$WORK/oci/index.json" | sed 's/sha256://')
for l in $(jq -r '.layers[].digest' "$WORK/oci/blobs/sha256/$IDX" | sed 's/sha256://'); do
  sudo tar -xf "$WORK/oci/blobs/sha256/$l" -C "$WORK/rootfs"
done

# --- 4. build the hardened config -------------------------------------------
ARGS=$([ $# -gt 0 ] && printf '%s\n' "$*" | jq -R 'split(" ")' \
        || jq -n --slurpfile c <(jq '.config' "$WORK/oci/blobs/sha256/$(jq -r '.config.digest' "$WORK/oci/blobs/sha256/$IDX" | sed 's/sha256://')") \
             '($c[0].Entrypoint // []) + ($c[0].Cmd // [])')
( cd "$WORK" && rm -f config.json && runc spec )
if [ "$UNSAFE" = 1 ]; then
  say "RUNNING WITH NO CONTROLS (--unsafe): default caps, root, writable rootfs, no seccomp"
  jq --argjson args "$ARGS" '
      .process.terminal  = false
    | .process.args      = $args
    | .root.readonly     = false
    | .linux.namespaces |= map(select(.type != "network"))
    | .mounts += [{"destination":"/tmp","type":"tmpfs","source":"tmpfs",
                   "options":["nosuid","nodev","mode=1777","size=8m"]}]
    ' "$WORK/config.json" > "$WORK/c.tmp" && mv "$WORK/c.tmp" "$WORK/config.json"
  ID="rv-$$"
  ( cd "$WORK" && sudo runc --root /run/runc-i11 run "$ID" ) || true
  sudo runc --root /run/runc-i11 delete -f "$ID" 2>/dev/null || true
  exit 0
fi

jq --slurpfile s "$SECCOMP" --argjson args "$ARGS" --argjson uid "$UID_IN" '
    .process.terminal            = false
  | .process.args                = $args
  | .process.user.uid            = $uid
  | .process.user.gid            = $uid
  | .process.noNewPrivileges     = true
  | .process.capabilities.bounding  = []
  | .process.capabilities.effective = []
  | .process.capabilities.permitted = []
  | .root.readonly               = true
  | .linux.seccomp               = $s[0]
  | .linux.namespaces           |= map(select(.type != "network"))
  | .mounts += [{"destination":"/tmp","type":"tmpfs","source":"tmpfs",
                 "options":["nosuid","nodev","mode=1777","size=8m"]}]
  ' "$WORK/config.json" > "$WORK/c.tmp" && mv "$WORK/c.tmp" "$WORK/config.json"

say "running with: caps=[] noNewPrivileges=true uid=$UID_IN readonly=true seccomp=$(basename "$SECCOMP")"
ID="rv-$$"
( cd "$WORK" && sudo runc --root /run/runc-i11 run "$ID" ) || true
sudo runc --root /run/runc-i11 delete -f "$ID" 2>/dev/null || true
