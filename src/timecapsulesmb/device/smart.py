"""Read-only ATA SMART attributes for the app's Checkup report.

Raw attributes remain vendor-reported strings: large read/seek error-rate
values, for example, are not counts of failed reads. Never run a self-test,
enable SMART, or change the drive's power-management settings here.
"""
from __future__ import annotations

import re

from timecapsulesmb.transport.errors import TransportError
from timecapsulesmb.transport.ssh import SshConnection, run_ssh


_ATTRIBUTE = re.compile(
    r"^\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\s+(yes|no)\s+"
    r"(online|offline)\s+(positive|negative)\s+(.+?)\s+"
    r"(\d+(?:\s+Lifetime min/max \d+/\d+)?)\s*$"
)


def parse_smart_status(text: str, returncode: int = 0) -> dict[str, object]:
    unavailable: dict[str, object] = {"state": "unavailable", "attributes": []}
    if len(text) > 32768:
        return unavailable
    lowered = text.lower()
    threshold_exceeded = "threshold exceeds condition" in lowered
    if threshold_exceeded:
        # RETURN STATUS can report failure even if the optional attribute
        # reads that follow it are unsupported or fail. Keep that warning.
        unavailable["threshold_exceeded"] = True
    if "smart not supported" in lowered:
        return {"state": "unsupported", "attributes": []}
    if "smart disabled" in lowered or "smart not enabled" in lowered:
        return {"state": "disabled", "attributes": []}
    if returncode or "checksum error" in lowered or "smart enabled" not in lowered:
        return unavailable
    attributes: list[dict[str, object]] = []
    seen: set[int] = set()
    for line in text.splitlines():
        if not re.match(r"^\s*\d+\s", line):
            continue
        match = _ATTRIBUTE.fullmatch(line)
        if match is None:
            return unavailable
        attr_id, value, threshold = map(int, match.group(1, 2, 3))
        if not 1 <= attr_id <= 255 or attr_id in seen or not 1 <= value <= 253 or threshold > 253:
            return unavailable
        seen.add(attr_id)
        attributes.append({
            "id": attr_id, "value": value, "threshold": threshold,
            "critical": match[4] == "yes", "collection": match[5],
            "reliability": match[6], "name": match[7].strip(), "raw": match[8].strip(),
        })
    if not attributes or len(attributes) > 30:
        return unavailable
    return {
        "state": "available", "attributes": attributes,
        "threshold_exceeded": threshold_exceeded,
    }


def read_smart_status(connection: SshConnection, device: str) -> dict[str, object]:
    if not re.fullmatch(r"(?:wd|sd)[0-9]{1,3}", device):
        return {"state": "unsupported", "attributes": []}
    # The device watchdog bounds the remote child too; an SSH timeout alone
    # would leave atactl running. All commands and arguments are fixed apart
    # from the validated whole-disk name from MaSt.
    command = (
        f"(/sbin/atactl {device} smart status 2>&1 & p=$!; "
        "(sleep 5; kill $p) </dev/null >/dev/null 2>&1 & w=$!; "
        "wait $p; rc=$?; kill $w; exit $rc) 2>/dev/null"
    )
    try:
        result = run_ssh(connection, command, check=False, timeout=12)
    except TransportError:
        return {"state": "unavailable", "attributes": []}
    return parse_smart_status(result.stdout, result.returncode)
