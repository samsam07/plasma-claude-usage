/*
 * Session usage over the last seven days: one column per five-hour window,
 * placed at the time it ran and as tall as the highest percentage it reached.
 * Point at a column, or tab in and use the arrow keys, to read it out.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/usage.js" as Usage

ColumnLayout {
    id: chart

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var trend: applet.trend
    readonly property var bars: trend.bars

    // The column under the pointer or the keyboard; -1 for none.
    property int selected: -1
    readonly property var selectedBar: selected >= 0 && selected < bars.length ? bars[selected] : null

    readonly property color gridColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.12)
    readonly property string strongColor: Kirigami.Theme.textColor.toString()

    spacing: Kirigami.Units.smallSpacing

    activeFocusOnTab: bars.length > 0
    Accessible.role: Accessible.Chart
    Accessible.name: i18n("Session usage, last 7 days")
    Accessible.description: readout.text.replace(/<[^>]+>/g, "")

    onActiveFocusChanged: selected = activeFocus && bars.length > 0 ? bars.length - 1 : -1
    onBarsChanged: selected = -1
    Keys.onLeftPressed: selected = selected <= 0 ? bars.length - 1 : selected - 1
    Keys.onRightPressed: selected = selected >= bars.length - 1 ? 0 : selected + 1

    function readoutFor(bar) {
        var text = i18nc("percentage, then when", "<b><font color=\"%1\">%2</font></b> · %3",
                         strongColor, Usage.percentText(bar.peak), applet.sessionWindowText(bar));
        return bar.current ? i18nc("a session still running", "%1 (in progress)", text) : text;
    }

    TextMetrics {
        id: tickMetrics
        font: Kirigami.Theme.smallFont
        text: "100%"
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("Session usage, last 7 days")
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ----------------------------------------------------------- y axis

        Item {
            Layout.preferredWidth: tickMetrics.width
            Layout.fillHeight: true

            Repeater {
                model: [100, 50]

                PlasmaComponents3.Label {
                    required property int modelData
                    anchors.right: parent.right
                    y: plot.yFor(modelData) - height / 2
                    text: Usage.percentText(modelData)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // ---------------------------------------------------------- plot

            Item {
                id: plot
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 4

                // Room above the 100% line for half of its tick label.
                readonly property real plotTop: tickMetrics.height / 2
                readonly property real plotHeight: height - plotTop
                readonly property real span: chart.trend.to - chart.trend.from

                function xFor(ms) {
                    return (ms - chart.trend.from) / span * width;
                }

                function yFor(percent) {
                    return plotTop + plotHeight * (1 - percent / 100);
                }

                // The column nearest the pointer, if the pointer is close to
                // one — a hit area wider than the thin columns themselves.
                function barAt(x) {
                    var best = -1;
                    var bestDistance = Kirigami.Units.gridUnit;
                    for (var i = 0; i < chart.bars.length; i++) {
                        var bar = chart.bars[i];
                        var center = (xFor(bar.left) + xFor(bar.right)) / 2;
                        var distance = Math.abs(x - center) - (xFor(bar.right) - xFor(bar.left)) / 2;
                        if (distance < bestDistance) {
                            best = i;
                            bestDistance = distance;
                        }
                    }
                    return best;
                }

                // Shade the stretch before recording began: an empty day there
                // means nothing is known, not that nothing was used.
                Rectangle {
                    readonly property double since: chart.applet.sessionHistory.since
                    visible: since > chart.trend.from
                    x: 0
                    y: plot.plotTop
                    width: Math.min(plot.width, plot.xFor(since))
                    height: plot.plotHeight
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.05)
                }

                // Day boundaries.
                Repeater {
                    model: chart.trend.days.slice(1, chart.trend.days.length - 1)

                    Rectangle {
                        required property double modelData
                        x: Math.round(plot.xFor(modelData))
                        y: plot.plotTop
                        width: 1
                        height: plot.plotHeight
                        color: chart.gridColor
                    }
                }

                Repeater {
                    model: [100, 50, 0]

                    Rectangle {
                        required property int modelData
                        x: 0
                        y: Math.round(plot.yFor(modelData))
                        width: plot.width
                        height: 1
                        // The baseline a step stronger than the gridlines.
                        color: modelData === 0
                            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.3)
                            : chart.gridColor
                    }
                }

                Repeater {
                    model: chart.bars

                    Rectangle {
                        id: column
                        required property var modelData
                        required property int index

                        readonly property real startX: plot.xFor(modelData.left)
                        readonly property real endX: plot.xFor(modelData.right)
                        readonly property color levelColor: chart.applet.colorFor(modelData.level, Kirigami.Theme.backgroundColor)
                        readonly property real corner: Math.min(4, width / 2)

                        // A 2px gap keeps back-to-back sessions apart.
                        x: startX + 1
                        width: Math.max(2, endX - startX - 2)
                        height: Math.max(2, modelData.ratio * plot.plotHeight)
                        y: plot.yFor(0) - height
                        radius: corner
                        color: chart.selected === index ? Qt.lighter(levelColor, 1.25) : levelColor

                        // Square where the column meets the baseline.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: Math.min(parent.height, parent.corner)
                            color: parent.color
                        }
                    }
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: chart.bars.length === 0
                    text: i18n("No sessions recorded yet")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: mouse => chart.selected = plot.barAt(mouse.x)
                    onExited: {
                        if (!chart.activeFocus) {
                            chart.selected = -1;
                        }
                    }
                }
            }

            // -------------------------------------------------------- x axis

            Item {
                Layout.fillWidth: true
                implicitHeight: tickMetrics.height

                Repeater {
                    model: chart.trend.days.slice(0, chart.trend.days.length - 1)

                    PlasmaComponents3.Label {
                        required property double modelData
                        required property int index
                        readonly property double dayEnd: chart.trend.days[index + 1]
                        readonly property bool today: index === chart.trend.days.length - 2

                        x: (plot.xFor(modelData) + plot.xFor(dayEnd) - width) / 2
                        text: Qt.locale().toString(new Date(modelData), "ddd")
                        font: Kirigami.Theme.smallFont
                        color: today ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }
    }

    PlasmaComponents3.Label {
        id: readout
        Layout.fillWidth: true
        visible: text !== ""
        textFormat: Text.StyledText
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        elide: Text.ElideRight
        text: {
            if (chart.selectedBar) {
                return chart.readoutFor(chart.selectedBar);
            }
            if (chart.trend.busiest) {
                return i18nc("the session with the highest usage", "Busiest: %1", chart.readoutFor(chart.trend.busiest));
            }
            return "";
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: chart.applet.sessionHistory.since > 0
        text: i18n("Recorded by this widget since %1",
                   Qt.locale().toString(new Date(chart.applet.sessionHistory.since), "ddd d MMM"))
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
    }
}
