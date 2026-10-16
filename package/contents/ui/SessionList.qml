/*
 * The running Claude Code sessions, working ones first. The list takes the
 * room its column has spare and shows as many as fit; the rest are counted on
 * a last line. With no room spare it still shows up to three.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

import "../code/usage.js" as Usage

ColumnLayout {
    id: list

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var sessions: applet.recentSessions
    readonly property bool busyOnly: Plasmoid.configuration.sessionsBusyOnly
    readonly property color busyColor: applet.colorFor("normal", Kirigami.Theme.backgroundColor)

    readonly property real rowHeight: metrics.height
    readonly property real rowSpacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
    // How many rows the room given fits. The room depends only on how many
    // sessions there are, never on how many are shown, so this cannot loop.
    readonly property int capacity: Math.max(1, Math.floor((rows.height + rowSpacing) / (rowHeight + rowSpacing)))
    readonly property int shown: sessions.length <= capacity ? sessions.length : capacity - 1
    readonly property var hidden: sessions.slice(shown)

    spacing: rowSpacing

    TextMetrics {
        id: metrics
        font: Kirigami.Theme.defaultFont
        text: "Mg"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Claude Code sessions")
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: list.sessions.length === 0
        text: list.busyOnly ? i18n("None working") : i18n("No Claude Code sessions open")
        color: Kirigami.Theme.disabledTextColor
    }

    Item {
        id: rows
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: list.sessions.length > 0
        Layout.minimumHeight: Math.min(list.sessions.length, 3) * (list.rowHeight + list.rowSpacing) - list.rowSpacing
        implicitHeight: Layout.minimumHeight

        Column {
            width: parent.width
            spacing: list.rowSpacing

            Repeater {
                model: list.sessions.slice(0, list.shown)

                delegate: SessionRow {
                    required property var modelData
                    width: parent.width
                    height: list.rowHeight
                    name: modelData.name
                    status: modelData.status
                    busyColor: list.busyColor
                    animate: list.applet.popupShown
                    runningText: modelData.startedAt > 0
                        ? Usage.formatDuration(list.applet.now - modelData.startedAt, list.applet.durationUnits)
                        : ""
                }
            }

            PlasmaComponents3.Label {
                visible: list.hidden.length > 0
                width: parent.width
                height: list.rowHeight
                verticalAlignment: Text.AlignVCenter
                leftPadding: Math.round(metrics.height * 0.75) + Kirigami.Units.largeSpacing
                text: list.hidden.every(session => session.status !== "busy")
                    ? i18np("+%1 idle session", "+%1 idle sessions", list.hidden.length)
                    : i18np("+%1 more session", "+%1 more sessions", list.hidden.length)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }
}
