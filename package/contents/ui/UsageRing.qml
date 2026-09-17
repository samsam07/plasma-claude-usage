/*
 * A track with an arc drawn clockwise from twelve o'clock, round-capped.
 * Children are laid over the centre — the Claude mark in the panel, the
 * percentage in the popup.
 */

import QtQuick
import QtQuick.Shapes

import org.kde.kirigami as Kirigami

Item {
    id: ring

    // 0 to 1; anything past a full circle is drawn as one.
    property real value: 0
    property color color: Kirigami.Theme.highlightColor
    property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                       Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.2)
    property real thickness: Math.max(1.5, diameter * 0.1)

    readonly property real diameter: Math.min(width, height)
    readonly property real radius: Math.max(0, (diameter - thickness) / 2)

    implicitWidth: Kirigami.Units.iconSizes.medium
    implicitHeight: implicitWidth

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            // A zero-length arc with round caps would still paint a dot.
            strokeColor: ring.value > 0 ? ring.color : "transparent"
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, ring.value))
            }
        }
    }
}
