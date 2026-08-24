# Getting Listnr onto your iPhone

Two ways, both work with your paid Apple Developer account. No renewal churn:
with a paid account a development-signed build stays valid for the provisioning
profile lifetime (about a year), not 7 days.

**Device requirement: iOS 26.0 or later.** The deployment target is iOS 26 — the app uses the Liquid Glass tab bar, so an older iPhone cannot install this build.

## Way A — direct install from Xcode (fastest, no TestFlight)

1. Connect your iPhone with a cable, unlock it, tap "Trust".
2. Open `Listnr.xcodeproj` in Xcode.
3. Select the **Listnr** target → Signing & Capabilities:
   - Tick "Automatically manage signing"
   - Team: **Luis Kisters (personal team)** — the one tied to the paid membership
4. Select your iPhone in the device menu → Run.
   First time: on the phone go to Settings → General → VPN & Device Management and
   trust your developer certificate.
5. Done. The app keeps its position between launches; audio continues on the lock screen.

## Way B — TestFlight (for builds you want to keep or share)

One-time setup, about five minutes:

1. appstoreconnect.apple.com → Users and Access → Integrators/Keys:
   generate an **App Store Connect API key** (Admin role not needed; App Manager works),
   download the `.p8`, note the Key ID and Issuer ID.
2. Put it somewhere outside this repo, e.g. `~/.appstoreconnect/private_keys/AuthKey_XXXX.p8`.

Per release (every time you want a new build):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# set these three values once
export ASC_KEY_ID=XXXXXX
export ASC_ISSUER_ID=xxxxxx-xxxx
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8

xcodebuild archive -project Listnr.xcodeproj -scheme Listnr \
  -destination 'generic/platform=iOS' \
  -archivePath build/Listnr.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

xcrun altool --upload-app -f build/Listnr.xcarchive/Products/Applications/Listnr.ipa \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --upload
```

(Export an IPA from the archive first: `xcodebuild -exportArchive -exportOptionsPlist …`,
or drag into Transporter.) TestFlight then processes it for ~10 minutes; internal testers
get it immediately after processing. The external beta review is one short form per build.

## Why not automated tonight

The upload needs an App Store Connect API key that does not exist in this environment yet.
Once `ASC_*` variables are present, the block above can be dropped straight into CI.

## V1 device run

Work through this list once on a real iPhone. Write the date next to each item as
you tick it.

- [ ] `xcodegen generate`, open `Listnr.xcodeproj`, target Listnr → Signing & Capabilities:
      automatic signing, team = the paid one. Bundle id stays `com.luisKisters.Listnr`.  Date: ______
- [ ] iPhone on iOS 26 connected and trusted → Run. The deployment target is iOS 26.0,
      so a lower phone cannot install the build at all — check the phone's version first.  Date: ______
- [ ] On the phone: Settings → General → VPN & Device Management → trust the developer
      certificate.  Date: ______
- [ ] Two or three real M4B files in an iCloud Drive folder; in the app tap `+`, pick that
      folder, confirm both appear with real titles, authors, durations and chapter counts.  Date: ______
- [ ] Play, lock the phone: lock-screen artwork, title, chapter and the ±15/30 controls
      work. A book with no embedded artwork must still show the typographic cover on the
      lock screen — that one is rendered through `ImageRenderer`.  Date: ______
- [ ] Arm a 15-minute sleep timer, lock, confirm playback stops on time.  Date: ______
- [ ] Take a note mid-playback: it pauses, saves at the right timestamp, resumes.  Date: ______
- [ ] Force-quit and relaunch: position, folder and notes survive; the rescan adds a newly
      copied M4B without another picker.  Date: ______

**Rule:** any failing item goes back to its owning step (5, 6 or 7) in
`docs/plans/2026-08-22-listnr-v1.md`, never into a workaround in this document.

### Known and deliberate

- An M4B that is still downloading from iCloud shows a notice instead of playing. This is
  by design: `AVAudioPlayer` needs the whole file locally.
- The player cover is square and sits inside the rails, not on them. `ideas.md` records why.
