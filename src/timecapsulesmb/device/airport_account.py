"""Read a sharing credential in memory; never include ACP data in errors."""
from dataclasses import dataclass, field
import plistlib

from timecapsulesmb.transport.ssh import SshConnection, run_ssh_capture_bytes


@dataclass(frozen=True)
class AirportSharingAccount:
    password: str = field(repr=False)
    read_only: bool
    name: str = ""


def read_sharing_account(connection: SshConnection, name: str) -> AirportSharingAccount:
    try:
        data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q usrd", timeout=25)
        if len(data) > 262144:
            raise ValueError
        value = plistlib.loads(data)
        users = value["users"]
        if not isinstance(users, list) or len(users) > 128:
            raise ValueError
        names: set[str] = set()
        for user in users:
            username = user.get("name") if isinstance(user, dict) else None
            if (not isinstance(username, str) or not username or len(username.encode()) > 255
                    or any(ord(c) < 32 or ord(c) == 127 or c in ":/\\" for c in username)
                    or username.casefold() in names):
                raise ValueError
            names.add(username.casefold())
        if name == "*":
            # Prefer an enabled writer so Checkup can exercise file operations;
            # use an enabled reader when the device has no writable accounts.
            matches = sorted((u for u in users if type(u.get("fileSharingAccess")) is int
                              and u["fileSharingAccess"] in (0, 1)),
                             key=lambda u: (u["fileSharingAccess"], u["name"].casefold()))[:1]
        else:
            matches = [u for u in users if u["name"] == name]
        if len(matches) != 1:
            raise ValueError
        user = matches[0]
        password, access = user["password"], user["fileSharingAccess"]
        if (not isinstance(password, str) or not password or "\0" in password
                or len(password.encode()) > 4096 or type(access) is not int or access not in (0, 1)):
            raise ValueError
        return AirportSharingAccount(password, access == 1, user["name"])
    except Exception:
        # Even malformed XML and transport exceptions can contain credentials.
        raise ValueError("The selected AirPort sharing account is unavailable, disabled or invalid.") from None
