#!/usr/bin/env python3
"""cgexport.py — cAdvisor, minus about twenty thousand lines. (I12.9)

For every running container: find its cgroup, read CPU / memory / pid counts
straight from the kernel, resolve a human name through the CRI, and serve the
result as Prometheus exposition.

There is no metrics library here and no dependency beyond the standard library,
because there is nothing to depend on: every number below is a file in
/sys/fs/cgroup that B7 taught you to read, and the only hard part is deciding
which of them to publish.

    sudo python3 cgexport.py            # serve on :9101
    curl -s localhost:9101/metrics

Needs root: crictl talks to a root-owned socket and the cgroup files for
containers are root-readable only.
"""

import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# Prometheus requires this exact content type. python3 -m http.server serves
# application/octet-stream, which a scraper will refuse.
CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"
PORT = 9101


def crictl(*args):
    """Run crictl and parse its JSON. This is the only non-kernel source we use,
    and we use it for exactly one thing: turning a container ID into a name."""
    out = subprocess.run(
        ["crictl", *args], capture_output=True, text=True, check=True
    ).stdout
    return json.loads(out)


def read(path, default=None):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return default


def keyed(text):
    """Parse a 'key value' cgroup file (cpu.stat, memory.stat) into a dict."""
    d = {}
    for line in (text or "").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip("-").isdigit():
            d[parts[0]] = int(parts[1])
    return d


def cgroup_dir(cgpath):
    """Turn an OCI cgroupsPath into a real directory under /sys/fs/cgroup.

    Two spellings exist, and which one you get depends on the runtime's cgroup
    driver (I8):

      cgroupfs  /k8s.io/<id>                     -- already a path
      systemd   <slice>:<prefix>:<id>            -- has to be expanded

    systemd nests slices by splitting the name on '-', so
    kubepods-besteffort.slice lives at
    /kubepods.slice/kubepods-besteffort.slice, and the container is a .scope
    inside it.
    """
    if ":" not in cgpath:
        return cgpath
    slice_, prefix, ident = cgpath.split(":")
    parts = slice_.removesuffix(".slice").split("-")
    nested = "".join(
        "/" + "-".join(parts[: i + 1]) + ".slice" for i in range(len(parts))
    )
    return f"{nested}/{prefix}-{ident}.scope"


def containers():
    """Yield (id, name, pod, namespace, cgroup_dir) for every RUNNING container."""
    for c in crictl("ps", "-o", "json")["containers"]:
        cid = c["id"]
        labels = c.get("labels") or {}
        info = crictl("inspect", cid)
        cgpath = info["info"]["runtimeSpec"]["linux"]["cgroupsPath"]
        cgpath = cgroup_dir(cgpath)
        yield (
            cid,
            c["metadata"]["name"],
            labels.get("io.kubernetes.pod.name", "-"),
            labels.get("io.kubernetes.pod.namespace", "-"),
            "/sys/fs/cgroup" + cgpath,
        )


def sample():
    """One scrape: read every number for every container, from the kernel."""
    rows = []
    for cid, name, pod, ns, d in containers():
        cpu = keyed(read(f"{d}/cpu.stat"))
        mem = keyed(read(f"{d}/memory.stat"))
        current = int((read(f"{d}/memory.current") or "0").strip() or 0)
        limit = (read(f"{d}/memory.max") or "max").strip()
        rows.append(
            {
                "labels": f'container="{name}",pod="{pod}",namespace="{ns}",'
                f'id="{cid[:12]}"',
                # A counter: cumulative, only ever rising. Seconds, because
                # Prometheus convention is base units.
                "cpu_seconds": cpu.get("usage_usec", 0) / 1e6,
                "throttled_seconds": cpu.get("throttled_usec", 0) / 1e6,
                "throttled_periods": cpu.get("nr_throttled", 0),
                "periods": cpu.get("nr_periods", 0),
                # Gauges.
                "memory_usage": current,
                # The number that matters: usage minus reclaimable page cache.
                # Publishing memory.current alone is the single most common
                # container-metrics mistake (I12.6).
                "memory_working_set": max(current - mem.get("inactive_file", 0), 0),
                "memory_rss": mem.get("anon", 0),
                "memory_cache": mem.get("file", 0),
                "memory_limit": 0 if limit == "max" else int(limit),
                "pids": int((read(f"{d}/pids.current") or "0").strip() or 0),
            }
        )
    return rows


METRICS = [
    ("container_cpu_usage_seconds_total", "counter",
     "Cumulative CPU time consumed by the container.", "cpu_seconds"),
    ("container_cpu_throttled_seconds_total", "counter",
     "Cumulative time the container was throttled by its CPU quota.",
     "throttled_seconds"),
    ("container_cpu_throttled_periods_total", "counter",
     "Number of enforcement periods in which the container was throttled.",
     "throttled_periods"),
    ("container_cpu_periods_total", "counter",
     "Number of CPU enforcement periods elapsed.", "periods"),
    ("container_memory_usage_bytes", "gauge",
     "Current memory usage including page cache.", "memory_usage"),
    ("container_memory_working_set_bytes", "gauge",
     "Current memory usage excluding reclaimable page cache.",
     "memory_working_set"),
    ("container_memory_rss_bytes", "gauge",
     "Anonymous memory: the pages the workload itself allocated.", "memory_rss"),
    ("container_memory_cache_bytes", "gauge",
     "Page cache charged to this container.", "memory_cache"),
    ("container_spec_memory_limit_bytes", "gauge",
     "Memory limit, or 0 if unlimited.", "memory_limit"),
    ("container_processes", "gauge",
     "Processes running inside the container.", "pids"),
]


def render(rows):
    out = []
    for metric, kind, help_, key in METRICS:
        out.append(f"# HELP {metric} {help_}")
        out.append(f"# TYPE {metric} {kind}")
        for r in rows:
            value = r[key]
            value = f"{value:.6f}" if isinstance(value, float) else str(value)
            out.append(f"{metric}{{{r['labels']}}} {value}")
    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] not in ("/metrics", "/"):
            self.send_error(404)
            return
        try:
            body = render(sample()).encode()
        except Exception as exc:  # a scrape must never take the exporter down
            self.send_error(500, str(exc))
            return
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPE)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    if "--once" in sys.argv:  # print one scrape and exit, for the lab
        sys.stdout.write(render(sample()))
        raise SystemExit(0)
    print(f"cgexport: serving http://0.0.0.0:{PORT}/metrics", file=sys.stderr)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
