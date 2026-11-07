"""Opt-in AirPort account tests on a separate, loopback-only Samba instance.

    .venv/bin/python -m tests.samba.airport_accounts_device --env .env --binary bin/samba4/smbd

Requires smbprotocol and pycryptodome on the Mac. Creates fictional credentials
in memory and a private, temporary password database on the device. It never
changes AirPort accounts, production configuration or the active SMB server.
Only a uniquely named scratch folder inside the configured share is exported.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
from pathlib import Path
import secrets
import shlex
import time
import uuid

from Crypto.Hash import MD4
from smbprotocol.connection import Connection
from smbprotocol.exceptions import SMBResponseException
from smbprotocol.session import Session
from smbprotocol.tree import TreeConnect

from tests.samba.dir_device import (
    Client, DELETE, FILE_NON_DIRECTORY_FILE, GENERIC_READ, GENERIC_WRITE,
    STATUS_ACCESS_DENIED, status_of,
)
from tests.samba.links_device import Device
from tests.samba.device_supervision import open_file
from timecapsulesmb.core.config import parse_env_file
from timecapsulesmb.transport.ssh import ssh_local_forward

READ_ONLY_ERRORS = (STATUS_ACCESS_DENIED, 0xC00000A2)  # MEDIA_WRITE_PROTECTED


class AccountClient(Client):
    def __init__(self, username: str, password: str, port: int, client_guid=None):
        self.conn = Connection(client_guid or uuid.uuid4(), "127.0.0.1", port, require_signing=True)
        self.conn.connect(timeout=15)
        try:
            self.sess = Session(self.conn, username, password, require_encryption=False)
            self.sess.connect()
            self.tree = TreeConnect(self.sess, r"\\127.0.0.1\AccountProbe")
            self.tree.connect()
        except Exception:
            self.conn.disconnect()
            raise


@contextmanager
def client(username: str, password: str, port: int):
    connection = AccountClient(username, password, port)
    try:
        yield connection
    finally:
        connection.close()


def check(value: bool, message: str):
    if not value:
        raise AssertionError(message)
    print("PASS " + message, flush=True)


def login_refused(username: str, password: str, port: int) -> bool:
    try:
        with client(username, password, port):
            return False
    except SMBResponseException as error:
        return error.status in (0xC000006D, 0xC0000064, 0xC0000072, 0xC0000022)


def independent_durable_identity(passwords, port):
    from smbprotocol.create_contexts import SMB2CreateDurableHandleRequestV2, SMB2CreateDurableHandleReconnectV2

    client_guid, create_guid = uuid.uuid4(), uuid.uuid4()
    original = AccountClient("writer", passwords["writer"], port, client_guid)
    request = SMB2CreateDurableHandleRequestV2()
    request["timeout"] = 60000
    request["create_guid"] = create_guid
    handle, responses = open_file(original.tree, "durable", contexts=[request], create=True, batch=True)
    check(any(type(context).__name__ == "SMB2CreateDurableHandleResponseV2" for context in responses),
          "server grants durable handle to original account")
    content = b"durable owner identity"
    handle.write(content, 0)
    handle.flush()
    file_id = handle.file_id
    original.conn.disconnect(close=False)

    def reconnect(tree):
        context = SMB2CreateDurableHandleReconnectV2()
        context["file_id"] = file_id
        context["create_guid"] = create_guid
        return open_file(tree, "durable", contexts=[context], batch=True)

    other = AccountClient("#family", passwords["#family"], port, client_guid)
    try:
        status, result = status_of(lambda: reconnect(other.tree))
        if result:
            result[0].close()
        check(status != 0, "different account cannot reclaim durable handle")
    finally:
        other.close()
    owner = AccountClient("writer", passwords["writer"], port, client_guid)
    try:
        handle, _ = reconnect(owner.tree)
        check(handle.read(0, len(content)) == content, "original account can reclaim its durable handle")
        handle.close()
    finally:
        owner.close()


def run(device: Device, binary: Path, *, remote_port: int = 1445, local_port: int = 11445):
    token = uuid.uuid4().hex[:12]
    binary_dir = device.payload_disk() + "/.samba4/.airport-account-probe-" + token
    # HFS uses synthetic ownership on the appliance. Samba's strict-owned
    # messaging locks and private state belong on MFS, as in production.
    private = "/mnt/Memory/.airport-account-probe-" + token
    storage = device.root + "/__tc_account_probe_" + token
    outside = private + "/outside"
    q = shlex.quote
    passwords = {name: secrets.token_urlsafe(24)
                 for name in ("writer", "reader", "denied", "#family", "Café team")}

    def publish(access=None, *, missing_metadata=False, empty=False):
        permissions = dict(writer=0, reader=1, denied=2)
        permissions.update({"#family": 0, "Café team": 0})
        permissions.update(access or {})
        rows = []
        for index, (name, permission) in enumerate(permissions.items()):
            nt_hash = MD4.new(passwords[name].encode("utf-16-le")).hexdigest().upper()
            marker = "" if missing_metadata else f"TCA-{permission}:"
            # Deliberately leave the denied record's U flag set: the backend
            # must enforce the access marker independently of that flag.
            rows.append(f"{name}:{65536 + index}:" + "X" * 32 + f":{nt_hash}:[U          ]:LCT-00000001:{marker}\n")
        device.put(private + "/accounts.new", b"" if empty else "".join(rows).encode())
        device.sh(f"chmod 600 {q(private + '/accounts.new')} && "
                  f"mv {q(private + '/accounts.new')} {q(private + '/accounts')}")

    config = f"""[global]
    server role = standalone server
    security = user
    map to guest = Never
    passdb backend = tc_airport:{private}/accounts
    netbios name = TCACCOUNTPROBE
    workgroup = WORKGROUP
    interfaces = 127.0.0.1
    bind interfaces only = yes
    smb ports = {remote_port}
    server min protocol = SMB2_02
    server max protocol = SMB3
    server signing = mandatory
    smb encrypt = if_required
    private dir = {private}/state
    state directory = {private}/state
    cache directory = {private}/state
    lock directory = {private}/locks
    pid directory = {private}/run
    ncalrpc dir = {private}/run/ncalrpc
    dbwrap_tdb_mutexes:* = no
    log file = {private}/log.smbd
    log level = 3
    load printers = no
    disable spoolss = yes
    aio read size = 0
    aio write size = 0
    max smbd processes = 12
    server multi channel support = no
[AccountProbe]
    path = {storage}
    read only = no
    guest ok = no
    wide links = no
    kernel oplocks = no
    kernel share modes = no
    posix locking = no
    durable handles = yes
"""
    try:
        device.sh(f"umask 077 && mkdir {q(private)} {q(binary_dir)} && "
                  f"mkdir {q(private + '/state')} {q(private + '/locks')} {q(private + '/run')} && "
                  f"mkdir {q(storage)} && chmod 755 {q(storage)}")
        device.put(binary_dir + "/airport-auth-probe", binary.read_bytes())
        expected_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
        check(hashlib.sha256(device.sh_bytes(f"cat {q(binary_dir + '/airport-auth-probe')}")).hexdigest() == expected_hash,
              "uploaded server matches branch build")
        device.put(private + "/smb.conf", config.encode())
        device.put(storage + "/existing", b"configured storage folder\n")
        device.put(outside, b"outside must not be shared\n")
        device.sh(f"ln -s {q(outside)} {q(storage + '/escape')} && "
                  f"chmod 755 {q(binary_dir + '/airport-auth-probe')} && chmod 600 {q(private + '/smb.conf')}")
        publish()
        device.sh(f"trap '' HUP; {q(binary_dir + '/airport-auth-probe')} -F --no-process-group "
                  f"--debug-stdout -l {q(private)} -s {q(private + '/smb.conf')} "
                  f"</dev/null >{q(private + '/startup.log')} 2>&1 & "
                  f"echo $! >{q(private + '/probe.pid')}")
        with ssh_local_forward(device.connection, local_port=local_port, remote_host="127.0.0.1",
                               remote_port=remote_port):
            time.sleep(2)
            with client("writer", passwords["writer"], local_port) as writer:
                handle = writer.open("new", GENERIC_READ | GENERIC_WRITE | DELETE, 2, FILE_NON_DIRECTORY_FILE)
                handle.write(b"independent account write", 0)
                check(handle.read(0, 25) == b"independent account write", "writer can create, read and write")
                writer.rename(handle, "renamed")
                writer.delete_on_close(handle)
                handle.close()
                check(True, "writer can rename and delete")
                for path in ("escape", "..\\" + private.rsplit("/", 1)[-1] + "\\outside"):
                    status, handle = status_of(lambda p=path: writer.open(p, GENERIC_READ, 1, FILE_NON_DIRECTORY_FILE))
                    if handle:
                        handle.close()
                    check(status != 0, "share boundary refuses " + ("external symlink" if path == "escape" else "parent traversal"))
            with client("reader", passwords["reader"], local_port) as reader:
                handle = reader.open("existing", GENERIC_READ, 1, FILE_NON_DIRECTORY_FILE)
                check(handle.read(0, 26) == b"configured storage folder\n", "read-only account can read")
                handle.close()
                for name, access, disposition in (("existing", GENERIC_WRITE, 1), ("new", GENERIC_WRITE, 2)):
                    status, handle = status_of(lambda: reader.open(name, access, disposition, FILE_NON_DIRECTORY_FILE))
                    if handle:
                        handle.close()
                    check(status == STATUS_ACCESS_DENIED, "read-only account denied write/create")
                # Samba may allow a DELETE-access handle on a read-only share;
                # the actual mutation must still fail and leave the file intact.
                handle = reader.open("existing", DELETE, 1, FILE_NON_DIRECTORY_FILE)
                try:
                    status, _ = status_of(lambda: reader.rename(handle, "must-not-rename"))
                    check(status in READ_ONLY_ERRORS, "read-only account denied rename")
                    status, _ = status_of(lambda: reader.delete_on_close(handle))
                    check(status in READ_ONLY_ERRORS, "read-only account denied delete")
                finally:
                    handle.close()
                handle = reader.open("existing", GENERIC_READ, 1, FILE_NON_DIRECTORY_FILE)
                check(handle.read(0, 26) == b"configured storage folder\n", "refused mutations leave the file intact")
                handle.close()
            for name in ("#family", "Café team"):
                with client(name, passwords[name], local_port) as connection:
                    handle = connection.open("existing", GENERIC_READ, 1, FILE_NON_DIRECTORY_FILE)
                    handle.close()
                check(True, "special account name authenticates: " + name)
            independent_durable_identity(passwords, local_port)
            for username, password, label in (
                ("writer", secrets.token_urlsafe(), "wrong password"),
                ("reader", passwords["writer"], "another account's password"),
                ("denied", passwords["denied"], "no-access account"),
                ("root", device.env["TC_PASSWORD"], "device password fallback"),
            ):
                check(login_refused(username, password, local_port), label + " rejected")
            publish({"writer": 1})
            with client("writer", passwords["writer"], local_port) as reader:
                status, handle = status_of(lambda: reader.open("existing", GENERIC_WRITE, 1, FILE_NON_DIRECTORY_FILE))
                if handle:
                    handle.close()
                check(status == STATUS_ACCESS_DENIED, "permission update applies to new login")
            old_password = passwords["writer"]
            passwords["writer"] = secrets.token_urlsafe(24)
            publish()
            with client("writer", passwords["writer"], local_port):
                check(True, "changed password applies to new login")
            check(login_refused("writer", old_password, local_port), "previous account password rejected")
            publish(missing_metadata=True)
            check(login_refused("writer", passwords["writer"], local_port), "missing permission metadata fails closed")
            publish(empty=True)
            check(login_refused("writer", passwords["writer"], local_port), "removed accounts cannot log in")
    except Exception:
        # The isolated server knows only fictional passwords. Level-3 logs
        # contain status messages and usernames, never the password database.
        log = device.sh(f"tail -n 60 {q(private + '/startup.log')} {q(private)}/log.* "
                        f"{q(private + '/exit-status')} 2>/dev/null", check=False)
        if log:
            print(log, flush=True)
        raise
    finally:
        pid_text = device.sh(f"cat {q(private + '/probe.pid')} 2>/dev/null", check=False).strip()
        if pid_text.isdigit():
            device.sh(f"kill {int(pid_text)}", check=False)
            time.sleep(2)
        device.sh(f"rm -rf {q(private)} {q(binary_dir)} {q(storage)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--env", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    args = parser.parse_args()
    run(Device(parse_env_file(args.env)), args.binary)


if __name__ == "__main__":
    main()
