import json
import os
import re
import sys
from datetime import datetime, timezone
from itertools import pairwise
from typing import Dict, List


ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1bP.*?\x1b\\")
KERNEL_TS_RE = re.compile(r"^\[\s*([0-9]+(?:\.[0-9]+)?)\]\s*(.*)$")
WRAPPER_TRACE_RE = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s+(.+)$")
FIREBREAK_SESSION_RE = re.compile(
    r"\[firebreak-session\]\s+(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s+([A-Za-z0-9._:-]+)$"
)

RUNNER_MARKERS = {
    "Finished NixOS Activation": "nixos_activation_done_ms",
    "Finished Align guest development user with the host user identity": "adopt_host_identity_done_ms",
    "Finished Prepare the workspace and worker session paths": "prepare_worker_session_done_ms",
    "Finished Configure runtime network": "configure_runtime_network_done_ms",
    "Started Expose rootless guest egress": "guest_egress_proxy_started_ms",
    "Started Expose localhost TCP services through the Cloud Hypervisor vsock mux": "guest_port_publish_started_ms",
    "Started Interactive dev shell on ttyS0": "dev_console_started_ms",
    "Started Warm local command worker": "local_command_worker_started_ms",
}


def load_event_file(path: str, source_name: str) -> List[Dict[str, object]]:
    events: List[Dict[str, object]] = []
    if not os.path.exists(path):
        return events

    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 3)
            if len(parts) < 3:
                continue
            detail = parts[3] if len(parts) > 3 else ""
            try:
                ts_ms = int(parts[0])
            except ValueError:
                continue
            events.append({
                "ts_ms": ts_ms,
                "component": parts[1],
                "phase": parts[2],
                "detail": detail,
                "source": source_name,
            })
    return events


def parse_runner_markers(path: str) -> Dict[str, int]:
    markers: Dict[str, int] = {}
    if not os.path.exists(path):
        return markers

    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = ANSI_RE.sub("", raw_line).strip()
            match = KERNEL_TS_RE.match(line)
            if not match:
                continue
            seconds = float(match.group(1))
            payload = match.group(2)
            for needle, key in RUNNER_MARKERS.items():
                if needle in payload and key not in markers:
                    markers[key] = int(seconds * 1000)
    return markers


def parse_iso_utc_ms(raw_value: str) -> int:
    return int(datetime.strptime(raw_value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp() * 1000)


def load_wrapper_trace(path: str) -> List[Dict[str, object]]:
    events: List[Dict[str, object]] = []
    if not os.path.exists(path):
      return events

    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            match = WRAPPER_TRACE_RE.match(line)
            if not match:
                continue
            ts_ms = parse_iso_utc_ms(match.group(1))
            payload = match.group(2)
            component = "wrapper"
            phase = payload
            detail = ""
            if ":" in payload:
                phase, detail = payload.split(":", 1)
            events.append({
                "ts_ms": ts_ms,
                "component": component,
                "phase": phase,
                "detail": detail,
                "source": "wrapper-trace",
            })
    return events


def load_firebreak_session_events(path: str) -> List[Dict[str, object]]:
    events: List[Dict[str, object]] = []
    if not os.path.exists(path):
        return events

    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = ANSI_RE.sub("", raw_line).strip()
            match = FIREBREAK_SESSION_RE.search(line)
            if not match:
                continue
            ts_ms = parse_iso_utc_ms(match.group(1))
            payload = match.group(2)
            component = "guest-session"
            phase = payload
            detail = ""
            if "-" in payload:
                component = payload.split("-", 1)[0]
            events.append({
                "ts_ms": ts_ms,
                "component": component,
                "phase": phase,
                "detail": detail,
                "source": "runner-firebreak-session",
            })
    return events


def build_summary(runtime_dir: str) -> Dict[str, object]:
    host_events_path = os.path.join(runtime_dir, "profile-host.tsv")
    guest_events_path = os.path.join(runtime_dir, "runtime", "exec-output", "profile-guest.tsv")
    runner_out_path = os.path.join(runtime_dir, "runner.out")
    wrapper_trace_path = os.path.join(runtime_dir, "wrapper-trace.log")

    host_events = load_event_file(host_events_path, "host")
    if not host_events:
        host_events = load_wrapper_trace(wrapper_trace_path)

    guest_events = load_event_file(guest_events_path, "guest")
    if not guest_events:
        guest_events = load_firebreak_session_events(runner_out_path)

    events = host_events + guest_events
    events.sort(key=lambda event: event["ts_ms"])

    segments: List[Dict[str, object]] = []
    for previous, current in pairwise(events):
        duration_ms = int(current["ts_ms"]) - int(previous["ts_ms"])
        if duration_ms < 0:
            continue
        segments.append({
            "duration_ms": duration_ms,
            "from": f'{previous["component"]}:{previous["phase"]}',
            "to": f'{current["component"]}:{current["phase"]}',
            "from_source": previous["source"],
            "to_source": current["source"],
        })

    top_segments = sorted(segments, key=lambda segment: segment["duration_ms"], reverse=True)[:12]
    runner_markers = parse_runner_markers(runner_out_path)

    summary: Dict[str, object] = {
        "runtime_dir": runtime_dir,
        "event_files": {
            "host": host_events_path if os.path.exists(host_events_path) else None,
            "guest": guest_events_path if os.path.exists(guest_events_path) else None,
            "wrapper_trace": wrapper_trace_path if os.path.exists(wrapper_trace_path) else None,
            "runner": runner_out_path if os.path.exists(runner_out_path) else None,
        },
        "event_count": len(events),
        "events": events,
        "top_segments": top_segments,
        "runner_markers_ms": runner_markers,
    }

    if events:
        summary["total_profile_window_ms"] = int(events[-1]["ts_ms"]) - int(events[0]["ts_ms"])
        summary["first_event"] = f'{events[0]["component"]}:{events[0]["phase"]}'
        summary["last_event"] = f'{events[-1]["component"]}:{events[-1]["phase"]}'

    return summary


def main() -> int:
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("usage: profile-summary.py RUNTIME_DIR [OUTPUT_JSON]", file=sys.stderr)
        return 1

    runtime_dir = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) == 3 else ""
    summary = build_summary(runtime_dir)
    payload = json.dumps(summary, indent=2, sort_keys=True)

    if output_path:
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.write("\n")

    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
