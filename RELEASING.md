# Releasing Switcher

This project is a SwiftPM macOS app. `swift run Switcher` is useful for local development, but a distributable release should be packaged as a signed `.app` bundle and notarized before sharing.

## Prerequisites

- Full Xcode with Swift 6.2 or newer.
- An Apple Developer account with a Developer ID Application certificate.
- Accessibility permission tested on the target macOS version.
- A clean changelog entry in `CHANGELOG.md`.

Verify the active toolchain:

```bash
xcode-select -p
xcodebuild -version
swift --version
```

If Xcode is not selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build

Create a release executable:

```bash
swift build -c release
```

The executable is written under:

```bash
swift build -c release --show-bin-path
```

## App Bundle

The repository does not currently define an Xcode archive target, so create a `.app` bundle from the release executable when preparing a distributable artifact:

```bash
APP_NAME=Switcher
BUNDLE_ID=com.kshitiz.Switcher
VERSION=1.1.0
BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_DIR=".build/release/${APP_NAME}.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
```

Use the final bundle identifier chosen for the release channel. Keep it stable between releases so macOS permissions and login-item state remain predictable.

## Signing

Unsigned development builds can run locally, but launch-at-login and Gatekeeper behavior are not representative until the app is signed and notarized.

Sign the bundle with a Developer ID Application identity:

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  ".build/release/Switcher.app"
```

Validate the signature:

```bash
codesign --verify --deep --strict --verbose=2 ".build/release/Switcher.app"
spctl --assess --type execute --verbose ".build/release/Switcher.app"
```

## Notarization

Create a zip for notarization:

```bash
ditto -c -k --keepParent ".build/release/Switcher.app" ".build/release/Switcher.zip"
```

Submit and staple:

```bash
xcrun notarytool submit ".build/release/Switcher.zip" \
  --keychain-profile "SwitcherNotaryProfile" \
  --wait

xcrun stapler staple ".build/release/Switcher.app"
```

Validate the stapled app:

```bash
spctl --assess --type execute --verbose ".build/release/Switcher.app"
```

## Release Checklist

1. Update `AppVersion.current`.
2. Update `CHANGELOG.md`.
3. Run `swift test` with full Xcode selected.
4. Run `swift build -c release`.
5. Package the `.app`.
6. Sign and notarize the `.app`.
7. Manually test launch, Accessibility permission flow, pinning, resizing, launch-at-login, global hotkey, multiple Spaces, and at least one multi-display setup.
8. Tag the release and attach the notarized artifact.
