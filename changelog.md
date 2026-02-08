# Changelog

## [1.0.50] - 2026-02-08

### Added
- **Meetings settings tab**: New dedicated Settings tab for meeting-related preferences.
  - **Auto-start toggle**: Choose whether recording begins automatically when a meeting app is detected.
  - **Auto-stop toggle**: Choose whether recording stops automatically when the meeting app closes.
  - **Auto-stop delay slider**: Configurable 0–30 second grace period before auto-stop triggers, to avoid false stops.
  - **Auto-summary toggle**: Enable or disable automatic AI summary generation after a meeting ends.
  - **Monitored apps picker**: Select which meeting apps (Zoom, Teams, Meet, Webex, Slack, Discord, FaceTime) trigger auto-detection.

### Fixed
- **Final audio chunk lost on stop**: Fixed a race condition where `stopCapture()` spawned a fire-and-forget Task to drain audio buffers, then immediately cleared the buffers and nil'd the callback. The final chunk now drains synchronously and is processed before the transcription pipeline is torn down.
- **Meeting detection accuracy**: Improved `isAppInMeeting` with three-strategy detection — window title keyword matching, non-meeting window filtering, and a frontmost-app fallback when Screen Recording permission doesn't expose window names. Updated Zoom, Teams, and Slack window-title keywords for better hit rates.
- **Meeting status stuck on "processing"**: Meetings are now always marked completed after summary generation, even if the LLM encounters an error.
- **Summary generated for empty meetings**: Skipped summary generation when no transcript segments were recorded.

### Improved
- **Meeting auto-detect sync**: Toggling auto-detect in Settings now immediately starts or stops the detection timer without requiring an app restart.
- **Detection logging**: Diagnostic log output from the 2-second detection timer is now throttled to once every 30 seconds to reduce log noise.
- **Browser meeting detection**: `checkBrowserForMeetings` now returns all detected browser-based meetings instead of only the first, and respects the monitored-apps filter.
- **Settings view refactor**: Split the monolithic `SettingsView` body into per-tab computed properties (`generalTab`, `hotKeyTab`, `meetingsTab`, `promptsTab`) for maintainability.

## [1.0.49] - 2026-02-08

### Added
- **AI Meeting Notes**: Granola-style intelligent meeting capture with live transcription, structured summaries, and action items.
  - **Live transcription**: Real-time speech-to-text during meetings with animated waveform visualization.
  - **Dual-channel audio**: Separate microphone ("Me") and system audio ("Others") streams with accurate per-source timestamps and chronological merging.
  - **Speaker diarization**: Uses FluidAudio's DiarizerManager for proper speaker separation with WeSpeaker embeddings and clustering. Automatically identifies "Me" vs "Others" in the conversation.
  - **AI summaries**: Auto-generated brief and detailed meeting summaries using embedded LLM.
  - **Key topics extraction**: Automatically identifies and summarizes main discussion points.
  - **Action items**: AI extracts action items with assignee detection from meeting content.
  - **Decision tracking**: Captures key decisions made during the meeting.
  - **Follow-ups**: Lists items that need follow-up after the meeting.
  - **Post-meeting Q&A**: Ask questions about any meeting and get AI-powered answers from the transcript.
  - **Meeting app auto-detection**: Auto-detects Zoom, Microsoft Teams, Google Meet, Webex, Slack, Discord, and FaceTime. Automatically starts/stops recording with a 5-second grace period to avoid false positives.
  - **Meeting hotkey**: Configurable global hotkey (default: Control+M) to start/stop meeting recording from anywhere.
  - **Export options**: Copy meetings as Markdown or export transcripts and summaries.
- **Meeting Notes sidebar panel**: Beautiful UI with live recording view and meeting list with search.
- **Meeting detail view**: Full meeting notes with tabs for Summary, Transcript, Actions, and Q&A.
- **Meeting waveform visualization**: Animated audio level display during recording.
- **Speaker ID model in onboarding**: Optional download step for speaker diarization model (required for Meeting Notes speaker identification).

### Improved
- **Live transcription reliability**: Fixed audio buffer errors during meeting recording by copying recording data before processing.
- **Transcript timestamp accuracy**: Mic and system audio chunks now carry their actual capture timestamps instead of a shared timer, ensuring correct chronological ordering.
- **LLM context limits**: Increased transcript truncation limits for meeting AI analysis (4K → 24K characters) to leverage the full LLM context window.
- **Q&A display**: Meeting detail view now reads directly from storage as a computed property, fixing an issue where Q&A answers were generated but not displayed due to a SwiftUI state management race condition.
- **Meeting auto-detection**: Fixed detection logic to check window titles instead of triggering on any focused meeting app. Detection now includes minimized/background windows and the auto-detect preference is persisted across app launches.

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
