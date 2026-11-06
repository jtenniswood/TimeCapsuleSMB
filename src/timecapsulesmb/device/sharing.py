"""AirPort disk settings. Credentials stay in memory and off public payloads."""
from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import plistlib
import re
import socket
import uuid

from timecapsulesmb.integrations import acp, cfl
from timecapsulesmb.transport.ssh import SshConnection, run_ssh_capture_bytes, run_ssh_input, ssh_local_forward


def managed_sharing_disabled(connection: SshConnection) -> bool:
    """Only the managed runtime's explicit opt-in makes Apple's switch apply."""
    try:
        data = run_ssh_capture_bytes(connection,
            "if grep -Eq \"^AIRPORT_SHARING_SETTINGS=('1'|1)$\" /mnt/Flash/tcapsulesmb.conf; then /usr/bin/acp -q usbF; fi", timeout=25)
        return len(data) <= 32 and bool(int(data.strip(), 0) & 4)
    except Exception:
        return False


class SharingSettingsError(ValueError):
    pass


def _name(value: object) -> str:
    if (not isinstance(value, str) or not value or len(value.encode()) > 255
            or any(ord(char) < 32 or ord(char) == 127 or char in ":/\\" for char in value)):
        raise SharingSettingsError("Enter a valid account name.")
    return value


def _password(value: object) -> str:
    if not isinstance(value, str) or not value or "\0" in value or len(value.encode()) > 4096:
        raise SharingSettingsError("Enter a password for each new account or disk password.")
    return value


@dataclass(repr=False)
class SharingSettings:
    flags: int
    users: dict = field(repr=False)
    disk_password: str = field(repr=False)
    supported: bool
    partitions: list[dict[str, object]] = field(default_factory=list)

    @property
    def enabled(self) -> bool:
        return not bool(self.flags & 4)

    @property
    def security(self) -> str:
        return "accounts" if not self.flags & 0x40 else "disk_password" if self.disk_password else "device_password"

    def public(self) -> dict[str, object]:
        accounts = [{"name": user["name"], "access": user["fileSharingAccess"]} for user in self.users["users"]]
        visible = {"enabled": self.enabled, "security": self.security, "accounts": accounts}
        # No password or hash of a password is exposed as the revision token.
        revision = hashlib.sha256(json.dumps([self.flags, visible], sort_keys=True).encode()).hexdigest()
        return {"schema_version": 1, **visible, "revision": revision, "supported": self.supported, "partitions": self.partitions}


def read_settings(connection: SshConnection) -> SharingSettings:
    try:
        flags_data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q usbF", timeout=25)
        if len(flags_data) > 32:
            raise ValueError
        flags = int(flags_data.strip(), 0)
        if not 0 <= flags <= 0xffffffff:
            raise ValueError
        data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q usrd", timeout=25)
        if len(data) > 262144:
            raise ValueError
        users = plistlib.loads(data)
        records = users["users"]
        if not isinstance(records, list) or len(records) > 128:
            raise ValueError
        names = set()
        for user in records:
            name = _name(user["name"])
            if name.casefold() in names or type(user.get("fileSharingAccess")) is not int or user["fileSharingAccess"] not in (0, 1, 2):
                raise ValueError
            if not isinstance(user.get("password"), str):
                raise ValueError
            names.add(name.casefold())
        disk = run_ssh_capture_bytes(connection, "/usr/bin/acp -q fssp 2>&1", timeout=25)
        if len(disk) > 8192 or disk.startswith(b"###"):
            raise ValueError
        disk_password = disk.decode().removesuffix("\n")
        try:
            feature = run_ssh_capture_bytes(connection, "/mnt/Flash/service --print-sharing-features", timeout=10)
        except Exception:
            feature = b""
        return SharingSettings(flags, users, disk_password, feature.strip() == b"airport-sharing-v1", _read_partitions(connection))
    except Exception:
        # XML parser and SSH errors can quote the entire credential record.
        pass
    # Outside the handler: diagnostic helpers must not recover the original
    # XML/SSH exception through __context__, even if they ignore `from None`.
    raise SharingSettingsError("The sharing settings could not be read. Check the connection and try again.")


def _read_partitions(connection: SshConnection) -> list[dict[str, object]]:
    # A missing or unreadable disk must not prevent turning sharing off or
    # editing accounts. Capacity is optional; it is not a disk-health verdict.
    partitions: list[dict[str, object]] = []
    try:
        mast_data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q MaSt", timeout=25)
        if len(mast_data) > 1_048_576:
            raise ValueError
        disks = plistlib.loads(mast_data)
        if not isinstance(disks, list) or len(disks) > 32:
            raise ValueError
        for disk in disks:
            if not isinstance(disk, dict) or not isinstance(disk.get("partitions"), list):
                continue
            for partition in disk["partitions"][:32]:
                if not isinstance(partition, dict):
                    continue
                try:
                    raw_uuid = partition.get("uuid")
                    identity = str(uuid.UUID(bytes=raw_uuid)) if isinstance(raw_uuid, bytes) and len(raw_uuid) == 16 else str(uuid.UUID(str(raw_uuid)))
                except (ValueError, TypeError):
                    continue
                name = partition.get("name")
                if not isinstance(name, str) or len(name.encode()) > 255:
                    continue
                size = partition.get("size")
                free = partition.get("sizeFree")
                partitions.append({"id": identity, "name": name, "builtin": disk.get("builtin") is True,
                    "size_mib": size if type(size) is int and 0 <= size <= 2**43 else None,
                    "free_mib": free if type(free) is int and 0 <= free <= 2**43 else None})
    except Exception:
        return []
    return partitions


def changed_settings(current: SharingSettings, changes: object, credentials: object) -> SharingSettings:
    if not isinstance(changes, dict) or set(changes) != {"enabled", "security", "accounts", "revision"}:
        raise SharingSettingsError("The sharing settings are incomplete.")
    if not current.supported:
        raise SharingSettingsError("Update File Sharing before changing these settings.")
    if changes["revision"] != current.public()["revision"]:
        raise SharingSettingsError("The sharing settings changed in another app. Reload them and try again.")
    enabled, security, records = changes["enabled"], changes["security"], changes["accounts"]
    if type(enabled) is not bool or security not in ("accounts", "disk_password", "device_password"):
        raise SharingSettingsError("Choose how to secure the shared disk.")
    if not isinstance(records, list) or len(records) > 128 or not isinstance(credentials, dict):
        raise SharingSettingsError("The account list is invalid.")
    passwords = credentials.get("account_passwords", {})
    if not isinstance(passwords, dict):
        raise SharingSettingsError("The account passwords are invalid.")
    existing = {user["name"]: user for user in current.users["users"]}
    result, names, sources = [], set(), set()
    for record in records:
        if not isinstance(record, dict) or set(record) - {"name", "source_name", "access"}:
            raise SharingSettingsError("The account list is invalid.")
        name = _name(record.get("name"))
        source, access = record.get("source_name"), record.get("access")
        if source is not None and not isinstance(source, str):
            raise SharingSettingsError("The account list is invalid.")
        if name.casefold() in names or type(access) is not int or access not in (0, 1, 2):
            raise SharingSettingsError("Use a different name for each account and choose its access.")
        names.add(name.casefold())
        if source is not None and (source not in existing or source in sources):
            raise SharingSettingsError("An account changed in another app. Reload the settings and try again.")
        if source is not None:
            sources.add(source)
        user = dict(existing[source]) if source is not None else {}
        user.update(name=name, fileSharingAccess=access)
        if name in passwords:
            user["password"] = _password(passwords[name])
        elif source is None:
            raise SharingSettingsError("Enter a password for the new account.")
        result.append(user)
    if enabled and security == "accounts" and not any(user["fileSharingAccess"] in (0, 1) for user in result):
        raise SharingSettingsError("Add an account with disk access before enabling sharing.")
    disk_password = current.disk_password
    if security == "disk_password":
        if "disk_password" in credentials:
            disk_password = _password(credentials["disk_password"])
        elif current.security != "disk_password":
            raise SharingSettingsError("Enter a disk password.")
    else:
        disk_password = ""
    flags = current.flags & ~0x44
    if not enabled:
        flags |= 4
    if security != "accounts":
        flags |= 0x40
    return SharingSettings(flags, {**current.users, "users": result}, disk_password, True, current.partitions)


def write_settings(connection: SshConnection, desired: SharingSettings, previous: SharingSettings) -> None:
    # The new service follows Apple's settings automatically. Unknown config
    # lines, including the selected storage folder, remain byte-for-byte intact.
    error_message: str | None = None
    try:
        config = run_ssh_capture_bytes(connection, "cat /mnt/Flash/tcapsulesmb.conf", timeout=25)
        if len(config) > 65536 or b"\0" in config:
            raise ValueError
        updated = re.sub(rb"(?m)^AIRPORT_SHARING_SETTINGS=.*\n?", b"", config).rstrip(b"\n") + b"\nAIRPORT_SHARING_SETTINGS=1\n"
        # Encode both batches before writing anything. Unknown plist types
        # fail here without leaving a partly applied change on the device.
        def properties(value: SharingSettings) -> dict[str, int | bytes]:
            return {"usrd": cfl.encode(value.users), "fssp": value.disk_password.encode(), "usbF": value.flags}
        desired_properties, previous_properties = properties(desired), properties(previous)
        # SSH and base station passwords can differ. Root can read Apple's
        # local property, so settings writes do not assume they are the same.
        admin_data = run_ssh_capture_bytes(connection, "/usr/bin/acp -q syPW 2>&1", timeout=25)
        if len(admin_data) > 8192 or admin_data.startswith(b"###") or b"\0" in admin_data:
            raise ValueError
        admin_password = admin_data.decode().removesuffix("\n")
        def save_config(data: bytes) -> None:
            temporary = "/mnt/Flash/tcapsulesmb.conf.sharing-" + uuid.uuid4().hex
            run_ssh_input(connection, f"umask 077\nset -Ce\ntmp={temporary}\ntrap 'rm -f \"$tmp\"' EXIT HUP INT TERM\ncat > \"$tmp\"\nmv \"$tmp\" /mnt/Flash/tcapsulesmb.conf\nsync",
                          input_bytes=data, timeout=25)
        def matches(value: SharingSettings) -> bool:
            actual = read_settings(connection)
            return actual.flags == value.flags and actual.users == value.users and actual.disk_password == value.disk_password
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with ssh_local_forward(connection, local_port=port, remote_host="127.0.0.1", remote_port=acp.ACP_PORT):
            config_attempted = False
            try:
                acp.set_properties("127.0.0.1", admin_password, desired_properties, port=port)
                if not matches(desired):
                    raise ValueError
                config_attempted = True
                save_config(updated)
            except Exception:
                try:
                    acp.set_properties("127.0.0.1", admin_password, previous_properties, port=port)
                    if config_attempted:
                        save_config(config)
                    if not matches(previous):
                        raise ValueError
                except Exception:
                    error_message = "The settings could not be verified or restored. Reconnect to your AirPort and check its sharing settings."
                else:
                    error_message = "The update could not be verified. The previous sharing settings were restored."
    except Exception:
        error_message = "The sharing settings could not be saved. Reconnect and try again."
    if error_message:
        raise SharingSettingsError(error_message)
