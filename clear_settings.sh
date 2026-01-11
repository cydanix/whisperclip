#! /bin/bash

# Usage: ./clear_settings.sh [key]
# If key is provided, deletes only that setting
# If no key is provided, deletes all settings

if [ -n "$1" ]; then
    defaults delete com.whisperclip "$1" 2>/dev/null
    defaults delete WhisperClip "$1" 2>/dev/null
    echo "Deleted setting: $1"
else
    defaults delete com.whisperclip 2>/dev/null
    defaults delete WhisperClip 2>/dev/null
    echo "Deleted all settings"
fi
