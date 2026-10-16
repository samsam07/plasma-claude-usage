/*
 * The popup. In a narrow popup, one column: the current session with its
 * chart and pace, this week's limits, the week by product, then the running
 * Claude Code sessions, which take whatever room is spare, and the seven-day
 * history at the bottom. A wide popup moves the sessions and the history into
 * a second column.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

import "../code/usage.js" as Usage

PlasmaExtras.Representation {
    id: full

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var session: applet.sessionRow
    readonly property color sessionColor: session
        ? applet.colorFor(session.level, Kirigami.Theme.backgroundColor)
        : Kirigami.Theme.disabledTextColor
    readonly property color orange: applet.colorFor("normal", Kirigami.Theme.backgroundColor)
    readonly property color warningColor: applet.colorFor("warning", Kirigami.Theme.backgroundColor)
    readonly property var pace: applet.progress ? applet.progress.pace : null
    // No session under way: nothing to chart, so the block shrinks to a small
    // ring and a line saying so.
    readonly property bool heroIdle: applet.progress === null
    readonly property color paceColor: pace && (pace.reached || pace.limitAt > 0)
        ? warningColor
        : Kirigami.Theme.disabledTextColor

    // Which sections are on screen: switched on in the settings, and with
    // something to show.
    readonly property var cfg: Plasmoid.configuration
    readonly property bool showHero: cfg.showMainLimit && session !== null
    readonly property bool showLimits: cfg.showOtherLimits && (applet.weekRows.length > 0 || applet.credits !== null)
    readonly property bool showProducts: cfg.showProducts && applet.breakdown !== null
    readonly property bool showSessions: cfg.showSessions
    readonly property bool showHistory: cfg.showTrend && applet.hasData
    readonly property bool heatmap: cfg.historyChart !== "bars"

    // Without data the sign-in message comes first. In each column a
    // separator goes above every section but the first.
    readonly property string firstLeft: !applet.hasData ? "placeholder"
        : showHero ? "hero"
        : showLimits ? "limits"
        : showProducts ? "products"
        : ""

    // Two columns once there is room for both.
    readonly property bool wide: width >= Kirigami.Units.gridUnit * 33

    readonly property real gap: Math.round(Kirigami.Units.largeSpacing * 1.25)
    readonly property real topMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real bottomMargin: Kirigami.Units.largeSpacing

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    // Tall enough for everything, up to a point; past that the body scrolls.
    readonly property real fullHeight: Math.min(Kirigami.Units.gridUnit * 42,
        body.implicitHeight + topMargin + bottomMargin + chromeHeight)
    // Plasma restores the popup's last size over the preferred one, so only the
    // minimum is sure to hold — without data it must fit the sign-in message.
    Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 14, applet.hasData ? 0 : fullHeight)
    Layout.preferredHeight: Math.max(Layout.minimumHeight, fullHeight)

    readonly property real chromeHeight: (header ? header.implicitHeight : 0) + (footer ? footer.implicitHeight : 0)

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Qt.resolvedUrl("../icons/claude.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Claude Usage")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: full.applet.plan !== "" ? i18nc("%1 is a plan name, such as Pro", "Claude %1", full.applet.plan) : ""
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    PlasmaComponents3.BusyIndicator {
        id: busy
        anchors.centerIn: parent
        visible: running
        running: full.applet.loading && !full.applet.hasData
    }

    PlasmaComponents3.ScrollView {
        id: scroll
        anchors.fill: parent
        visible: !busy.running
        contentWidth: availableWidth
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        Item {
            implicitWidth: scroll.availableWidth
            // What scrolls is the content's own height; the body still stretches
            // to the height on offer, so the sessions can take what is spare.
            implicitHeight: body.implicitHeight + full.topMargin + full.bottomMargin
            height: Math.max(implicitHeight, scroll.availableHeight)

            GridLayout {
                id: body
                anchors.fill: parent
                anchors.topMargin: full.topMargin
                anchors.bottomMargin: full.bottomMargin
                anchors.leftMargin: Kirigami.Units.largeSpacing * 2
                anchors.rightMargin: Kirigami.Units.largeSpacing * 2
                columns: full.wide ? 3 : 1
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: full.gap

                // ------------------------------------------------ left column

                ColumnLayout {
                    id: leftColumn
                    visible: full.firstLeft !== ""
                    Layout.fillWidth: true
                    // Both columns start from nothing, so they share the width evenly.
                    Layout.preferredWidth: 0
                    // A layout grows with any child that fills; only the right
                    // column takes spare height.
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignTop
                    spacing: full.gap

                    // Nothing cached and nothing fetched — say why. The footer's
                    // Refresh button is the way forward, so it is not repeated here.
                    PlasmaExtras.PlaceholderMessage {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: !full.applet.hasData
                        iconName: {
                            switch (full.applet.authState) {
                            case "missing":
                            case "expired":
                            case "denied":
                                return "dialog-password";
                            default:
                                return "network-disconnect-symbolic";
                            }
                        }
                        text: {
                            switch (full.applet.authState) {
                            case "missing":
                                return i18n("Sign in to Claude Code");
                            case "expired":
                                return i18n("Claude Code's sign-in has expired");
                            case "denied":
                                return i18n("Usage is not available to this sign-in");
                            default:
                                return i18n("No usage available");
                            }
                        }
                        explanation: {
                            switch (full.applet.authState) {
                            case "missing":
                                return i18n("This widget reads the sign-in Claude Code keeps on this computer. Run <b>claude</b> in a terminal and log in with your Claude account.");
                            case "expired":
                                return i18n("Using Claude Code renews it, and the widget picks the new one up on its next refresh.");
                            case "denied":
                                return i18n("Run <b>claude</b>, then <b>/login</b>, to sign in again.");
                            default:
                                return full.applet.errorText !== "" ? full.applet.errorText : i18n("Usage has not been loaded yet.");
                            }
                        }
                    }

                    // The current session: the ring, when it resets, how it has
                    // gone so far and where its pace leads.
                    RowLayout {
                        Layout.fillWidth: true
                        // As tall as the ring; the chart fills what the text leaves.
                        Layout.fillHeight: false
                        visible: full.showHero
                        spacing: Math.round(Kirigami.Units.largeSpacing * 1.5)

                        UsageRing {
                            readonly property real ringSize: Kirigami.Units.gridUnit * (full.heroIdle ? 3.5 : 6)
                            Layout.preferredWidth: ringSize
                            Layout.preferredHeight: ringSize
                            Layout.alignment: full.heroIdle ? Qt.AlignVCenter : Qt.AlignTop
                            value: full.session ? full.session.ratio : 0
                            color: full.sessionColor
                            thickness: Math.round(Kirigami.Units.gridUnit * (full.heroIdle ? 0.35 : 0.55))

                            PlasmaExtras.Heading {
                                anchors.centerIn: parent
                                level: full.heroIdle ? 4 : 1
                                text: full.session ? Usage.percentText(full.session.percent) : ""
                                color: full.sessionColor
                                font.weight: Font.Bold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: !full.heroIdle
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: full.applet.shortTitleFor(full.session)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                textFormat: Text.StyledText
                                text: full.heroIdle
                                    ? full.applet.sessionIdleText(full.session)
                                    : full.applet.sessionResetText(full.session, Kirigami.Theme.textColor)
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            SessionChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                visible: !full.heroIdle
                                progress: full.applet.progress
                                color: full.orange
                                paceColor: full.paceColor
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                visible: !full.heroIdle && text !== ""
                                horizontalAlignment: Text.AlignRight
                                text: full.applet.sessionPaceText(full.pace)
                                font: Kirigami.Theme.smallFont
                                color: full.paceColor
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: full.showLimits && full.firstLeft !== "limits"
                    }

                    // This week: each weekly limit, with a tick for how much of
                    // the week has gone, its pace and its reset; then credits.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: full.showLimits
                        spacing: full.gap

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: i18n("This week")
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                visible: full.applet.weekRows.length > 0
                                implicitWidth: 2
                                implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.55)
                                radius: 1
                                color: Kirigami.Theme.textColor
                            }

                            PlasmaComponents3.Label {
                                visible: full.applet.weekRows.length > 0
                                text: i18nc("legend for the tick on each weekly bar", "time elapsed")
                                font: Kirigami.Theme.smallFont
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }

                        Repeater {
                            model: full.applet.weekRows

                            delegate: LimitRow {
                                required property var modelData
                                readonly property var weekPace: Usage.weekPace(modelData, full.applet.now)

                                Layout.fillWidth: true
                                title: full.applet.shortTitleFor(modelData)
                                valueText: Usage.percentText(modelData.percent)
                                value: modelData.ratio
                                barColor: full.applet.colorFor(modelData.level, Kirigami.Theme.backgroundColor)
                                marker: weekPace ? weekPace.elapsed : -1
                                note: full.applet.weekPaceText(weekPace)
                                noteColor: weekPace && weekPace.ahead ? full.warningColor : Kirigami.Theme.disabledTextColor
                                subtitle: full.applet.weekResetText(modelData)
                            }
                        }

                        LimitRow {
                            readonly property var credits: full.applet.credits
                            readonly property bool hasPercent: credits !== null && credits.percent !== null

                            Layout.fillWidth: true
                            visible: credits !== null
                            title: i18n("Usage credits")
                            valueText: hasPercent ? Usage.percentText(credits.percent) : ""
                            value: hasPercent ? Math.min(1, credits.percent / 100) : -1
                            barColor: hasPercent
                                ? full.applet.colorFor(Usage.levelFor(credits.percent, credits.severity,
                                                                      full.applet.warningPercent, full.applet.criticalPercent),
                                                       Kirigami.Theme.backgroundColor)
                                : Kirigami.Theme.highlightColor
                            subtitle: {
                                if (credits === null || credits.used === "") {
                                    return "";
                                }
                                return credits.limit !== ""
                                    ? i18nc("money spent of a monthly limit", "%1 spent of %2", credits.used, credits.limit)
                                    : i18nc("money spent", "%1 spent", credits.used);
                            }
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: full.showProducts && full.firstLeft !== "products"
                    }

                    ProductSplit {
                        Layout.fillWidth: true
                        visible: full.showProducts
                        breakdown: full.applet.breakdown
                    }
                }

                // Between the columns when wide, between top and bottom when not.
                Kirigami.Separator {
                    Layout.fillHeight: true
                    visible: full.wide && leftColumn.visible && rightColumn.visible
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: !full.wide && leftColumn.visible && rightColumn.visible
                }

                // ----------------------------------------------- right column

                ColumnLayout {
                    id: rightColumn
                    visible: full.showSessions || full.showHistory
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 0
                    spacing: full.gap

                    SessionList {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: full.showSessions
                        applet: full.applet
                    }

                    // Keeps the history at the bottom when the sessions are hidden.
                    Item {
                        Layout.fillHeight: true
                        visible: !full.showSessions
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: full.showSessions && full.showHistory
                    }

                    SessionHeatmap {
                        Layout.fillWidth: true
                        visible: full.showHistory && full.heatmap
                        applet: full.applet
                    }

                    SessionTrend {
                        Layout.fillWidth: true
                        visible: full.showHistory && !full.heatmap
                        applet: full.applet
                    }
                }

                // Figures are shown, but they are not current — say why.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.columnSpan: full.wide ? 3 : 1
                    visible: full.applet.stale && full.applet.errorText !== ""
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "data-warning"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        Layout.alignment: Qt.AlignTop
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: full.applet.errorText
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.neutralTextColor
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                font: Kirigami.Theme.smallFont
                color: full.applet.stale
                    ? Kirigami.Theme.neutralTextColor
                    : Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
                text: {
                    if (full.applet.lastFetchText === "") {
                        return i18n("Not yet updated");
                    }
                    return full.applet.stale
                        ? i18n("Saved usage from %1", full.applet.lastFetchText)
                        : i18n("Updated %1", full.applet.lastFetchText);
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "globe-symbolic"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Open Usage on claude.ai")
                onClicked: Qt.openUrlExternally(full.applet.usagePage)

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                visible: full.cfg.showSettingsButton
                icon.name: "configure-symbolic"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Configure Claude Usage…")
                onClicked: Plasmoid.internalAction("configure").trigger()

                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PlasmaComponents3.ToolButton {
                text: i18n("Refresh")
                icon.name: "view-refresh"
                enabled: !full.applet.loading
                display: PlasmaComponents3.AbstractButton.TextBesideIcon
                onClicked: full.applet.refresh()
            }
        }
    }
}
