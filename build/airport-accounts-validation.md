# AirPort account payload validation

The NetBSD 6 payloads in this change contain the account parser in `service`
and the `tc_airport` password backend in Samba 4.25.0. Both are required.
NetBSD 4 payloads are unchanged; the installer refuses account mode on those
devices rather than installing the original device-password backend.

The payloads were cross-compiled on macOS with Apple Clang 21, Zig 0.15.2's
LLD, and the official NetBSD 7.0 evbarm-earm headers and libraries. They target
ARMv4T, EABI, software floating point and strict alignment. Dependency archive
versions and SHA-256 pins match `env.sh`: GMP 6.3.0, nettle 3.10.1,
libtasn1 4.20.0 and patched GnuTLS 3.8.5. GnuTLS uses its included unistring
implementation, with threads and C11 atomics disabled; the old target has no
usable pthread runtime or generic C11 atomic load/store library. Heimdal uses
its existing NetBSD atomic fallback. Host-only ASN.1/error-table generators
were compiled for macOS separately from target code.

Both executables are static ARM ELF images with no dynamic loader or TLS
segment and one writable load segment. The checks in
`_data_segment_check.sh` verified the retained fault-ahead constructor, the
initialized-data bounds, and the fork/mmap repair wrappers before stripping.
These kernel workarounds remain necessary even when using a different linker.
The runtime now sets its local RPC directory explicitly instead of relying on
the compiler's staging prefix.

The replay tool verified that the exported Samba patch series reproduces the
built source tree. Artifact hashes are recorded in the normal manifest.

## Device checks

`tests/samba/airport_accounts_device.py` runs the branch's server on a separate
loopback-only port through SSH. Its private databases and locks live in RAM;
its uniquely named test share is inside the existing configured storage folder.
It uses fictional credentials and leaves AirPort accounts and production
settings unchanged. On a NetBSD 6 Time Capsule it verified:

- independent passwords, including Unicode and leading-`#` account names;
- writable accounts can create, read, write, rename and delete;
- read-only accounts can read but cannot write, create, rename or delete;
- refused mutations preserve the original file;
- no-access accounts, wrong passwords and device-password fallback are refused;
- password and permission changes apply to new connections;
- deleted accounts and records missing permissions fail closed;
- external symlinks and parent traversal cannot escape the configured folder;
- an interrupted durable handle can be reclaimed by its original account, and
  cannot be reclaimed by a different account with the same SMB client identity.

The branch's native helper also ran on the device and produced the expected
hash and access mode for the live AirPort account, compared privately in memory.
The account parser, staging/configuration, manager, deployment, Checkup and
artifact tests cover the host-side behavior. Existing authenticated sessions
keep their permissions until they disconnect; account edits affect new logins.
