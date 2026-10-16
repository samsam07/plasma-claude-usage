/*
 * One running Claude Code session: a status dot, its name, and beneath it the
 * project folder and how long it has been running; busy or idle on the right.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

RowLayout {
    id: session

    property string name
    property string folder
    property string runningText
    property string status
    // Claude orange for the theme in use.
    required property color busyColor
    // Off while the popup is closed, so a hidden row does not keep drawing.
    property bool animate: true

    readonly property bool busy: status === "busy"
    readonly property color statusColor: busy ? busyColor : Kirigami.Theme.disabledTextColor

    spacing: Kirigami.Units.largeSpacing

    // A dot when idle; when busy, the spark Claude Code cycles through while
    // it works.
    Item {
        Layout.alignment: Qt.AlignTop
        implicitWidth: rowSpinner.size
        implicitHeight: nameLabel.implicitHeight

        Rectangle {
            anchors.centerIn: parent
            visible: !session.busy
            width: Kirigami.Units.smallSpacing * 2
            height: width
            radius: width / 2
            color: session.statusColor
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

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        PlasmaComponents3.Label {
            id: nameLabel
            Layout.fillWidth: true
            text: session.name !== "" ? session.name : i18n("Claude Code session")
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: session.folder !== "" && session.runningText !== ""
                ? i18nc("project folder · how long it has been running", "%1 · %2",
                        session.folder, session.runningText)
                : session.folder + session.runningText
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            // Keep the start of the path and the running time; drop the middle.
            elide: Text.ElideMiddle
            maximumLineCount: 1
        }
    }

    // Only the states Claude Code is known to write; anything else is an
    // internal word that would show untranslated, so it is left out.
    PlasmaComponents3.Label {
        Layout.alignment: Qt.AlignTop
        visible: text !== ""
        text: {
            switch (session.status) {
            case "busy":
                return i18nc("a Claude Code session is working", "Busy");
            case "idle":
                return i18nc("a Claude Code session is waiting", "Idle");
            default:
                return "";
            }
        }
        font: Kirigami.Theme.smallFont
        color: session.statusColor
    }
}
