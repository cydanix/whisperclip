#!/usr/bin/env bash
set -euo pipefail

CONFIG=${1:-Release}

xcodebuild \
  -scheme WhisperClip \
  -configuration $CONFIG \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build \
  ARCHS=arm64 \
  build
