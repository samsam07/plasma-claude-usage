/*
 * What sits in the panel or the system tray: the Claude mark inside a ring
 * that fills as the chosen limit is used, orange turning yellow then red.
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/usage.js" as Usage

MouseArea {
    id: compact

    // QML ids do not cross file boundaries, so the applet is handed in.
    required property var applet

    readonly property var row: applet.ring

    // Square, sized by the panel's thickness.
    Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : Kirigami.Units.iconSizes.small

    activeFocusOnTab: true
    hoverEnabled: true
    Accessible.role: Accessible.Button
    Accessible.name: applet.toolTipMainText
    Accessible.description: row
        ? i18nc("limit name: percentage used", "%1: %2", applet.titleFor(row), Usage.percentText(row.percent))
        : applet.errorText

    onClicked: applet.expanded = !applet.expanded
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            applet.expanded = !applet.expanded;
            event.accepted = true;
        }
    }

    UsageRing {
        anchors.centerIn: parent
        width: compact.width
        height: compact.height
        value: compact.row ? compact.row.ratio : 0
        color: compact.row
            ? compact.applet.colorFor(compact.row.level, Kirigami.Theme.backgroundColor)
            : "transparent"
        // Old figures stay visible but step back.
        opacity: compact.applet.stale ? 0.55 : 1

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(parent.diameter * 0.52)
            height: width
            source: Qt.resolvedUrl("../icons/claude.svg")
            opacity: compact.applet.hasData ? 1 : 0.6
        }
    }
}
