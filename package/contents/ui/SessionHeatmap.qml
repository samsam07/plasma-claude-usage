/*
 * When Claude gets used: the last seven days, one row each, today last, and
 * a cell per hour coloured by how much of the session limit went in it. Point
 * at a cell, or tab in and use the arrow keys, to read it out.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/usage.js" as Usage

ColumnLayout {
    id: heat

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var map: applet.heatmap
    readonly property color hot: applet.colorFor("normal", Kirigami.Theme.backgroundColor)
    readonly property real cellHeight: Math.round(Kirigami.Units.gridUnit * 0.6)
    readonly property real gap: 2

    // The busiest session the grid can show: hours are only recorded from
    // hoursSince on, and an older session would have no cells to match.
    readonly property var busiest: {
        var since = applet.sessionHistory.hoursSince;
        var best = null;
        applet.trend.bars.forEach(bar => {
            if (since > 0 && bar.end > since && (!best || bar.peak > best.peak)) {
                best = bar;
            }
        });
        return best;
    }

    // The cell under the pointer or the keyboard, as row * 24 + hour; -1 for none.
    property int selected: -1
    readonly property var selectedCell: selected >= 0 ? map.rows[Math.floor(selected / 24)].cells[selected % 24] : null

    function textColor(alpha) {
        return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, alpha);
    }

    function cellColor(cell) {
        if (cell.used > 0) {
            return Qt.rgba(hot.r, hot.g, hot.b, 0.2 + 0.8 * cell.ratio);
        }
        // Before recording began nothing is known, which is not the same as
        // nothing used.
        return textColor(cell.known ? 0.12 : 0.05);
    }

    function usedText(used) {
        if (used <= 0) {
            return Usage.percentText(0);
        }
        return used < 1 ? i18nc("less than one percent", "<1%") : Math.round(used) + "%";
    }

    function readoutFor(cell) {
        var start = new Date(cell.start);
        var end = new Date(cell.start + 3600000);
        return i18nc("day and hour, then the share of the session limit used in it", "%1, %2–%3 · <b>%4</b> of the session limit",
                     Qt.locale().toString(start, "ddd d MMM"),
                     Qt.formatTime(start, Qt.locale(), Locale.ShortFormat),
                     Qt.formatTime(end, Qt.locale(), Locale.ShortFormat),
                     usedText(cell.used));
    }

    spacing: Kirigami.Units.smallSpacing

    activeFocusOnTab: map.max > 0
    Accessible.role: Accessible.Chart
    Accessible.name: i18n("When you use Claude, last 7 days")
    Accessible.description: readout.text.replace(/<[^>]+>/g, "")

    onActiveFocusChanged: selected = activeFocus ? 6 * 24 + new Date(applet.now).getHours() : -1
    Keys.onLeftPressed: selected = selected <= 0 ? 7 * 24 - 1 : selected - 1
    Keys.onRightPressed: selected = selected >= 7 * 24 - 1 ? 0 : selected + 1
    Keys.onUpPressed: selected = selected < 24 ? selected + 6 * 24 : selected - 24
    Keys.onDownPressed: selected = selected >= 6 * 24 ? selected - 6 * 24 : selected + 24

    TextMetrics {
        id: dayMetrics
        font: Kirigami.Theme.smallFont
        text: "Wed"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("When you use Claude, last 7 days")
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

        Column {
            id: dayColumn
            spacing: heat.gap

            Repeater {
                model: heat.map.rows

                PlasmaComponents3.Label {
                    required property var modelData
                    required property int index
                    width: Math.ceil(dayMetrics.width)
                    height: heat.cellHeight
                    verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().toString(new Date(modelData.start), "ddd")
                    font: Kirigami.Theme.smallFont
                    color: index === 6 ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                }
            }
        }

        Item {
            id: grid
            Layout.fillWidth: true
            implicitHeight: 7 * heat.cellHeight + 6 * heat.gap

            readonly property real cellWidth: (width - 23 * heat.gap) / 24

            Repeater {
                model: heat.map.rows

                Item {
                    id: dayRow
                    required property var modelData
                    required property int index
                    y: index * (heat.cellHeight + heat.gap)
                    width: grid.width
                    height: heat.cellHeight

                    Repeater {
                        model: dayRow.modelData.cells

                        Rectangle {
                            required property var modelData
                            required property int index
                            x: index * (grid.cellWidth + heat.gap)
                            width: grid.cellWidth
                            height: heat.cellHeight
                            radius: 2
                            color: heat.cellColor(modelData)
                            border.width: heat.selected === dayRow.index * 24 + index ? 1 : 0
                            border.color: Kirigami.Theme.textColor
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                visible: heat.map.max <= 0
                text: i18n("No usage recorded yet")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: mouse => {
                    var hour = Math.floor(mouse.x / (grid.cellWidth + heat.gap));
                    var day = Math.floor(mouse.y / (heat.cellHeight + heat.gap));
                    heat.selected = hour >= 0 && hour < 24 && day >= 0 && day < 7 ? day * 24 + hour : -1;
                }
                onExited: {
                    if (!heat.activeFocus) {
                        heat.selected = -1;
                    }
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.leftMargin: dayColumn.width + Math.round(Kirigami.Units.smallSpacing * 1.5)
        implicitHeight: hourMetrics.height

        TextMetrics {
            id: hourMetrics
            font: Kirigami.Theme.smallFont
            text: "00"
        }

        Repeater {
            model: [0, 6, 12, 18]

            PlasmaComponents3.Label {
                required property int modelData
                x: modelData === 0 ? 0 : (modelData / 24) * parent.width - width / 2
                text: String(modelData).padStart(2, "0")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

        PlasmaComponents3.Label {
            id: readout
            Layout.fillWidth: true
            textFormat: Text.StyledText
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            text: {
                if (heat.selectedCell) {
                    return heat.readoutFor(heat.selectedCell);
                }
                var busiest = heat.busiest;
                if (busiest) {
                    return i18nc("the session window with the highest usage, then its peak", "Busiest: <b>%1</b>, %2",
                                 heat.applet.shortWindowText(busiest), Usage.percentText(busiest.peak));
                }
                return "";
            }
        }

        PlasmaComponents3.Label {
            text: i18nc("start of the heatmap's colour scale", "Less")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        Repeater {
            model: [0, 0.35, 0.65, 1]

            Rectangle {
                required property real modelData
                implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.55)
                implicitHeight: implicitWidth
                radius: 2
                color: modelData > 0 ? Qt.rgba(heat.hot.r, heat.hot.g, heat.hot.b, modelData) : heat.textColor(0.12)
            }
        }

        PlasmaComponents3.Label {
            text: i18nc("end of the heatmap's colour scale", "More")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
