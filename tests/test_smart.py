from __future__ import annotations

import json
import subprocess
from pathlib import Path
from unittest import mock

import pytest

from timecapsulesmb.device.smart import parse_smart_status, read_smart_status
from timecapsulesmb.transport.errors import SshCommandTimeout, SshError
from timecapsulesmb.transport.ssh import SshConnection


FIXTURE = Path(__file__).parent / "fixtures/smart_status.txt"
UNAVAILABLE = {"state": "unavailable", "attributes": []}


def test_parses_device_readings_and_preserves_vendor_raw_values():
    report = parse_smart_status(FIXTURE.read_text())
    assert report["state"] == "available"
    assert report["threshold_exceeded"] is False
    attributes = {attribute["id"]: attribute for attribute in report["attributes"]}
    assert len(attributes) == 24
    assert attributes[194]["raw"] == "48 Lifetime min/max 0/12"
    assert attributes[9]["raw"] == "16141"
    assert attributes[5]["raw"] == attributes[197]["raw"] == "0"
    assert attributes[198]["collection"] == "offline"
    assert attributes[1]["raw"] == "109549360"
    assert attributes[1]["reliability"] == "positive"


def test_swift_fixture_matches_python_report():
    fixture = Path(__file__).parents[1] / (
        "macos/TimeCapsuleSMB/Tests/TimeCapsuleSMBAppTests/Fixtures/disk_smart_report.json"
    )
    assert json.loads(fixture.read_text())["disks"][0]["details"] == parse_smart_status(FIXTURE.read_text())


@pytest.mark.parametrize(("text", "state"), [
    ("SMART not supported", "unsupported"),
    ("SMART supported, SMART disabled", "disabled"),
    ("SMART supported, SMART not enabled", "disabled"),
    ("/sbin/atactl: not found", "unavailable"),
    ("SMART supported, SMART enabled\nSMART attribute values checksum error", "unavailable"),
    ("SMART supported, SMART enabled\nSMART attribute thresholds checksum error", "unavailable"),
    ("SMART supported, SMART enabled\nid value thresh crit collect reliability description raw", "unavailable"),
    ("", "unavailable"),
])
def test_missing_readings_are_never_healthy_zeroes(text, state):
    assert parse_smart_status(text) == {"state": state, "attributes": []}


@pytest.mark.parametrize("row", [
    "0 100 10 yes online positive Unknown 0",
    "256 100 10 yes online positive Unknown 0",
    "5 254 10 yes online positive Unknown 0",
    "5 0 10 yes online positive Unknown 0",
    "5 100 254 yes online positive Unknown 0",
    "5 100 10 yes online positive Reallocated sector count truncated",
    "5 100 10 yes online positive Reallocated sector count 0\n5 100 10 yes online positive Other 1",
])
def test_malformed_or_ambiguous_output_is_unavailable(row):
    assert parse_smart_status("SMART supported, SMART enabled\n" + row) == UNAVAILABLE


def test_failed_and_oversized_reads_are_unavailable():
    assert parse_smart_status(FIXTURE.read_text(), returncode=1) == UNAVAILABLE
    assert parse_smart_status(FIXTURE.read_text() * 100) == UNAVAILABLE


def test_keeps_hardware_failure_even_when_optional_attribute_reads_fail():
    text = "SMART supported, SMART enabled\nThreshold exceeds condition\natactl: command failed"
    assert parse_smart_status(text, returncode=1) == {**UNAVAILABLE, "threshold_exceeded": True}
    report = parse_smart_status(FIXTURE.read_text() + "\nThreshold exceeds condition\n")
    assert report["threshold_exceeded"] is True


def test_reads_only_status_with_host_and_device_time_limits():
    connection = SshConnection("root@10.0.0.2", "pw", "")
    with mock.patch("timecapsulesmb.device.smart.run_ssh", return_value=subprocess.CompletedProcess(
        ["ssh"], 0, FIXTURE.read_text(), "",
    )) as run:
        assert read_smart_status(connection, "wd0")["state"] == "available"
    args, kwargs = run.call_args
    assert args[0] is connection
    assert "/sbin/atactl wd0 smart status" in args[1]
    assert "sleep 5; kill $p" in args[1]
    assert "wait $p" in args[1]
    assert kwargs == {"check": False, "timeout": 12}
    assert not any(command in args[1] for command in ("smart enable", "smart disable", "smart offline"))


@pytest.mark.parametrize("device", ["dk2", "wd0a", "wd0; reboot", "../wd0", "sd0\nreboot", "wd9999"])
def test_validates_disk_identifier_before_ssh(device):
    with mock.patch("timecapsulesmb.device.smart.run_ssh") as run:
        assert read_smart_status(mock.sentinel.connection, device) == {"state": "unsupported", "attributes": []}
    run.assert_not_called()


@pytest.mark.parametrize("error", [SshError("connection reset"), SshCommandTimeout("timed out")])
def test_transport_failure_is_an_optional_reading(error):
    with mock.patch("timecapsulesmb.device.smart.run_ssh", side_effect=error):
        assert read_smart_status(mock.sentinel.connection, "sd0") == UNAVAILABLE
