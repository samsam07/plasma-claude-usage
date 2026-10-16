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

    // While a Claude Code session works, the icon animates in the style
    // chosen in the settings: Claude Code's spark frames or the petal wave in
    // place of the mark, the mark itself turning, or a light lapping the ring.
    readonly property bool working: applet.anyBusy && Plasmoid.configuration.animateLogo
    readonly property string animation: ["frames", "wave", "spin", "orbit"].indexOf(Plasmoid.configuration.panelAnimation) >= 0
        ? Plasmoid.configuration.panelAnimation
        : "frames"
    readonly property bool sparking: working && (animation === "wave" || animation === "frames")
    readonly property bool turning: working && animation === "spin"

    // About half the ring, but odd when the ring is odd and even when it is
    // even: otherwise centring it lands on half a pixel, which is rounded,
    // and the mark sits half a pixel up and to the left.
    readonly property int markSize: {
        var ring = Math.round(Math.min(width, height));
        var size = Math.round(ring * 0.52);
        return (ring - size) % 2 === 0 ? size : size + 1;
    }

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
        orbiting: compact.working && compact.animation === "orbit"

        Kirigami.Icon {
            id: logo
            anchors.centerIn: parent
            width: compact.markSize
            height: width
            source: Qt.resolvedUrl("../icons/claude.svg")
            opacity: compact.applet.hasData ? 1 : 0.6
            visible: !spinner.visible
            smooth: true

            // The turning mark: a turn every 3.2 s, breathing between 86% and
            // 100% every 1.6 s. Animators, so they run on the render thread.
            RotationAnimator {
                target: logo
                from: 0
                to: 360
                duration: 3200
                loops: Animation.Infinite
                running: compact.turning
                onRunningChanged: {
                    if (!running) {
                        logo.rotation = 0;
                    }
                }
            }

            SequentialAnimation {
                loops: Animation.Infinite
                running: compact.turning
                onRunningChanged: {
                    if (!running) {
                        logo.scale = 1;
                    }
                }

                ScaleAnimator { target: logo; from: 1; to: 0.86; duration: 800; easing.type: Easing.InOutSine }
                ScaleAnimator { target: logo; from: 0.86; to: 1; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        // The spark frames or the petal wave, in place of the mark — the same
        // the popup shows beside each working session.
        ClaudeSpinner {
            id: spinner
            anchors.centerIn: parent
            width: logo.width
            height: logo.height
            size: logo.width
            color: compact.applet.colorFor("normal", Kirigami.Theme.backgroundColor)
            style: compact.animation === "wave" ? "wave" : "frames"
            visible: compact.sparking
            running: visible
        }
    }
}
