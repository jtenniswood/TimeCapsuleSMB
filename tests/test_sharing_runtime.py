import pytest

from timecapsulesmb.device.errors import AcpdQuitError, DeviceError
from timecapsulesmb.device.probe import ManagerStartupAgeProbeResult
from timecapsulesmb.services import runtime_verification as verification
from timecapsulesmb.transport.ssh import SshConnection


@pytest.mark.parametrize("state,port_open,error", [
    (ManagerStartupAgeProbeResult(2, "running", acpd_running=True), False, None),
    (ManagerStartupAgeProbeResult(None, "missing", acpd_running=True), False, DeviceError),
    (ManagerStartupAgeProbeResult(2, "running", acpd_running=True), True, DeviceError),
    (ManagerStartupAgeProbeResult(2, "running", acpd_running=False), False, AcpdQuitError),
    (ManagerStartupAgeProbeResult(2, "unknown"), False, DeviceError),
])
def test_disabled_sharing_requires_a_live_manager_and_acpd_with_no_smb_listener(monkeypatch, state, port_open, error):
    monkeypatch.setattr(verification, "managed_sharing_disabled", lambda _: True)
    monkeypatch.setattr(verification, "tcp_open", lambda *_: port_open)
    def verify():
        return verification.verify_managed_runtime_ready(SshConnection("root@capsule.local", "admin", ""),
            stage="verify_runtime", timeout_seconds=0, heading="Ready", failure_message="Failed", read_start_state=lambda _: state)
    if error:
        with pytest.raises(error):
            verify()
    else:
        result = verify()
        assert result.ready and not result.samba_ready
