/*
 * One product's share of the week's usage: name, bar, percentage on one line.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/usage.js" as Usage

RowLayout {
    id: product

    property string name
    property real percent: 0

    spacing: Kirigami.Units.largeSpacing

    TextMetrics {
        id: valueMetrics
        font: Kirigami.Theme.defaultFont
        text: "100%"
    }

    PlasmaComponents3.Label {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        text: product.name
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.15)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: product.percent > 0 ? Math.max(height, parent.width * Math.min(1, product.percent / 100)) : 0
            radius: parent.radius
            // A share, not a limit, so it stays out of the orange/yellow/red
            // the limits use to mean something.
            color: Kirigami.Theme.highlightColor
        }
    }

    PlasmaComponents3.Label {
        Layout.preferredWidth: valueMetrics.width
        horizontalAlignment: Text.AlignRight
        text: Usage.percentText(product.percent)
        font.features: ({ "tnum": 1 })
    }
}
