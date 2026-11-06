# Mac interface

AirPort Utility is the visual reference. The audience is a person who wants to
use a shared disk, without learning its software or network internals.

- Use the Mac system font: 13 pt regular for labels and controls, 11 pt for
  secondary information, 13 pt semibold for section labels, 17 pt for setup
  titles and device names. `UtilityStyle` owns these choices.
- Use native tabs, fields, checkboxes, menus, alerts and disclosure controls.
- Align form labels to the right. Keep fields and actions aligned between panes.
- Use 24 pt pane margins and section spacing, 12 pt between related rows.
- Avoid repeated pane titles, state pills, tinted cards and decorative icons.
- Give each action one clear home. App preferences belong in the app menu;
  device-specific settings belong in the device editor. Keep a single action
  row at the bottom of forms.
- Present the next useful decision. Prefer a short label or one sentence to
  paragraphs of explanation. Help and advanced details are optional.
- Say “file sharing” and “disk” in everyday screens. Software names, protocol
  options, internal paths, raw readings and logs belong in advanced details.
- Always show an actionable failure and any warning about losing files. An
  expanded details view must never be required to discover a critical warning.
- Preserve operation ownership, cancellation rules, confirmations and saved
  credentials. Presentation changes must not start a device operation on their own.

The visual review must cover the device canvas and popover; nearby/manual setup;
password entry, progress and errors; every device tab; every maintenance tool;
app Settings; empty, active and completed Activity; startup failures, support
details and confirmation dialogs. Review light and dark appearances, the minimum
window size, and longer translated labels. Operating-system password prompts
and Sparkle's update windows retain their native presentation.
