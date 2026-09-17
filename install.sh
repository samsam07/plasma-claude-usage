#!/bin/sh
# Install or update the Claude Usage plasmoid for the current user.
set -e

cd "$(dirname "$0")"
id=com.github.samsam07.claudeusage

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$id"; then
    echo "Updating $id…"
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    echo "Installing $id…"
    kpackagetool6 --type Plasma/Applet --install package
fi

# The widget list and the system tray settings look the icon up by name, and a
# package's own files are not on the icon path.
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$icons"
cp package/contents/icons/claude.svg "$icons/$id.svg"

cat <<'EOT'

Installed. To put it with the network and volume icons:
    right-click the system tray's arrow -> Configure System Tray… -> Entries
    -> "Claude Usage" -> Always shown
Or add it on its own: right-click the panel -> Add or Manage Widgets -> "Claude Usage".

If the widget is already showing, reload the shell to pick up changes:
    kquitapp6 plasmashell && (kstart plasmashell >/dev/null 2>&1 &)
EOT
