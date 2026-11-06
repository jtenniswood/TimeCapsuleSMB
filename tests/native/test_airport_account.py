"""Read one shared password from AirPort without shell evaluation or fallback."""
import plistlib
import subprocess

import pytest
from Crypto.Hash import MD4

from tests.native.build import ROOT, compile_modules


@pytest.fixture(scope="module")
def account_reader(tmp_path_factory):
    binary = tmp_path_factory.mktemp("airport-account") / "read"
    compile_modules(binary, ("native/service/airport_account.c", "native/service/nt_hash.c",
                             "native/common/acp.c"),
                    flags=("-I", str(ROOT / "build/native")),
                    extra_sources=(ROOT / "tests/native/unit/test_airport_account.c",))
    return binary


def read(binary, users, *, name="jtenniswood", raw=None):
    return subprocess.run([str(binary), name], input=raw if raw is not None else plistlib.dumps({"users": users}),
                          capture_output=True, timeout=5)


@pytest.mark.parametrize("password", ["password", " Café<&\"'\\😀\n ", "x" * 4096])
@pytest.mark.parametrize("access", [0, 1])
def test_selects_named_account_and_preserves_exact_password(account_reader, password, access):
    result = read(account_reader, [dict(name="other", password="different", fileSharingAccess=0),
                                   dict(name="jtenniswood", password=password, fileSharingAccess=access)])
    expected = MD4.new(password.encode("utf-16-le")).hexdigest().upper()
    assert result.returncode == 0, result.stderr
    assert result.stdout.decode() == f"{access} {expected}\n"
    assert result.stderr == b""


@pytest.mark.parametrize("users", [[], [dict(name="other", password="secret", fileSharingAccess=0)],
    [dict(name="jtenniswood", password="secret", fileSharingAccess=2)]])
def test_absent_deleted_or_disabled_account_disables_smb(account_reader, users):
    result = read(account_reader, users)
    assert result.returncode == 0
    assert result.stdout == b"2 " + b"0" * 32 + b"\n"


@pytest.mark.parametrize("users", [
    [dict(name="jtenniswood", password="", fileSharingAccess=0)],
    [dict(name="jtenniswood", password="x" * 4097, fileSharingAccess=0)],
    [dict(name="jtenniswood", fileSharingAccess=0)],
    [dict(name="jtenniswood", password="secret")],
    [dict(name="jtenniswood", password="secret", fileSharingAccess=3)],
    [dict(name="jtenniswood", password="secret", fileSharingAccess=0)] * 2,
])
def test_invalid_selected_account_fails_without_password_output(account_reader, users):
    result = read(account_reader, users)
    assert result.returncode != 0
    assert result.stdout == result.stderr == b""


@pytest.mark.parametrize("raw", [b"", b"### get failed", b"<plist><dict/></plist>garbage",
    b"<plist><dict><key>users</key><dict/></dict></plist>",
    b"<plist><dict><key>users</key><array/>",
    b"<plist><dict><key>users</key><array/></dict></plist>\0",
    b'<!DOCTYPE plist [<!ENTITY x "secret">]><plist><dict/></plist>',
    b"<plist><dict><key>users</key><array/><key>users</key><array/></dict></plist>",
    b"<plist><dict><key>users</key><array/><key>deep</key>" + b"<array>" * 33 + b"</array>" * 33 + b"</dict></plist>",
])
def test_malformed_truncated_or_ambiguous_xml_never_falls_back(account_reader, raw):
    result = read(account_reader, [], raw=raw)
    assert result.returncode != 0
    assert result.stdout == result.stderr == b""
