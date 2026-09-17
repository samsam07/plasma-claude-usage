/*
 * The popup: the ring's limit large, every other limit as a bar beneath it,
 * usage credits when they are switched on, this week's split by product, and
 * the seven-day session trend.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/usage.js" as Usage

PlasmaExtras.Representation {
    id: full

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var hero: applet.ring
    readonly property var others: applet.rows.filter(row => !hero || row.key !== hero.key)
    readonly property color heroColor: hero
        ? applet.colorFor(hero.level, Kirigami.Theme.backgroundColor)
        : Kirigami.Theme.disabledTextColor

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    // Tall enough for everything, up to a point; past that the body scrolls.
    Layout.preferredHeight: Math.max(Layout.minimumHeight, Math.min(Kirigami.Units.gridUnit * 38,
        body.implicitHeight + Kirigami.Units.largeSpacing * 2
        + (header ? header.implicitHeight : 0) + (footer ? footer.implicitHeight : 0)))

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

    // Nothing cached and nothing fetched — say why, and offer a way forward.
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 3
        visible: !full.applet.hasData && !full.applet.loading
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
        helpfulAction: Kirigami.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: full.applet.refresh()
        }
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        visible: running
        running: full.applet.loading && !full.applet.hasData
    }

    PlasmaComponents3.ScrollView {
        id: scroll
        anchors.fill: parent
        visible: full.applet.hasData
        contentWidth: availableWidth
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        Item {
            implicitWidth: scroll.availableWidth
            implicitHeight: body.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: body
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Kirigami.Units.largeSpacing
                anchors.leftMargin: Kirigami.Units.largeSpacing * 2
                anchors.rightMargin: Kirigami.Units.largeSpacing * 2
                spacing: Kirigami.Units.largeSpacing

                // ---------------------------------------------------- hero

                RowLayout {
                    Layout.fillWidth: true
                    visible: full.hero !== null
                    spacing: Kirigami.Units.largeSpacing * 2

                    UsageRing {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                        value: full.hero ? full.hero.ratio : 0
                        color: full.heroColor
                        thickness: Kirigami.Units.gridUnit * 0.5

                        PlasmaExtras.Heading {
                            anchors.centerIn: parent
                            level: 2
                            text: full.hero ? Usage.percentText(full.hero.percent) : ""
                            color: full.heroColor
                            font.weight: Font.Bold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaExtras.Heading {
                            Layout.fillWidth: true
                            level: 4
                            text: full.applet.titleFor(full.hero)
                            wrapMode: Text.Wrap
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: full.applet.resetText(full.hero)
                            color: Kirigami.Theme.disabledTextColor
                            wrapMode: Text.Wrap
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            color: full.heroColor
                            wrapMode: Text.Wrap
                            text: {
                                if (!full.hero) {
                                    return "";
                                }
                                if (full.hero.percent >= 100) {
                                    return i18n("Limit reached");
                                }
                                switch (full.hero.level) {
                                case "critical":
                                    return i18n("Almost at the limit");
                                case "warning":
                                    return i18n("Approaching the limit");
                                default:
                                    return "";
                                }
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: full.others.length > 0 || full.applet.credits !== null
                }

                // ---------------------------------------------------- others

                Repeater {
                    model: full.others

                    delegate: LimitRow {
                        required property var modelData
                        Layout.fillWidth: true
                        title: full.applet.titleFor(modelData)
                        valueText: Usage.percentText(modelData.percent)
                        subtitle: full.applet.resetText(modelData)
                        value: modelData.ratio
                        barColor: full.applet.colorFor(modelData.level, Kirigami.Theme.backgroundColor)
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

                // ------------------------------------------------------ products

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: full.applet.breakdown !== null
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: full.applet.breakdown !== null
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("This week's usage by product")
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Repeater {
                        model: full.applet.breakdown || []

                        delegate: ProductRow {
                            required property var modelData
                            Layout.fillWidth: true
                            name: modelData.name
                            percent: modelData.percent
                        }
                    }
                }

                // --------------------------------------------------------- trend

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                SessionTrend {
                    Layout.fillWidth: true
                    applet: full.applet
                }

                // Figures are shown, but they are not current — say why.
                RowLayout {
                    Layout.fillWidth: true
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
                icon.name: "internet-web-browser"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Open Usage on claude.ai")
                onClicked: Qt.openUrlExternally(full.applet.usagePage)

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
