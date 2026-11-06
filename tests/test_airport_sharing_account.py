import plistlib
from unittest import mock

import pytest

from timecapsulesmb.core.config import AppConfig, validate_smb_airport_account
from timecapsulesmb.device.airport_account import read_sharing_account
from timecapsulesmb.services.deploy import render_flash_runtime_config
from timecapsulesmb.device.storage import PayloadHome
from timecapsulesmb.transport.ssh import SshConnection
from timecapsulesmb.checks.doctor_state import DoctorSink, DoctorTarget, RemoteAccess, SmbConfigState
from timecapsulesmb.checks.doctor_steps import _doctor_select_smb_password


def test_selected_account_is_deployed_without_storing_its_password():
    config = AppConfig.from_values({"TC_SMB_AIRPORT_ACCOUNT": "jtenniswood"})
    text = render_flash_runtime_config(config, PayloadHome("/Volumes/dk2", "/dev/dk2", ".samba4"))
    assert "SMB_AIRPORT_ACCOUNT=jtenniswood\n" in text
    assert "PASSWORD" not in text


@pytest.mark.parametrize("name", ["", "jtenniswood", "a.b-c_d", "x" * 63])
def test_selected_account_names_are_validated(name):
    assert validate_smb_airport_account(name, "TC_SMB_AIRPORT_ACCOUNT") is None


@pytest.mark.parametrize("name", ["*", "root\nother", "a:b", "x" * 64, "a b"])
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
