/*
 * One limit in the popup: its name and percentage, a bar with a tick for how
 * much of its window has gone, and beneath, its pace and when it resets.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: limit

    property string title
    property string valueText
    property string subtitle
    // 0 to 1, or negative for no bar at all.
    property real value: 0
    property color barColor: Kirigami.Theme.highlightColor
    // How much of the window has gone, 0 to 1, or negative for no tick.
    property real marker: -1
    property string note
    property color noteColor: Kirigami.Theme.disabledTextColor

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: limit.title
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaComponents3.Label {
            text: limit.valueText
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: limit.value >= 0
        implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.15)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Never narrower than its own rounded ends, so 1% still shows.
            width: limit.value > 0 ? Math.max(height, parent.width * Math.min(1, limit.value)) : 0
            radius: parent.radius
            color: limit.barColor
        }

        Rectangle {
            visible: limit.marker >= 0
            x: Math.round(parent.width * Math.min(1, limit.marker)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height * 2
            radius: 1
            color: Kirigami.Theme.textColor
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: limit.note !== "" || limit.subtitle !== ""
        spacing: Kirigami.Units.smallSpacing * 1.5

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: limit.note
            font: Kirigami.Theme.smallFont
            color: limit.noteColor
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaComponents3.Label {
            // On its own, it starts on the left like any other line.
            Layout.fillWidth: limit.note === ""
            visible: text !== ""
            text: limit.subtitle
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
