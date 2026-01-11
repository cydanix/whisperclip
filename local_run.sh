#!/usr/bin/env bash
set -euo pipefail

CONFIG=${1:-Release}

./local_build.sh $CONFIG

# Run the app in the background and detach from terminal
LOCAL_RUN=1 LOG_TO_CONSOLE=1 LOG_SENSITIVE_DATA=1 build/Build/Products/$CONFIG/WhisperClip
