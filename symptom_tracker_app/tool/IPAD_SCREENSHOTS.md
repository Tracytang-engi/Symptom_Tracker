# iPad App Store screenshots

In Codemagic, start a new build from `main` and choose
**SensaTrace - iPad Screenshots**, not the App Store publishing workflow.
No Apple API key, signing certificate or Render connection is required.

The workflow runs the real app widgets on an installed 13-inch iPad Pro
simulator (12.9-inch fallback). It captures portrait PNGs at 2064 x 2752 or
2048 x 2732 pixels, without stretching or editing the UI. It also exports JPEGs
without alpha channels for store upload. Download
`SensaTrace-iPad-screenshots.zip` from the build artifacts and extract it.

Review every image before uploading to the 13-inch iPad screenshot slot:

- `01-home.jpg`
- `02-timeline.jpg`
- `03-episode-detail.jpg`
- `04-settings.jpg`

Confirm that text is readable, no content overlaps, and there are no permission
dialogs, debug banners or error screens. Do not upload failed/partial captures.
The app name still appears as Symptom Tracker, matching the current binary.

The test entry point uses fictional local records marked as examples. It does
not sign in, upload backups, send messages, or simulate a connected ESP32.
Background notification startup and BLE event handling are disabled only in
the screenshot test. The production entry point and screens are unchanged.

This workflow creates screenshots only; it does not publish an IPA or replace
the build already selected in App Store Connect. It must be run on macOS;
Windows cannot execute the iOS simulator. If no suitable simulator is installed,
inspect the Codemagic Xcode image rather than substituting an iPhone capture.
