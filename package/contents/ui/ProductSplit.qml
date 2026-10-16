/*
 * This week's usage by product as one bar split into shares, with a legend.
 * Products with no share are named together on one line.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/usage.js" as Usage

ColumnLayout {
    id: products

    property var breakdown: null

    readonly property var split: Usage.productSplit(breakdown)
    readonly property real total: split.shares.reduce((sum, share) => sum + share.percent, 0)
    // The accent first, then steps away from it, so neighbours stay apart. The
    // bars are shares, not limits, so they keep clear of orange, yellow and red.
    readonly property var colors: [
        Kirigami.Theme.highlightColor,
        Qt.darker(Kirigami.Theme.highlightColor, 2.1),
        Qt.lighter(Kirigami.Theme.highlightColor, 1.5),
        Kirigami.Theme.disabledTextColor
    ]
    readonly property real gap: 2

    function colorAt(index) {
        return colors[index % colors.length];
    }

    spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("This week by product")
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Item {
        id: bar
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.smallSpacing * 2

        readonly property real room: width - products.gap * Math.max(0, products.split.shares.length - 1)

        Rectangle {
            anchors.fill: parent
            visible: products.split.shares.length === 0
            radius: height / 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.15)
        }

        Row {
            anchors.fill: parent
            spacing: products.gap

            Repeater {
                model: products.split.shares

                Rectangle {
                    required property var modelData
                    required property int index
                    height: bar.height
                    // Never narrower than its own rounded ends, so 1% still shows.
                    width: Math.max(height, bar.room * modelData.percent / products.total)
                    radius: height / 2
                    color: products.colorAt(index)
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing * 1.5

        Repeater {
            model: products.split.shares

            Row {
                id: entry
                required property var modelData
                required property int index
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.25)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: 2
                    color: products.colorAt(entry.index)
                }

                PlasmaComponents3.Label {
                    textFormat: Text.StyledText
                    text: i18nc("product, then its share", "%1 <b>%2</b>", entry.modelData.name,
                                Usage.percentText(entry.modelData.percent))
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

        PlasmaComponents3.Label {
            visible: products.split.unused.length > 0
            text: i18nc("products with no share of the week", "%1 0%",
                        products.split.unused.join(i18nc("separates product names", ", ")))
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
