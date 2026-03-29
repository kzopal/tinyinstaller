#!/bin/sh
# detect_keyboard.sh - detects keyboard input device
 
if [ -e /dev/input ]; then
    echo "Keyboard detected."
else
    echo "No keyboard detected."
fi