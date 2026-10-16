import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_ringLimit
    property alias cfg_warningPercent: warningField.value
    property alias cfg_criticalPercent: criticalField.value
    property alias cfg_refreshMinutes: refreshField.value
    property alias cfg_credentialsPath: pathField.text
    property alias cfg_showMainLimit: showMainLimitBox.checked
    property alias cfg_showOtherLimits: showOtherLimitsBox.checked
    property alias cfg_showProducts: showProductsBox.checked
    property alias cfg_showSessions: showSessionsBox.checked
    property alias cfg_showTrend: showTrendBox.checked
    property alias cfg_showSettingsButton: showSettingsButtonBox.checked
    property alias cfg_animateLogo: animateLogoBox.checked
    property alias cfg_sessionsBusyOnly: busyOnlyBox.checked
    property string cfg_historyChart

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.ComboBox {
            id: ringBox
            Kirigami.FormData.label: i18n("Ring shows:")

            textRole: "label"
            valueRole: "value"
            model: [
                { value: "session", label: i18n("Current session") },
                { value: "weekly",  label: i18n("Current week (all models)") },
                { value: "closest", label: i18n("Whichever is closest to its limit") }
            ]

            onActivated: page.cfg_ringLimit = currentValue

            Component.onCompleted: {
                currentIndex = indexOfValue(page.cfg_ringLimit);
                if (currentIndex < 0) {
                    currentIndex = 0;
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: animateLogoBox
            Kirigami.FormData.label: i18n("Panel icon:")
            text: i18n("Animate while a Claude Code session is working")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showMainLimitBox
            Kirigami.FormData.label: i18n("Popup shows:")
            text: i18n("Current session")
        }

        QQC2.CheckBox {
            id: showOtherLimitsBox
            text: i18n("This week's limits and usage credits")
        }

        QQC2.CheckBox {
            id: showProductsBox
            text: i18n("This week by product")
        }

        QQC2.CheckBox {
            id: showSessionsBox
            text: i18n("Claude Code sessions")
        }

        QQC2.CheckBox {
            id: showTrendBox
            text: i18n("The last seven days")
        }

        QQC2.CheckBox {
            id: showSettingsButtonBox
            text: i18n("Settings button")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: busyOnlyBox
            Kirigami.FormData.label: i18n("Sessions:")
            enabled: showSessionsBox.checked
            text: i18n("Only those working on a task")
        }

        QQC2.ComboBox {
            id: historyBox
            Kirigami.FormData.label: i18n("Last seven days as:")
            enabled: showTrendBox.checked

            textRole: "label"
            valueRole: "value"
            model: [
                { value: "heatmap", label: i18n("When you use Claude, by the hour") },
                { value: "bars", label: i18n("Each session's peak") }
            ]

            onActivated: page.cfg_historyChart = currentValue

            Component.onCompleted: {
                currentIndex = indexOfValue(page.cfg_historyChart);
                if (currentIndex < 0) {
                    currentIndex = 0;
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: warningField
            Kirigami.FormData.label: i18n("Turn yellow at:")
            from: 1
            to: 100
            textFromValue: (value, locale) => i18nc("percentage", "%1%", value)
            valueFromText: (text, locale) => {
                var n = parseInt(text, 10);
                return isNaN(n) ? warningField.value : n;
            }
        }

        QQC2.SpinBox {
            id: criticalField
            Kirigami.FormData.label: i18n("Turn red at:")
            from: warningField.value
            to: 100
            textFromValue: (value, locale) => i18nc("percentage", "%1%", value)
            valueFromText: (text, locale) => {
                var n = parseInt(text, 10);
                return isNaN(n) ? criticalField.value : n;
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18n("Below these the ring is Claude orange. If Claude itself flags a limit as nearly used up, the colour follows that too, even under these percentages.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: refreshField
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 2
            to: 60
            editable: true
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => {
                var n = parseInt(text, 10);
                return isNaN(n) ? refreshField.value : n;
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18n("Claude limits how often usage can be read, and Claude Code's own /usage counts against the same limit.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }

        QQC2.TextField {
            id: pathField
            Kirigami.FormData.label: i18n("Credentials file:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18n("Where Claude Code keeps its sign-in. The widget only reads this file — it never renews or changes the sign-in. Change it only if you run Claude Code with <b>CLAUDE_CONFIG_DIR</b>.")
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
        }
    }
}
