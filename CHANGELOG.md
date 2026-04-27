# Changelog

## 2026-04-27

### `23e58bf` - Stop launchd service by project plist

- Improves the stop script so it can unload the LaunchDaemon associated with this project's `server.js`.
- Helps cleanly stop older locally installed service instances without relying on a machine-specific launchd label.

### `d3c9181` - Manage server with launchd scripts

- Updates the start command to install and kickstart a LaunchDaemon instead of leaving a loose background process.
- Adds a stop command for unloading the service.
- Adds a launchd plist template and ignores generated plist files.
- Replaces machine-specific Node paths and launchd labels with portable defaults.

### `784245b` - Send Left Option as modifier-only HID report

- Fixes Typeless activation from the phone button on systems that reject modifier keys duplicated in the HID key array.
- Sends Left Option through the HID modifier byte only, matching the standard report format.
- Keeps the existing Typeless hotkey behavior unchanged for users configured to use Left Option.
