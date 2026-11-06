# AirPort Utility behaviour reference

The application should manage the AirPort's actual settings, with Apple's
simple grouping and native macOS controls. A local profile name or a diagnostic
command is not a replacement for a device setting.

## Inspection

Read-only inspection on 6 November 2026 used [REA](https://github.com/morluto/rea)
6.8.0 against the system-installed AirPort Utility. REA's built-in macOS reader
identified Objective-C classes, methods and addresses. Its Interface Builder
decoder identified native controls, outlets and action selectors. No Apple
application code or resource files are included in this repository.

Executable SHA-256:
`c33d4d0928801b4dfebd526fa3c62cb51f25102faf4aba7169045fb61e8c4687`.
The inspected universal binary's selected slice was arm64.

Reproduce without registering an MCP server or modifying agent settings:

```sh
npm exec --yes --package=node@22.23.4 --package=rea-agents@6.8.0 -- \
  rea inspect-native-dispatch-metadata \
  '/System/Applications/Utilities/AirPort Utility.app/Contents/MacOS/AirPort Utility' \
  --format json > airport-dispatch.json
npm exec --yes --package=node@22.23.4 --package=rea-agents@6.8.0 -- \
  rea decode-interface-builder \
  '/System/Applications/Utilities/AirPort Utility.app' \
  --format json > airport-interface.json
```

These are static observations. A selector alone does not prove what a control
writes. The bounded default metadata and document inventories are incomplete;
they do not establish pixel layout or the absence of other features. REA found
no configured decompiler on this Mac. The property mappings below were checked
separately against symbolic arm64 disassembly and read-only device observations.

## Sharing behaviour implemented here

`AUDisksModel` exposes file-sharing enablement, security method, accounts, disk
password, partitions, and erase/archive availability. Its load/save entry points
are `0x1000230e8` and `0x100023c20` in this build. The decoded disks interface has
native account add/remove/edit buttons, a security popup, password verification,
and separate erase/archive actions.

| Setting | Device representation | Preservation rule |
| --- | --- | --- |
| Enable file sharing | `usbF` bit `0x04`, inverted | Preserve every unrelated bit |
| With accounts | `usbF` bit `0x40` clear | Preserve other account fields; apply each user's access |
| With a disk password | `usbF` bit `0x40` set, nonempty `fssp` | Keep the existing password when unchanged |
| With base station password | `usbF` bit `0x40` set, empty `fssp` | Use the base station password at runtime |
| Accounts | `usrd.users`: `name`, `password`, `fileSharingAccess` | Access 0 read/write, 1 read-only, 2 no access |
| Partition inventory | `MaSt` | UUID, name and optional capacity only in public results |

The virtual client settings `bsFS` and `bsFM` are not device property names to
write. Apple's mappings are at `0x10005a4c8`/`0x10005a5ac` and
`0x10005ad58`/`0x10005af30`. Bits `0x10`/`0x20` represent guest access and must not
be mistaken for the security method.

All accounts continue to share only the configured storage folder. This change
does not export a disk root. Passwords travel through the helper's private
credential envelope; public snapshots and revision tokens contain no password
or password-derived hash. Apply requires confirmation, verifies a readback,
restores and verifies the old settings after a failed write, then restarts and
checks the saved settings again. No settings were changed on the development
device during this inspection.

The bundled NetBSD 6 service advertises `airport-sharing-v1` and follows these
settings. Older installed services remain read-only in the editor until updated.
NetBSD 4 account support is not advertised: its existing Samba payload does not
include the per-account backend used by the NetBSD 6 payload.

## Remaining device features

These observations define follow-up work, not working controls in this change.
Do not expose buttons that merely simulate these operations.

| AirPort Utility group | Required user-facing capabilities | Evidence anchor |
| --- | --- | --- |
| Base Station | Device name and password, restart and firmware | Base station settings and task controllers |
| Internet | Connection method, addresses and DNS | `AUInternetModel.loadData` `0x100017dd0`, `saveData` `0x1000186bc` |
| Wireless | Network name, security, password, guest network | `AUWirelessModel.loadData` `0x10001a068`, `saveData` `0x10001bbe8` |
| Network | Router mode, reservations, port settings | `AUNetworkModel.loadData` `0x10001fa24`, `saveData` `0x1000219b8` |
| Disks | Archive to an external disk; disk actions | `AUDisksViewController` archive/erase actions |

The archive confirmation handler at `0x100014438` sends `diskd.archiveDisk` with
`srcUUID` and `dstUUID` as binary UUIDs, plus `archiveName` and `message` strings.
The UI filters for an external, unlocked destination with adequate free space.
Cancellation uses `diskd.cancelArchiveDisk`. Completion/progress and interrupted
copy recovery still need verification before implementing this operation.

Disk health should show its verdict, capacity, temperature and hours in use.
Recognized nonzero reallocated, pending or uncorrectable sectors warrant an
attention message; vendor-specific raw values alone do not establish failure.
Keep the full attribute dump out of the normal interface. The app's additional
file-sharing update action should explain the benefit in one sentence: support
for newer computers, with the installed version visible beside the update.
