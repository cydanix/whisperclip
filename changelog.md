# Changelog

## [1.0.49] - 2026-02-07

### Added
- **AI Meeting Notes**: Granola-style intelligent meeting capture with live transcription, structured summaries, and action items.
  - **Live transcription**: Real-time speech-to-text during meetings with animated waveform visualization.
  - **Speaker diarization**: Uses FluidAudio's DiarizerManager for proper speaker separation with WeSpeaker embeddings and clustering. Automatically identifies "Me" vs "Others" in the conversation.
  - **AI summaries**: Auto-generated brief and detailed meeting summaries using embedded LLM.
  - **Key topics extraction**: Automatically identifies and summarizes main discussion points.
  - **Action items**: AI extracts action items with assignee detection from meeting content.
  - **Decision tracking**: Captures key decisions made during the meeting.
  - **Follow-ups**: Lists items that need follow-up after the meeting.
  - **Post-meeting Q&A**: Ask questions about any meeting and get AI-powered answers from the transcript.
  - **Meeting app detection**: Auto-detects Zoom, Microsoft Teams, Google Meet, Webex, Slack, Discord, and FaceTime.
  - **Export options**: Copy meetings as Markdown or export transcripts and summaries.
- **Meeting Notes sidebar panel**: Beautiful UI with live recording view and meeting list with search.
- **Meeting detail view**: Full meeting notes with tabs for Summary, Transcript, Actions, and Q&A.
- **Meeting waveform visualization**: Animated audio level display during recording.

## [1.0.48] - 2026-02-06

### Added
- **Background operation**: The app now keeps running in the background when the window is closed or Cmd-Q is pressed. Transcription, hotkeys, and audio capture continue working with only the menu bar icon visible. Use the "Quit" option in the menu bar to fully exit.

### Improved
- **Start minimized**: Now hides the window entirely instead of minimizing to the Dock.

## [1.0.47] - 2026-02-06

### Added
- **Close button on Setup Guide**: You can now dismiss the onboarding wizard at any time using the close icon in the top-right corner.

### Improved
- **Low disk space warning**: Instead of blocking model downloads when disk space is low, the app now shows a warning and lets you choose to continue anyway.
- **Disk space detection reliability**: Fixed `getFreeDiskSpace` returning 0 KB for some users by resolving to the nearest existing directory, adding a home-directory fallback, and logging each step for easier diagnostics.

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
