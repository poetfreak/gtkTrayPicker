#!/usr/bin/env bash
# Eric's nifty build script for Freebasic.
LOGFILE="buildlog.txt"
BUILD_FLAGS="-s gui"

if [ "${debug:-0}" = "1" ]; then
    BUILD_FLAGS="$BUILD_FLAGS -g -exx"
fi

if fbc $BUILD_FLAGS traypicker.bas -x traypicker >"$LOGFILE" 2>&1; then
    chmod 755 traypicker
    printf '\033[1;32;47mBUILD SUCCEEDED\033[0m\n'
    exit 0
fi

printf '\033[1;31;47mBUILD FAILED\033[0m\n'
cat "$LOGFILE"
# Slap the log on clipboard for AI or build logs or whatever.
if command -v wl-copy >/dev/null 2>&1; then
    wl-copy <"$LOGFILE"
elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <"$LOGFILE"
fi

exit 1
