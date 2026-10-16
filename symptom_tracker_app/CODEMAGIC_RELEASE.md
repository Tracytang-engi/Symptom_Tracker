# Release from Windows with Codemagic

The repository-root `codemagic.yaml` builds on a cloud Mac and uploads the signed
IPA to App Store Connect. Uploading makes the build available for TestFlight after
Apple processing. External beta review and App Store review are separate manual
actions; this workflow does not automatically submit either review.

## One-time setup

1. In Apple Developer, register `com.symptomtracker.symptomTrackerApp` under your
   team. Create an iOS app with the same identifier in App Store Connect. Copy its
   numeric Apple ID from App Information. If the identifier is unavailable, update
   both the Xcode project and the YAML signing identifier before building.
2. Create an App Store Connect team API key with App Manager access. Download its
   `.p8` once and keep it private. Add it in Codemagic Team integrations > Developer
   Portal with the exact integration name `symptom-tracker`, its Key ID and Issuer
   ID. Do not commit signing keys or paste them into chat.
3. In Codemagic Code signing identities, generate or upload an Apple Distribution
   certificate with its private key. Fetch/create the App Store provisioning
   profile for the app and that certificate. An API key alone is not a signing
   certificate. Do not revoke certificates used by GoOffScript.
4. Add GitHub repository `Tracytang-engi/Symptom_Tracker` to Codemagic and select
   YAML configuration. Create environment group `symptom_tracker_release` with
   `APP_STORE_APPLE_ID` set to the numeric Apple ID from step 1.
5. Deploy `backup_server` on Render, set production DATABASE_URL and JWT_SECRET
   privately in Render, and verify `/health` and `/privacy`. Put only the public
   HTTPS Web Service URL in `lib/backup_config.dart`, with no trailing slash.
   The workflow stops before building if that URL is empty or the policy is absent.

## Build and submit

1. Start `ios-app-store` on branch `main`. Flutter is pinned to the locally tested
   3.41.5. On macOS, Flutter generates the missing Podfile; CocoaPods installs Pods.
   Neither needs to be handwritten on Windows. Analysis and tests must pass.
2. The workflow applies signing, increments Apple's latest build number, builds
   an IPA, checks the bundled privacy manifest and uploads it. If the first-build
   lookup fails, check the new App Store Connect app and API key access before retrying.
3. In TestFlight, install the processed build on an iPhone. Check microphone,
   Bluetooth, recording, SMS draft, backup/restore, and account deletion. Deleting
   an account must preserve local episodes. Also check the iPad layout.
4. Complete store metadata, screenshots, support URL, public privacy-policy URL,
   privacy disclosures and review contact information. Describe a recording tool,
   not diagnosis/treatment. State that SOS requires the user to send the SMS.
   Provide a working backup test account and explain any required ESP32 hardware.
5. Select the uploaded build and submit the App Store version for review in the
   browser. A successful CI upload is not an App Store review submission.

Cloud signing/building and real-device behavior cannot be verified on Windows.
Use the first Codemagic build log to diagnose any native plugin or Xcode issues.
