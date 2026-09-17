#!/bin/sh
# Remove the Claude Usage plasmoid.
set -e
id=com.github.samsam07.claudeusage
kpackagetool6 --type Plasma/Applet --remove "$id"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/$id.svg"
echo "Removed. The cached usage stays in ~/.local/share/plasmashell/QML Offline Storage/;"
echo "delete that directory if you want it gone too."
