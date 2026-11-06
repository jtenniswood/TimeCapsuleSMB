"""Read the selected sharing password in memory; never include ACP data in errors."""
from dataclasses import dataclass, field
import plistlib

from timecapsulesmb.transport.ssh import SshConnection, run_ssh_capture_bytes


@dataclass(frozen=True)
class AirportSharingAccount:
    password: str = field(repr=False)
    read_only: bool


def read_sharing_account(connection: SshConnection, name: str) -> AirportSharingAccount:
    try:
        data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q usrd", timeout=25)
        if len(data) > 65536:
            raise ValueError
        value = plistlib.loads(data)
        users = value["users"]
        if not isinstance(users, list):
            raise ValueError
        matches = [u for u in users if isinstance(u, dict) and u.get("name") == name]
        if len(matches) != 1:
            raise ValueError
        user = matches[0]
        password, access = user["password"], user["fileSharingAccess"]
        if (not isinstance(password, str) or not password or "\0" in password
                or len(password.encode()) > 4096 or type(access) is not int or access not in (0, 1)):
            raise ValueError
        return AirportSharingAccount(password, access == 1)
    except Exception:
        # Even malformed XML and transport exceptions can contain credentials.
        raise ValueError("The selected AirPort sharing account is unavailable, disabled or invalid.") from None
