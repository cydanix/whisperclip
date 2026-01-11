# Changelog

## [1.0.45] - 2026-01-11

### Added
- **Hold to Talk mode**: New option to hold the hotkey to record and release to stop, instead of press-to-toggle. Enable in Settings → Hot Key → Recording Mode.
- **Recording overlay position options**: Choose overlay position (top-left, top-right, bottom-left, bottom-right) in Settings.
- **Start minimized option**: New setting to launch the app minimized to the Dock. Enable in Settings → General → Startup Behavior.
- **Donation dialog**: A friendly, non-intrusive donation prompt appears after 10 successful recordings to support continued development.
- **Donate menu item**: Added "Donate ❤️" option to the status bar menu for easy access.

### Improved
- **Model loading progress**: Added animated progress indicator during model compilation phase, so users see activity instead of a stuck progress bar.
- **Better punctuation**: Enabled WhisperKit's prefill prompt for improved automatic punctuation in transcriptions.
- **Overlay positioning**: Bottom overlay positions now correctly avoid the macOS Dock.

### Fixed
- Fixed recording overlay not hiding when main window is closed during recording.
- Fixed race condition where recording overlay wouldn't show when triggered by hotkey.
