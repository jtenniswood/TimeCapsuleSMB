"""AirPort settings round trips, credential privacy and partial-write recovery."""
from contextlib import nullcontext
from dataclasses import replace
import json
import plistlib
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from timecapsulesmb.app.ops import sharing as operation
from timecapsulesmb.app.events import EventSink
from timecapsulesmb.app.service import run_api_request
from timecapsulesmb.device import sharing
from timecapsulesmb.integrations import cfl
from timecapsulesmb.services.app import AppOperationError
from timecapsulesmb.transport.ssh import SshConnection


@pytest.fixture
def current():
    return sharing.SharingSettings(0x410, {"users": [
        {"name": "Alex", "password": "private-account-secret", "fileSharingAccess": 0, "unknown": b"kept"},
        {"name": "Reader", "password": "private-reader-secret", "fileSharingAccess": 1},
    ], "unknown_root": True}, "private-disk-secret", True)


def edits(current, **changes):
    return {"enabled": current.enabled, "security": current.security,
            "accounts": [{"name": user["name"], "source_name": user["name"], "access": user["fileSharingAccess"]}
                         for user in current.users["users"]], "revision": current.public()["revision"], **changes}


def test_public_payload_and_revision_never_expose_or_fingerprint_passwords(current):
    public = current.public()
    other = replace(current, disk_password="different", users={"users": [
        {**user, "password": "different"} for user in current.users["users"]]})
    assert public["revision"] == other.public()["revision"]
    assert public["accounts"] == [{"name": "Alex", "access": 0}, {"name": "Reader", "access": 1}]
    assert "secret" not in json.dumps(public) and "password" not in repr(current)


@pytest.mark.parametrize(("flags", "password", "mode", "enabled"), [
    (0x410, "ignored", "accounts", True), (0x414, "", "accounts", False),
    (0x450, "disk", "disk_password", True), (0x450, "", "device_password", True),
])
def test_apple_sharing_flag_semantics(current, flags, password, mode, enabled):
    value = replace(current, flags=flags, disk_password=password)
    assert value.security == mode and value.enabled is enabled


@pytest.mark.parametrize("mode", ["accounts", "disk_password", "device_password"])
def test_security_changes_preserve_other_flags_and_unknown_account_fields(current, mode):
    desired = sharing.changed_settings(current, edits(current, enabled=False, security=mode), {"disk_password": "new-disk"})
    assert desired.flags & ~0x44 == current.flags & ~0x44
    assert not desired.enabled and desired.security == mode
    assert desired.users == current.users


def test_rename_access_password_addition_and_deletion_use_fresh_account_values(current):
    desired = sharing.changed_settings(current, edits(current, accounts=[
        {"name": "Renamed", "source_name": "Alex", "access": 1},
        {"name": "New", "access": 2},
    ]), {"account_passwords": {"New": "new-secret"}})
    assert desired.users["users"] == [
        {"name": "Renamed", "password": "private-account-secret", "fileSharingAccess": 1, "unknown": b"kept"},
        {"name": "New", "password": "new-secret", "fileSharingAccess": 2},
    ]
    assert desired.users["unknown_root"] is True


@pytest.mark.parametrize("changes,credentials", [
    ({"revision": "stale"}, {}), ({"accounts": []}, {}),
    ({"security": "unknown"}, {}), ({"enabled": 1}, {}),
    ({"accounts": [{"name": "New", "access": 0}]}, {}),
    ({"accounts": [{"name": "Bad:name", "access": 0}]}, {"account_passwords": {"Bad:name": "secret"}}),
    ({"accounts": [{"name": "Alex", "source_name": "Alex", "access": 3}]}, {}),
    ({"accounts": [{"name": "Alex", "source_name": "missing", "access": 0}]}, {}),
    ({"accounts": [{"name": "Alex", "source_name": "Alex", "access": 0}, {"name": "alex", "access": 0}]}, {}),
])
def test_invalid_or_stale_updates_are_rejected(current, changes, credentials):
    with pytest.raises(sharing.SharingSettingsError):
        sharing.changed_settings(current, edits(current, **changes), credentials)


def test_unsupported_service_and_missing_disk_password_cannot_be_saved(current):
    with pytest.raises(sharing.SharingSettingsError, match="Update File Sharing"):
        sharing.changed_settings(replace(current, supported=False), edits(current), {})
    with pytest.raises(sharing.SharingSettingsError, match="disk password"):
        sharing.changed_settings(current, edits(current, security="disk_password"), {})


def test_read_decodes_only_public_inventory_and_bad_disk_does_not_block_accounts(monkeypatch, current):
    values = {"usbF": b"0x410\n", "usrd": plistlib.dumps(current.users), "fssp": b"disk\n",
              "MaSt": plistlib.dumps([{"builtin": True, "partitions": [
                  {"uuid": bytes.fromhex("11"*16), "name": "Data", "size": 100, "sizeFree": 60},
                  {"name": "Missing UUID"},
              ]}])}
    def capture(_connection, command, **_):
        return b"airport-sharing-v1\n" if "--print-sharing-features" in command else values[command.removeprefix("/usr/bin/acp -q ")]
    monkeypatch.setattr(sharing, "run_ssh_capture_bytes", capture)
    value = sharing.read_settings(SshConnection("root@capsule.local", "admin", ""))
    assert value.supported and value.users == current.users
    assert value.public()["partitions"] == [{"id": "11111111-1111-1111-1111-111111111111", "name": "Data", "builtin": True, "size_mib": 100, "free_mib": 60}]
    values["MaSt"] = b"unavailable"
    assert sharing.read_settings(SshConnection("root@capsule.local", "admin", "")).partitions == []
    values["usrd"] = b"malformed private-account-secret"
    with pytest.raises(sharing.SharingSettingsError) as error:
        sharing.read_settings(SshConnection("root@capsule.local", "admin", ""))
    assert "private-account-secret" not in str(error.value)
    assert error.value.__context__ is None


@pytest.mark.parametrize("disk_value", [b"", b"\n", b"### a valid password\n"])
def test_app_request_reads_account_settings_when_no_disk_password_is_configured(monkeypatch, current, disk_value):
    connection = SshConnection("root@capsule.local", "ssh-password", "")
    monkeypatch.setattr(operation, "load_request_config", lambda *_: None)
    monkeypatch.setattr(operation, "resolve_request_connection", lambda *_args, **_: connection)
    values = {"/usr/bin/acp -q usbF": b"0x410\n", "/usr/bin/acp -q usrd": plistlib.dumps(current.users),
              "/usr/bin/acp -q fssp": disk_value, "/usr/bin/acp -q MaSt": plistlib.dumps([]),
              "/mnt/Flash/service --print-sharing-features": b"airport-sharing-v1\n"}
    def capture(_connection, command, **_):
        assert "2>&1" not in command  # An unset fssp reports an error only on stderr.
        return values[command]
    monkeypatch.setattr(sharing, "run_ssh_capture_bytes", capture)
    events = []
    result = run_api_request({"operation": "disk-sharing", "request_id": "sharing-read", "params": {
        "action": "read", "config": "/profile/.env", "credentials": {"password": "ssh-password"},
    }}, EventSink(lambda event: events.append(event.to_jsonable())))
    assert result == 0 and not any(event["type"] == "error" for event in events)
    payload = next(event["payload"] for event in events if event["type"] == "result")
    assert payload["security"] == "accounts" and payload["accounts"][0]["name"] == "Alex"
    assert "private-account-secret" not in json.dumps(events)


@pytest.fixture
def writer(monkeypatch):
    monkeypatch.setattr(sharing, "run_ssh_capture_bytes", lambda _connection, command, **_: b"private-base-password\n" if "syPW" in command
                        else b"SHARE_NAME='My Folder'\nSHARE_ROOT='ShareRoot'\nAIRPORT_SHARING_SETTINGS=0\n")
    monkeypatch.setattr(sharing, "ssh_local_forward", lambda *_args, **_kwargs: nullcontext())
    send, config = Mock(), Mock()
    monkeypatch.setattr(sharing.acp, "set_properties", send)
    monkeypatch.setattr(sharing, "run_ssh_input", config)
    return send, config, SshConnection("root@capsule.local", "admin", "")


def test_successful_write_keeps_storage_folder_and_secrets_off_commands(monkeypatch, writer, current):
    send, config, connection = writer
    desired = sharing.changed_settings(current, edits(current, enabled=False), {})
    monkeypatch.setattr(sharing, "read_settings", lambda _: desired)
    sharing.write_settings(connection, desired, current)
    assert send.call_count == config.call_count == 1
    call = config.call_args
    assert b"SHARE_ROOT='ShareRoot'\n" in call.kwargs["input_bytes"]
    assert call.kwargs["input_bytes"].count(b"AIRPORT_SHARING_SETTINGS=") == 1
    assert b"AIRPORT_SHARING_SETTINGS=1\n" in call.kwargs["input_bytes"]
    assert "trap" in call.args[1] and "set -Ce" in call.args[1]
    assert "secret" not in call.args[1] and "admin" not in call.args[1]
    assert send.call_args.args[2]["usbF"] == desired.flags
    assert send.call_args.args[1] == "private-base-password"


@pytest.mark.parametrize("fault", ["partial_acp", "readback", "config"])
def test_failed_write_restores_and_verifies_previous_settings(monkeypatch, writer, current, fault):
    send, config, connection = writer
    desired = sharing.changed_settings(current, edits(current, enabled=False), {})
    if fault == "partial_acp":
        send.side_effect = [ValueError("private-secret"), None]
        read = Mock(return_value=current)
    else:
        read = Mock(side_effect=[current if fault == "readback" else desired, current])
    if fault == "config":
        config.side_effect = [ValueError("private-secret"), None]
    monkeypatch.setattr(sharing, "read_settings", read)
    with pytest.raises(sharing.SharingSettingsError, match="previous sharing settings were restored") as error:
        sharing.write_settings(connection, desired, current)
    assert "private-secret" not in str(error.value)
    assert error.value.__context__ is None
    assert send.call_count == 2 and send.call_args.args[2]["usbF"] == current.flags
    if fault == "config":
        assert config.call_count == 2 and b"AIRPORT_SHARING_SETTINGS=0" in config.call_args.kwargs["input_bytes"]
    else:
        config.assert_not_called()


def test_failed_rollback_never_claims_settings_were_restored(monkeypatch, writer, current):
    send, _, connection = writer
    send.side_effect = ValueError("private-secret")
    with pytest.raises(sharing.SharingSettingsError, match="could not be verified or restored"):
        sharing.write_settings(connection, current, current)


def test_confirmation_precedes_all_writes_and_restart(monkeypatch, current):
    monkeypatch.setattr(operation, "load_request_config", lambda *_: None)
    monkeypatch.setattr(operation, "resolve_request_connection", lambda *_args, **_: SshConnection("root@capsule.local", "admin", ""))
    monkeypatch.setattr(operation, "read_settings", lambda _: current)
    write, reboot = Mock(), Mock()
    monkeypatch.setattr(operation, "write_settings", write)
    monkeypatch.setattr(operation, "reboot_device", reboot)
    with pytest.raises(AppOperationError) as error:
        operation.sharing_operation({"action": "apply", "changes": edits(current, enabled=False), "credentials": {}}, SimpleNamespace(stage=lambda _: None))
    assert error.value.code == "confirmation_required"
    write.assert_not_called()
    reboot.assert_not_called()


@pytest.mark.parametrize("matches_after_restart", [True, False])
def test_confirmed_apply_verifies_the_saved_settings_after_restarting(monkeypatch, current, matches_after_restart):
    desired = sharing.changed_settings(current, edits(current, enabled=False), {})
    monkeypatch.setattr(operation, "load_request_config", lambda *_: None)
    connection = SshConnection("root@capsule.local", "ssh-password", "")
    monkeypatch.setattr(operation, "resolve_request_connection", lambda *_args, **_: connection)
    monkeypatch.setattr(operation, "read_settings", Mock(side_effect=[current, desired if matches_after_restart else current]))
    for name in ["require_confirmation", "require_request_acpd_ready", "require_request_no_disk_check"]:
        monkeypatch.setattr(operation, name, Mock())
    write, reboot = Mock(), Mock(return_value=None)
    monkeypatch.setattr(operation, "write_settings", write)
    monkeypatch.setattr(operation, "reboot_device", reboot)
    context = SimpleNamespace(stage=Mock(), to_operation_callbacks=lambda: None)
    def apply():
        return operation.sharing_operation({"action": "apply", "changes": edits(current, enabled=False), "credentials": {}}, context)
    if matches_after_restart:
        result = apply()
        assert "secret" not in json.dumps(result.payload)
        assert result.payload["enabled"] is False
    else:
        with pytest.raises(AppOperationError, match="did not match") as error:
            apply()
        assert error.value.__context__ is None
    write.assert_called_once_with(connection, desired, current)
    reboot.assert_called_once()


@pytest.mark.parametrize("value,hex_value", [
    (True, "09"), (False, "08"), (0, "1000"), (256, "110100"),
    ("é", "70c3a900"), (b"abc", "43616263"),
    ([1, "x"], "a0100170780000"), ({"users": []}, "d070757365727300a00000"),
])
def test_cfl_wire_fixtures(value, hex_value):
    assert cfl.encode(value) == b"CFB0" + bytes.fromhex(hex_value) + b"END!"


@pytest.mark.parametrize("value", [-1, 2**64, "bad\0value", [None], object(), "x" * 1_048_577])
def test_cfl_rejects_unsupported_or_oversize_values(value):
    with pytest.raises(ValueError):
        cfl.encode(value)
