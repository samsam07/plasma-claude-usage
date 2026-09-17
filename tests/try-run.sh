#!/bin/sh
# Reinstall the applet, run it windowed, and report any QML errors.
# Qt routes warnings to the journal in a systemd session, so that is where we look.
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.." || exit 1

kpackagetool6 --type Plasma/Applet --upgrade package >/dev/null 2>&1 \
    || kpackagetool6 --type Plasma/Applet --install package >/dev/null 2>&1

since=$(date '+%Y-%m-%d %H:%M:%S')
timeout "${1:-12}" plasmawindowed com.github.samsam07.claudeusage >/dev/null 2>&1

# Catches load failures, binding errors, and runtime JS exceptions alike.
errors=$(journalctl --user --since "$since" --no-pager 2>/dev/null \
    | grep -E "error when loading applet|\.qml:[0-9]+|\.js:[0-9]+|TypeError|ReferenceError|Unable to assign|Cannot assign|is not a function|is not defined|claudeusage.*[Ww]arning" \
    | grep -v "propagateSizeHints" \
    | sed 's/^.*plasmawindowed\[[0-9]*\]: //')

if [ -n "$errors" ]; then
    printf 'QML ERRORS:\n%s\n' "$errors"
    exit 1
fi
echo "loaded with no QML errors"
