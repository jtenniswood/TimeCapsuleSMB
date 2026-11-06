import plistlib
from contextlib import nullcontext
from types import SimpleNamespace
from unittest import mock

import pytest

from timecapsulesmb.core.config import AppConfig, validate_smb_airport_account
from timecapsulesmb.device.airport_account import read_sharing_account
from timecapsulesmb.services.deploy import render_flash_runtime_config
from timecapsulesmb.device.storage import PayloadHome
from timecapsulesmb.transport.ssh import SshConnection
from timecapsulesmb.checks.doctor_state import DoctorSink, DoctorTarget, RemoteAccess, SmbConfigState
from timecapsulesmb.checks.doctor_steps import _doctor_select_smb_password
from timecapsulesmb.checks import doctor_steps
from timecapsulesmb.checks.models import CheckResult


def test_selected_account_is_deployed_without_storing_its_password():
    config = AppConfig.from_values({"TC_SMB_AIRPORT_ACCOUNT": "jtenniswood"})
    text = render_flash_runtime_config(config, PayloadHome("/Volumes/dk2", "/dev/dk2", ".samba4"))
    assert "SMB_AIRPORT_ACCOUNT=jtenniswood\n" in text
    assert "PASSWORD" not in text


@pytest.mark.parametrize("name", ["", "*", "jtenniswood", "a.b-c_d", "x" * 63])
def test_selected_account_names_are_validated(name):
    assert validate_smb_airport_account(name, "TC_SMB_AIRPORT_ACCOUNT") is None


@pytest.mark.parametrize("name", ["**", "root\nother", "a:b", "x" * 64, "a b"])
def test_unsafe_selected_account_names_are_rejected(name):
    assert validate_smb_airport_account(name, "TC_SMB_AIRPORT_ACCOUNT") is not None


@pytest.mark.parametrize("access", [0, 1])
def test_checkup_reads_current_account_password_without_saving_it(access):
    connection = SshConnection(host="root@192.0.2.1", password="admin-password", ssh_opts="")
    password = " sharing<&😀\n "
    raw = plistlib.dumps({"users": [dict(name="jtenniswood", password=password, fileSharingAccess=access)]})
    with mock.patch("timecapsulesmb.device.airport_account.run_ssh_capture_bytes", return_value=raw) as capture:
        account = read_sharing_account(connection, "jtenniswood")
    capture.assert_called_once_with(connection, "/usr/bin/acp -q usrd", timeout=25)
    assert account.password == password and account.read_only == (access == 1)
    assert password not in repr(account)
    assert connection.password == "admin-password"


@pytest.mark.parametrize("raw", [b"secret password not XML", plistlib.dumps({"users": []}),
    plistlib.dumps({"users": [dict(name="jtenniswood", password="secret", fileSharingAccess=2)]}),
    plistlib.dumps({"users": [dict(name="jtenniswood", password="secret", fileSharingAccess=0)] * 2}),
    b"x" * 65537])
def test_checkup_errors_do_not_expose_acp_data(raw):
    connection = SshConnection(host="root@192.0.2.1", password="admin", ssh_opts="")
    with mock.patch("timecapsulesmb.device.airport_account.run_ssh_capture_bytes", return_value=raw):
        with pytest.raises(ValueError) as error:
            read_sharing_account(connection, "jtenniswood")
    assert "secret" not in str(error.value)
    assert error.value.__suppress_context__


@pytest.mark.parametrize("available", [True, False])
def test_checkup_uses_the_active_selection_without_falling_back(available):
    connection = SshConnection(host="root@192.0.2.1", password="admin", ssh_opts="")
    target = DoctorTarget(connection, "192.0.2.1", "admin")
    remote = RemoteAccess(True, True, True, "")
    sink = DoctorSink(None, {})
    config = SmbConfigState("[global]\n    tc:airport account = jtenniswood\n", "")
    raw = plistlib.dumps({"users": [dict(name="jtenniswood", password="sharing-secret", fileSharingAccess=1)]})
    with mock.patch("timecapsulesmb.device.airport_account.run_ssh_capture_bytes",
                    return_value=raw if available else b"private malformed password"):
        selected = _doctor_select_smb_password(target, remote, config, sink)
    assert selected.connection is connection and selected.smb_account == "jtenniswood"
    assert selected.smb_password_available == available
    assert selected.smb_password == ("sharing-secret" if available else "")
    assert selected.smb_read_only == available
    assert "sharing-secret" not in repr(selected)
    assert "sharing-secret" not in repr(sink.results)
    assert "private malformed password" not in repr(sink.results)


@pytest.mark.parametrize("writer", [True, False])
def test_automatic_checkup_selection_uses_an_enabled_account(writer):
    users = [dict(name="denied", password="denied secret", fileSharingAccess=2),
             dict(name='Café % "reader"', password="reader secret", fileSharingAccess=1)]
    if writer:
        users.append(dict(name="writer", password="writer secret", fileSharingAccess=0))
    raw = plistlib.dumps({"users": users})
    target = DoctorTarget(SshConnection("root@192.0.2.1", "admin", ""), "192.0.2.1", "admin")
    sink = DoctorSink(None, {})
    with mock.patch("timecapsulesmb.device.airport_account.run_ssh_capture_bytes", return_value=raw):
        selected = _doctor_select_smb_password(target, RemoteAccess(True, True, True, ""),
                                              SmbConfigState("[global]\n tc:airport account = *\n", ""), sink)
    assert selected.smb_password_available
    assert selected.smb_account == ("writer" if writer else 'Café % "reader"')
    assert selected.smb_password == ("writer secret" if writer else "reader secret")
    assert selected.smb_read_only is not writer
    assert "secret" not in repr(selected) + repr(sink.results)


def test_tunnel_uses_the_account_username_for_listing_and_file_operations():
    listing = CheckResult("PASS", "listed", {"server": "127.0.0.1"})
    with mock.patch.object(doctor_steps, "ssh_local_forward", return_value=nullcontext()), \
         mock.patch.object(doctor_steps, "find_free_local_port", return_value=12345), \
         mock.patch.object(doctor_steps, "_authenticated_smb_listing_with_doctor_retries", return_value=listing) as list_shares, \
         mock.patch.object(doctor_steps, "_select_smb_file_ops_share", return_value="Data"), \
         mock.patch.object(doctor_steps, "check_authenticated_smb_file_ops_detailed", return_value=[]) as file_ops:
        doctor_steps._add_tunneled_authenticated_smb_results(
            mock.sentinel.connection, smb_password="account secret", smb_username="writer",
            active_share_names=["Data"], active_smb_conf_reason="", debug_fields=None, add_result=lambda result: None,
        )
    assert list_shares.call_args.args[:2] == ("writer", "account secret")
    assert file_ops.call_args.args[:2] == ("writer", "account secret")


def test_lan_uses_the_account_username_for_listing_and_file_operations():
    listing = CheckResult("PASS", "listed", {"server": "device.local"})
    with mock.patch.object(doctor_steps, "_doctor_smb_client_targets", return_value=["device.local"]), \
         mock.patch.object(doctor_steps, "_authenticated_smb_listing_with_doctor_retries", return_value=listing) as list_shares, \
         mock.patch.object(doctor_steps, "_select_smb_file_ops_share", return_value="Data"), \
         mock.patch.object(doctor_steps, "check_authenticated_smb_file_ops_detailed", return_value=[]) as file_ops:
        doctor_steps._add_authenticated_smb_results(
            AppConfig.from_values({}), None, None, smb_password="account secret", smb_username="writer",
            active_smb_conf="[Data]\npath = /share\n", active_smb_conf_reason="",
            direct_smb=SimpleNamespace(reachable_addresses=()), include_file_ops=True, device_smb_passed=False,
            debug_fields=None, add_result=lambda result: None,
        )
    assert list_shares.call_args.args[:2] == ("writer", "account secret")
    assert file_ops.call_args.args[:2] == ("writer", "account secret")
