# Changelog

## [1.0.46] - 2026-01-13

### Added
- **Parakeet voice-to-text engine**: New speech recognition option using FluidAudio with Apple Neural Engine support. Supports 25 European languages with excellent accuracy.
- **Sidebar navigation**: Redesigned main interface with a modern sidebar containing Microphone, Audio File, and History sections.
- **Audio file transcription**: New feature to transcribe audio files (MP3, WAV, M4A, AIFF, FLAC, OGG) via drag-and-drop or file picker.
- **Transcription history**: Browse past transcriptions with date/time, source indicator (mic/file), and easy copy functionality.
- **History search**: Full-text search across transcription history with highlighted matches.
- **Setup Guide menu item**: Quick access to onboarding/setup from the menu bar.

### Changed
- **Apple Silicon only**: App now requires Apple Silicon Mac (M1 or later) for optimal AI performance.
- **Redesigned UI**: Modern dark theme with gradient backgrounds, animations, and polished visual effects.
- **Dynamic hotkey display**: Hotkey shown in sidebar and microphone view now updates in real-time when changed in settings.
- **Code organization**: Refactored large UI components into separate files for better maintainability.

### Fixed
- Fixed hotkey display not updating when changed in settings.
- Fixed sidebar alignment with window traffic light buttons.

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
