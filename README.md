# HomeVault

HomeVault is an Android-first Flutter client for a router's local FTP server.
The app connects directly from the phone to the configured NAS. It does not
use a bridge, computer service, cloud relay, or automatic deletion of local
files.

## Current status: direct-FTP MVP implementation

The app shell and MVP workflows are implemented: direct FTP connection,
secure credential storage, NAS browsing, Android file picking, uploads with
duplicate skipping, downloads through the Android save picker, progress and
metadata-only transfer history, remote-size verification, folder creation,
rename, delete confirmation, and light/dark Material 3 UI. Results are
reported from the router; no mock success is used.

The container used to prepare this repository does not include Flutter or Dart,
so dependency resolution and Android execution must be performed on a machine
with the Flutter stable SDK installed.

```bash
flutter create .
flutter pub get
flutter test
flutter run -d <android-device>
```

On the phone, use a trusted home network only. Plain FTP does not encrypt
credentials or file contents. The default endpoint is `192.168.11.1:21`, but
all connection fields are editable.

### Manual device validation checklist

1. Connect the phone to the same LAN as the router.
2. Enter the FTP username and password and run **Test connection**.
3. Confirm `/` lists successfully and open `/usb1_1` when present.
4. Use **Back up files**, choose multiple files, select a NAS folder, and
	confirm each result separately.
5. Upload a duplicate name and confirm it is skipped rather than overwritten.
6. Download a remote file through the Android save picker and inspect the
	verification status.
7. Test folder creation, rename, and delete only with disposable data; record
	which operations the router denies.
8. Disable/reconnect Wi-Fi during a transfer and confirm it is failed or
	interrupted rather than falsely completed.

The current transfer implementation is foreground-oriented. Android may pause
or terminate work when the app is closed; uninterrupted background transfers
are not promised. Picker results without a usable local path are rejected
instead of being treated as permanent filesystem paths.