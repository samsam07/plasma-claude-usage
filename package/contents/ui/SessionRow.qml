/*
 * One running Claude Code session: a status dot, its name, and beneath it the
 * project folder and how long it has been running; busy or idle on the right.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/usage.js" as Usage

RowLayout {
    id: session

    property string name
    property string folder
    property string runningText
    property string status

    readonly property bool busy: status === "busy"
    readonly property color statusColor: busy ? Usage.COLORS.dark.normal : Kirigami.Theme.disabledTextColor

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
            running: session.busy && session.visible
            size: Math.round(nameLabel.implicitHeight * 0.75)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        PlasmaComponents3.Label {
            id: nameLabel
            Layout.fillWidth: true
            text: session.name
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: session.runningText !== ""
                ? i18nc("project folder · how long it has been running", "%1 · %2",
                        session.folder, session.runningText)
                : session.folder
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            // Keep the start of the path and the running time; drop the middle.
            elide: Text.ElideMiddle
            maximumLineCount: 1
        }
    }

    PlasmaComponents3.Label {
        Layout.alignment: Qt.AlignTop
        text: {
            switch (session.status) {
            case "busy":
                return i18nc("a Claude Code session is working", "Busy");
            case "idle":
                return i18nc("a Claude Code session is waiting", "Idle");
            default:
                return session.status;
            }
        }
        font: Kirigami.Theme.smallFont
        color: session.statusColor
    }
}
