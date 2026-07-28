#!/usr/bin/env python3
"""pull.py - pull an image from a registry using nothing but HTTP.

Usage:  pull.py REFERENCE OUT_DIR [--platform linux/amd64] [--store DIR]

    pull.py docker.io/library/alpine:3.21 ./layout
    pull.py localhost:5000/demo/alpine:3.21 ./layout --store ~/.content

This is the distribution spec transcribed, and nothing more:

    GET  /v2/                                 does it speak the API
    401 + WWW-Authenticate                    -> token from the named realm
    GET  /v2/<name>/manifests/<tag>           -> index or manifest
    GET  /v2/<name>/manifests/<digest>        -> the platform's manifest
    GET  /v2/<name>/blobs/<digest>            -> config, then each layer

Every blob is verified by recomputing its digest, and cached by digest in a
content store laid out the way containerd's is:

    <store>/blobs/sha256/<hex>

which is also, not by coincidence, where an OCI layout keeps its blobs. So the
layout this writes is the store plus two files, and I4's oci-inspect.py reads
it unchanged.
"""
import argparse, hashlib, json, os, sys, urllib.parse, urllib.request

ACCEPT = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])
INDEX_TYPES = {"application/vnd.oci.image.index.v1+json",
               "application/vnd.docker.distribution.manifest.list.v2+json"}


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_ref(ref):
    """Split registry/name:tag. Docker Hub's two shorthands are the only magic."""
    name, _, tag = ref.rpartition(":")
    if "/" in tag:                      # there was no tag, only a port or path
        name, tag = ref, "latest"
    host, _, rest = name.partition("/")
    if "." not in host and ":" not in host and host != "localhost":
        host, rest = "docker.io", name  # bare name: alpine -> docker.io/alpine
    if host == "docker.io":
        endpoint = "https://registry-1.docker.io"
        if "/" not in rest:
            rest = "library/" + rest    # alpine -> library/alpine
    else:
        scheme = "http" if host.startswith(("localhost", "127.0.0.1")) else "https"
        endpoint = f"{scheme}://{host}"
    return endpoint, rest, tag


def get(url, token=None, accept=None, method="GET"):
    req = urllib.request.Request(url, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if accept:
        req.add_header("Accept", accept)
    return urllib.request.urlopen(req)


def diagnose(e, url):
    """Turn an HTTP status into the sentence a human needed to read.

    This is the whole module in one function: every common pull failure is a
    status code that already says what went wrong, and the only reason it
    reaches people as 'ImagePullBackOff' is that nothing along the way
    bothered to say it out loud.
    """
    try:
        body = json.loads(e.read())
        err = (body.get("errors") or [{}])[0]
        detail = err.get("code") or body.get("details") or ""
    except Exception:
        detail = ""
    challenge = e.headers.get("WWW-Authenticate", "") if e.headers else ""
    hint = {
        401: ("no token, or the wrong credentials - a Bearer challenge from the "
              "registry means you never authenticated; a Basic challenge from an "
              "auth service means your credentials were rejected"),
        404: ("the reference does not exist here. A 404 on a manifest is a wrong "
              "name, tag or Accept header; a 404 on a blob after the manifest "
              "resolved is a registry missing content it promised"),
        429: "rate limited - authenticate, mirror, or run a pull-through cache",
        403: "authenticated, but not allowed to pull this repository",
    }.get(e.code, "")
    die(f"{e.code} {e.reason} on {url}\n"
        + (f"  registry says: {detail}\n" if detail else "")
        + (f"  challenge:     {challenge}\n" if challenge else "")
        + (f"  meaning:       {hint}" if hint else ""))


def authenticate(endpoint, name):
    """Do the token dance, if the registry asks for one. Anonymous is fine."""
    try:
        get(endpoint + "/v2/").read()
        return None                                    # 200: no auth needed
    except urllib.error.HTTPError as e:
        if e.code != 401:
            die(f"{endpoint}/v2/ answered {e.code} - is this a registry?")
        challenge = e.headers.get("WWW-Authenticate", "")
    if not challenge.lower().startswith("bearer"):
        die(f"cannot handle challenge: {challenge}")
    parts = dict(p.split("=", 1) for p in challenge[7:].split(",") if "=" in p)
    realm = parts["realm"].strip('"')
    query = {"scope": f"repository:{name}:pull"}
    if "service" in parts:
        query["service"] = parts["service"].strip('"')
    body = json.load(get(realm + "?" + urllib.parse.urlencode(query)))
    return body.get("token") or body.get("access_token")


def fetch_blob(endpoint, name, desc, store, what):
    """Fetch one blob, verify its digest, cache it. Never fetch it twice."""
    digest = desc["digest"]
    algo, hex_ = digest.split(":", 1)
    path = os.path.join(store, "blobs", algo, hex_)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        print(f"  [cached]   {what:<12} {digest[:26]}...")
        return path
    h, size = hashlib.new(algo), 0
    tmp = path + ".partial"
    url = f"{endpoint}/v2/{name}/blobs/{digest}"
    try:
        with get(url, TOKEN) as r, open(tmp, "wb") as f:
            while chunk := r.read(1 << 20):
                h.update(chunk); size += len(chunk); f.write(chunk)
    except urllib.error.HTTPError as e:
        diagnose(e, url)
    got = f"{algo}:{h.hexdigest()}"
    if got != digest:
        os.unlink(tmp)
        die(f"{what}: digest mismatch\n  claimed {digest}\n  actual  {got}")
    if "size" in desc and size != desc["size"]:
        os.unlink(tmp)
        die(f"{what}: size mismatch: descriptor says {desc['size']}, got {size}")
    os.rename(tmp, path)                 # rename last: a partial file is never valid
    print(f"  [verified] {what:<12} {digest[:26]}... {size:>9} bytes")
    return path


def fetch_manifest(endpoint, name, reference, store):
    """Fetch a manifest and cache it by its own digest, like any other blob."""
    url = f"{endpoint}/v2/{name}/manifests/{reference}"
    try:
        with get(url, TOKEN, ACCEPT) as r:
            raw = r.read()
            media = r.headers.get("Content-Type", "").split(";")[0]
    except urllib.error.HTTPError as e:
        diagnose(e, url)
    digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    if reference.startswith("sha256:") and reference != digest:
        die(f"manifest digest mismatch: asked for {reference}, got {digest}")
    path = os.path.join(store, "blobs", "sha256", digest.split(":", 1)[1])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(raw)
    return json.loads(raw), digest, len(raw), media


def select(index, want):
    """Pick one manifest for the wanted platform.

    Two things to skip, both learned the hard way in I4: attestation manifests
    (platform unknown/unknown, carrying a vnd.docker.reference.type annotation),
    and the assumption that architecture and variant are one string.
    """
    want_os, _, want_arch = want.partition("/")
    want_arch, _, want_var = want_arch.partition("/")
    for m in index.get("manifests", []):
        if (m.get("annotations") or {}).get("vnd.docker.reference.type"):
            continue
        p = m.get("platform") or {}
        if p.get("os") != want_os or p.get("architecture") != want_arch:
            continue
        if want_var and p.get("variant") != want_var:
            continue
        return m
    # architecture and variant are separate fields: "arm64" + "v8", never
    # "arm64v8". The conventional platform string keeps them slash-separated.
    have = sorted({"/".join(x for x in [(m.get("platform") or {}).get("os"),
                                        (m.get("platform") or {}).get("architecture"),
                                        (m.get("platform") or {}).get("variant")] if x)
                   for m in index.get("manifests", [])
                   if not (m.get("annotations") or {}).get("vnd.docker.reference.type")})
    die(f"no image found for platform {want}; the index offers {have}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("out")
    ap.add_argument("--platform", default="linux/amd64")
    ap.add_argument("--store", help="content store to cache blobs in "
                                    "(default: the output layout itself)")
    args = ap.parse_args()

    endpoint, name, tag = parse_ref(args.reference)
    store = args.store or args.out
    os.makedirs(store, exist_ok=True)
    print(f"registry   {endpoint}\nrepository {name}\nreference  {tag}\n")

    global TOKEN
    TOKEN = authenticate(endpoint, name)
    print("token      " + ("anonymous bearer token" if TOKEN else "none needed"))

    doc, digest, size, media = fetch_manifest(endpoint, name, tag, store)
    print(f"\nresolved   {tag} -> {digest}\n           {media}")

    if media in INDEX_TYPES or doc.get("mediaType") in INDEX_TYPES:
        chosen = select(doc, args.platform)
        print(f"selected   {args.platform} -> {chosen['digest'][:26]}...")
        doc, digest, size, media = fetch_manifest(endpoint, name, chosen["digest"], store)
    else:
        # No index: the tag resolved straight to one manifest. Nothing has
        # selected a platform, so check the config before trusting --platform.
        print(f"note       no index; {tag} is a single manifest")

    print("\nblobs:")
    config_path = fetch_blob(endpoint, name, doc["config"], store, "config")
    config = json.load(open(config_path))
    # The config is the only place that states the platform as a fact rather
    # than as a promise made by an index entry. Resolving a tag is not
    # selecting a platform, so check it - this is the arm64/amd64 incident.
    if (config.get("os"), config.get("architecture")) != tuple(args.platform.split("/")[:2]):
        print(f"  WARNING: asked for {args.platform}, but the config says "
              f"{config.get('os')}/{config.get('architecture')}")
    for i, layer in enumerate(doc["layers"]):
        fetch_blob(endpoint, name, layer, store, f"layer[{i}]")

    # An OCI layout is the blob store plus two files. If --store pointed
    # elsewhere, link the blobs we need into the layout rather than copying.
    os.makedirs(args.out, exist_ok=True)
    if os.path.abspath(store) != os.path.abspath(args.out):
        for d in [doc["config"], *doc["layers"], {"digest": digest}]:
            algo, hex_ = d["digest"].split(":", 1)
            src = os.path.join(store, "blobs", algo, hex_)
            dst = os.path.join(args.out, "blobs", algo, hex_)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if not os.path.exists(dst):
                os.link(src, dst)
    with open(os.path.join(args.out, "oci-layout"), "w") as f:
        json.dump({"imageLayoutVersion": "1.0.0"}, f)
    with open(os.path.join(args.out, "index.json"), "w") as f:
        json.dump({"schemaVersion": 2,
                   "mediaType": "application/vnd.oci.image.index.v1+json",
                   "manifests": [{"mediaType": media, "digest": digest, "size": size,
                                  "platform": {"os": config.get("os"),
                                               "architecture": config.get("architecture")},
                                  "annotations": {
                                      "org.opencontainers.image.ref.name": tag}}]}, f, indent=2)
    print(f"\nOCI layout ready: {args.out}  (tag '{tag}')")
    print(f"  next: oci-inspect.py {args.out} {tag} --extract rootfs/")


if __name__ == "__main__":
    main()
