# Contributing to Switcher

Thanks for helping improve Switcher. This project is a native macOS Swift app, so changes should stay focused, testable, and consistent with the existing SwiftUI/AppKit style.

## Development setup

1. Fork and clone the repository.
2. Install Xcode with Swift 6.2 or newer.
3. Run the test suite:

   ```bash
   swift test
   ```

4. Run the app locally:

   ```bash
   swift run SidebarPin
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
