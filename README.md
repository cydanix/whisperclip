# WhisperClip

<div align="center">

![WhisperClip Logo](icons/icon_256x256.png)

**Privacy-First Voice-to-Text with AI Enhancement for macOS**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)

[Website](https://whisperclip.com) • [Download](https://whisperclip.com/v2/download) • [Changelog](changelog.md) • [Support](mailto:support@cydanix.com)

</div>

## ✨ Features

### 🎤 **Voice-to-Text Transcription**
- High-quality speech recognition using WhisperKit
- Multiple model sizes (216MB to 955MB) for different accuracy/speed trade-offs
- Support for multiple languages with auto-detection
- Real-time waveform visualization during recording

### 🤖 **AI-Powered Text Enhancement**
- Local LLM processing for grammar correction and text improvement
- Multiple AI models including Gemma, Llama, Qwen, and Mistral
- Custom prompts for different use cases:
  - Grammar fixing and email formatting
  - Language translation
  - Custom text processing workflows

### 🔒 **Privacy-First Design**
- **100% local processing** - your voice never leaves your device
- No cloud services, no data collection
- Open source - audit the code yourself
- Secure sandboxed environment

### ⚡ **Productivity Features**
- Global hotkey support (Option+Space by default)
- **Hold to Talk mode** - hold hotkey to record, release to stop
- Auto-copy to clipboard
- Auto-paste functionality
- Auto-enter for instant message sending
- Menu bar integration
- Start minimized option
- Auto-stop recording after 10 minutes

### 🎨 **User Experience**
- Beautiful dark-themed interface
- Real-time recording visualization
- Recording overlay with customizable position
- Comprehensive onboarding guide
- Easy model management and downloads
- Customizable shortcuts and prompts

## 📋 Requirements

- **macOS 14.0** or later
- **20GB** free disk space (for AI models)
- **Microphone access** permission
- **Accessibility permissions** (for global hotkeys)
- **Apple Events permissions** (for clipboard operations)

## 🚀 Installation

### Download Pre-built App
1. Visit [whisperclip.com](https://whisperclip.com)
2. Download the latest release
3. Drag WhisperClip.app to your Applications folder
4. Follow the setup guide for permissions

### Build from Source
```bash
# Clone the repository
git clone https://github.com/cydanix/whisperclip.git
cd whisperclip

# Build the app
./build.sh

# For development
./local_build.sh Debug
./local_run.sh Debug
```

## 🔧 Usage

### Quick Start
1. **Launch WhisperClip** from Applications or menu bar
2. **Grant permissions** when prompted (microphone, accessibility)
3. **Download AI models** through the setup guide
4. **Press Option+Space** (or click Record) to start recording
5. **Press again to stop** - text will be automatically copied to clipboard

### Customization
- **Change hotkey**: Settings → Hotkey preferences
- **Add custom prompts**: Settings → Prompts → Add new prompt
- **Switch AI models**: Setup Guide → Download different models
- **Configure auto-actions**: Settings → Enable auto-paste/auto-enter

## 🤖 Supported AI Models

### Speech-to-Text (WhisperKit)
- **OpenAI Whisper Small** (216MB) - Fast, good quality
- **OpenAI Whisper Large v3 Turbo** (632MB) - Best balance
- **Distil Whisper Large v3 Turbo** (600MB) - Optimized speed
- **OpenAI Whisper Large v2 Turbo** (955MB) - Maximum accuracy

### Text Enhancement (Local LLMs)
- **Gemma 2 (2B/9B)** - Google's efficient models
- **Llama 3/3.2 (3B/8B)** - Meta's powerful models
- **Qwen 2.5/3 (1.5B-8B)** - Alibaba's multilingual models
- **Mistral 7B** - High-quality French company model
- **Phi 3.5 Mini** - Microsoft's compact model
- **DeepSeek R1** - Advanced reasoning model

All models run locally using MLX for Apple Silicon optimization.

## 🔒 Privacy & Security

WhisperClip is designed with privacy as the cornerstone:

- **Local Processing Only**: All voice recognition and AI processing happens on your device
- **No Network Requests**: Except for downloading models from Hugging Face
- **No Analytics**: No usage tracking, no telemetry, no data collection
- **Open Source**: Full transparency - inspect the code yourself
- **Sandboxed**: Runs in Apple's secure app sandbox
- **Encrypted Storage**: AI models stored securely on device

## 🛠 Development

### Project Structure
```
Sources/
├── WhisperClip.swift      # Main app entry point
├── ContentView.swift      # Main UI interface
├── AudioRecorder.swift    # Voice recording logic
├── VoiceToText*.swift     # Transcription engine
├── LLM*.swift            # AI text enhancement
├── ModelStorage.swift     # Model management
├── SettingsStore.swift    # User preferences
└── HotkeyManager.swift    # Global shortcuts
```

### Dependencies
- **WhisperKit**: Apple's optimized Whisper implementation
- **MLX**: Apple Silicon ML framework
- **MLX-Swift-Examples**: LLM implementations
- **Hub**: Hugging Face model downloads

### Building
```bash
# Debug build
./local_build.sh Debug

# Release build with code signing
./build.sh

# Notarization (requires Apple Developer account)
./notarize.sh
```

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes** and add tests
4. **Commit your changes**: `git commit -m 'Add amazing feature'`
5. **Push to branch**: `git push origin feature/amazing-feature`
6. **Open a Pull Request**

### Areas for Contribution
- New AI model integrations
- UI/UX improvements
- Performance optimizations
- Language support
- Accessibility features
- Documentation improvements

## 📄 License

WhisperClip is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

This means you can:
- ✅ Use commercially
- ✅ Modify and distribute
- ✅ Use privately
- ✅ Fork and create derivatives

**Attribution required**: Please include the original license notice.

## 🏢 About

WhisperClip is developed by **Cydanix LLC**.

- **Website**: [whisperclip.com](https://whisperclip.com)
- **Support**: [support@cydanix.com](mailto:support@cydanix.com)
- **Version**: 1.0.45

## 🙏 Acknowledgments

- **Apple** - WhisperKit and MLX frameworks
- **OpenAI** - Original Whisper models
- **Hugging Face** - Model hosting and Hub library
- **ML Community** - Open source AI models (Gemma, Llama, Qwen, etc.)

---

<div align="center">

**Made with ❤️ for privacy-conscious users**

[⭐ Star this repo](https://github.com/cydanix/whisperclip) if you find it useful!

</div>
