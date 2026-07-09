# Contributing to Switcher

Thanks for helping improve Switcher. This project is a native macOS Swift app, so changes should stay focused, testable, and consistent with the existing SwiftUI/AppKit style.

## Development setup

1. Fork and clone the repository.
2. Install full Xcode with Swift 6.2 or newer. Command Line Tools alone can build the executable, but `swift test` needs Xcode's XCTest support.
3. Verify the selected toolchain:

   ```bash
   xcode-select -p
   xcodebuild -version
   ```

   If `xcode-select -p` points at `/Library/Developer/CommandLineTools`, select Xcode before running tests:

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

4. Run the test suite:

   ```bash
   swift test
   ```

   `no such module 'XCTest'` or `unable to find utility "xctest"` means the active toolchain does not provide XCTest.

5. Run the app locally:

   ```bash
   swift run Switcher
   ```

## Pull requests

- Open an issue first for large behavior changes, permissions changes, or UI workflow changes.
- Keep pull requests focused on one bug fix or feature.
- Add or update tests when changing state management, settings persistence, window layout, or permission behavior.
- Include manual test notes for UI changes, especially macOS version, display setup, and Accessibility permission state.
- Run `swift test` before requesting review.

## Code style

- Follow the existing Swift naming and file organization.
- Prefer small types with explicit responsibilities over large view/controller changes.
- Avoid adding third-party dependencies unless they clearly reduce maintenance burden.
- Keep user-facing text concise and macOS-native.

## Reporting bugs

Use the bug report template and include:

- macOS version and hardware architecture.
- Steps to reproduce.
- Expected and actual behavior.
- Relevant logs, screenshots, or screen recordings when useful.
