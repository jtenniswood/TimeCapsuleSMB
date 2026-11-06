"""Read AirPort accounts without shell evaluation or a shared-password fallback."""
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


def account_set(binary, users, *, raw=None):
    result = read(binary, users, name="--all", raw=raw)
    rows = [line.split("\t") for line in result.stdout.decode().splitlines()]
    return result, {name: (int(uid), int(access), nt_hash) for uid, access, name, nt_hash in rows}


def test_every_account_has_its_own_password_and_permission(account_reader):
    users = [
        dict(name="writer", password="writer secret", fileSharingAccess=0),
        dict(name="reader", password="reader secret", fileSharingAccess=1),
        dict(name="denied", password="", fileSharingAccess=2),
        dict(name='Café % "team"', password="utf8 😀", fileSharingAccess=0),
    ]
    result, accounts = account_set(account_reader, users)
    assert result.returncode == 0, result.stderr
    assert len(accounts) == len(users)
    assert len({entry[0] for entry in accounts.values()}) == len(users)
    for user in users:
        uid, access, nt_hash = accounts[user["name"]]
        assert 65536 <= uid <= 0x2000FFFF
        assert access == user["fileSharingAccess"]
        assert nt_hash == ("0" * 32 if access == 2 else MD4.new(user["password"].encode("utf-16-le")).hexdigest().upper())
    assert result.stdout == account_set(account_reader, list(reversed(users)))[0].stdout


def test_adding_removing_or_changing_passwords_preserves_other_identities(account_reader):
    alice = dict(name="alice", password="first", fileSharingAccess=0)
    bob = dict(name="bob", password="second", fileSharingAccess=1)
    _, before = account_set(account_reader, [alice, bob])
    _, after = account_set(account_reader, [dict(bob, password="new password")])
    assert set(after) == {"bob"}
    assert after["bob"][:2] == before["bob"][:2]
    assert after["bob"][2] != before["bob"][2]
    _, renamed = account_set(account_reader, [dict(bob, name="BOB")])
    assert renamed["BOB"] == before["bob"]


def test_empty_account_list_is_valid_and_enables_no_logins(account_reader):
    result, accounts = account_set(account_reader, [])
    assert result.returncode == 0 and accounts == {}


@pytest.mark.parametrize("name", ["", "a:b", "a\nb", "a\rb", "a\tb", "a\\b", "a/b", "x" * 256])
def test_unrepresentable_names_reject_the_whole_snapshot(account_reader, name):
    result, accounts = account_set(account_reader, [
        dict(name="valid", password="secret", fileSharingAccess=0),
        dict(name=name, password="secret", fileSharingAccess=0),
    ])
    assert result.returncode != 0 and accounts == {} and result.stderr == b""


def test_ambiguous_names_are_never_silently_merged(account_reader):
    result, accounts = account_set(account_reader, [
        dict(name="Alice", password="one", fileSharingAccess=0),
        dict(name="alice", password="two", fileSharingAccess=1),
    ])
    assert result.returncode != 0 and accounts == {}


def test_distinct_names_with_colliding_ids_reject_the_whole_snapshot(account_reader):
    # These names share the bounded FNV identity used for Samba's user SID.
    users = [dict(name=name, password="secret", fileSharingAccess=access)
             for name, access in [("collision-19324", 0), ("collision-58640", 1)]]
    _, first = account_set(account_reader, users[:1])
    _, second = account_set(account_reader, users[1:])
    assert next(iter(first.values()))[0] == next(iter(second.values()))[0]
    result, accounts = account_set(account_reader, users)
    assert result.returncode != 0 and accounts == {} and result.stderr == b""


def test_leading_hash_is_an_account_name(account_reader):
    result, accounts = account_set(account_reader, [
        dict(name="#family", password="secret", fileSharingAccess=0),
    ])
    assert result.returncode == 0 and "#family" in accounts


def test_account_count_and_capture_are_bounded(account_reader):
    users = [dict(name=f"user-{i}", password="secret", fileSharingAccess=0) for i in range(128)]
    result, accounts = account_set(account_reader, users)
    assert result.returncode == 0 and len(accounts) == 128
    result, accounts = account_set(account_reader, users + [dict(name="extra", password="x", fileSharingAccess=0)])
    assert result.returncode != 0 and accounts == {}
    result, accounts = account_set(account_reader, [], raw=b" " * 262145)
    assert result.returncode != 0 and accounts == {}


def test_long_utf8_account_names_fit_the_password_database(account_reader):
    name = "é" * 127 + "x"
    result, accounts = account_set(account_reader, [dict(name=name, password="secret", fileSharingAccess=0)])
    assert result.returncode == 0 and name in accounts
