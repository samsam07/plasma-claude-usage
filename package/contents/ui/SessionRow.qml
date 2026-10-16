/*
 * One running Claude Code session on one line: a dot when idle or the spark
 * when busy, its name, and how it is doing.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

RowLayout {
    id: session

    property string name
    property string status
    // How long a busy session has been running; empty for none.
    property string runningText
    // Claude orange for the theme in use.
    required property color busyColor
    // Off while the popup is closed, so a hidden row does not keep drawing.
    property bool animate: true

    readonly property bool busy: status === "busy"
    readonly property real indicatorWidth: rowSpinner.size

    spacing: Kirigami.Units.largeSpacing

    Item {
        implicitWidth: session.indicatorWidth
        implicitHeight: nameLabel.implicitHeight

        Rectangle {
            anchors.centerIn: parent
            visible: !session.busy
            width: Kirigami.Units.smallSpacing * 2
            height: width
            radius: width / 2
            color: Kirigami.Theme.disabledTextColor
        }

        ClaudeSpinner {
            id: rowSpinner
            anchors.centerIn: parent
            visible: session.busy
            running: session.busy && session.animate
            color: session.busyColor
            size: Math.round(nameLabel.implicitHeight * 0.75)
        }
    }

    PlasmaComponents3.Label {
        id: nameLabel
        Layout.fillWidth: true
        text: session.name !== "" ? session.name : i18n("Claude Code session")
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // Only the states Claude Code is known to write; anything else is an
    // internal word that would show untranslated, so it is left out.
    PlasmaComponents3.Label {
        visible: text !== ""
        text: {
            switch (session.status) {
            case "busy":
                return session.runningText !== ""
                    ? i18nc("a Claude Code session is working, then for how long", "Busy · %1", session.runningText)
                    : i18nc("a Claude Code session is working", "Busy");
            case "idle":
                return i18nc("a Claude Code session is waiting", "Idle");
            default:
                return "";
            }
        }
        font: Kirigami.Theme.smallFont
        color: session.busy ? session.busyColor : Kirigami.Theme.disabledTextColor
    }
}
