/*
 * The spark shown while Claude Code works, in Claude orange, in one of two
 * styles: "frames", the spark Claude Code itself steps through — · ✢ ✳ ✶ ✻ ✽
 * and back; or "wave", one spark whose eight rays swell in a wave that
 * travels round it, drawn continuously. Either keeps moving even with
 * Plasma's animations set to Instant, as Plasma's own busy indicators do: it
 * says work is under way. The widget's own setting is what turns it off.
 *
 * Drawn rather than set as text: the glyphs come from different fonts that
 * report their extents unreliably, so as text they could not be kept centred
 * and the spark hopped as it cycled. Drawn, every frame shares one centre.
 */

import QtQuick

import org.kde.kirigami as Kirigami

Canvas {
    id: spinner

    property bool running: true
    required property color color
    // Diameter of the largest frame.
    property real size: Kirigami.Units.iconSizes.small
    property string style: "frames"

    // Indexes into the shapes drawn in onPaint, there and back again.
    readonly property var frames: [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]
    property int frame: 0
    // How far round the wave has travelled, 0 to 1.
    property real phase: 0
    readonly property int waveMs: 1400

    readonly property bool animating: running && visible
    // Standing still, the dot would be all but invisible; show the full spark.
    readonly property int shape: animating ? frames[frame] : 5

    implicitWidth: size
    implicitHeight: size

    onShapeChanged: requestPaint()
    onPhaseChanged: requestPaint()
    onStyleChanged: requestPaint()
    onColorChanged: requestPaint()
    onSizeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // A spoke that is thin at the centre and swells to a round tip.
    function teardrop(ctx, angle, from, to, tipRadius, baseHalfWidth) {
        var dx = Math.sin(angle), dy = -Math.cos(angle);
        var px = -dy, py = dx;
        var tx = to * dx, ty = to * dy;
        ctx.beginPath();
        ctx.moveTo(from * dx + baseHalfWidth * px, from * dy + baseHalfWidth * py);
        ctx.lineTo(tx + tipRadius * px, ty + tipRadius * py);
        ctx.arc(tx, ty, tipRadius, angle, angle + Math.PI, true);
        ctx.lineTo(from * dx - baseHalfWidth * px, from * dy - baseHalfWidth * py);
        ctx.closePath();
        ctx.fill();
    }

    function dot(ctx, x, y, radius) {
        ctx.beginPath();
        ctx.arc(x, y, radius, 0, 2 * Math.PI);
        ctx.fill();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var r = Math.min(width, height) / 2;
        if (r <= 0) {
            return;
        }
        ctx.translate(width / 2, height / 2);
        ctx.fillStyle = color;
        ctx.strokeStyle = color;
        var i;

        if (style === "wave") {
            // Each ray's length follows a sine wave offset by its angle, so a
            // swell travels clockwise and the outline never jumps.
            var turn = phase * 2 * Math.PI;
            dot(ctx, 0, 0, r * 0.13);
            for (i = 0; i < 8; i++) {
                var angle = i * Math.PI / 4;
                var swell = 0.5 + 0.5 * Math.sin(turn - angle);
                teardrop(ctx, angle, r * 0.15, r * (0.42 + 0.42 * swell), r * 0.12, r * 0.035);
            }
            return;
        }

        switch (shape) {
        case 0: // ·
            dot(ctx, 0, 0, r * 0.14);
            break;
        case 1: // ✢ four teardrops
            for (i = 0; i < 4; i++) {
                teardrop(ctx, i * Math.PI / 2, 0, r * 0.68, r * 0.3, r * 0.06);
            }
            break;
        case 2: // ✳ eight thin spokes
            ctx.lineWidth = r * 0.11;
            ctx.lineCap = "round";
            ctx.beginPath();
            for (i = 0; i < 8; i++) {
                var a = i * Math.PI / 4;
                ctx.moveTo(0, 0);
                ctx.lineTo(Math.sin(a) * r * 0.88, -Math.cos(a) * r * 0.88);
            }
            ctx.stroke();
            break;
        case 3: // ✶ six-pointed star
            ctx.beginPath();
            for (i = 0; i < 12; i++) {
                var radius = i % 2 === 0 ? r * 0.95 : r * 0.3;
                var b = i * Math.PI / 6;
                ctx.lineTo(Math.sin(b) * radius, -Math.cos(b) * radius);
            }
            ctx.closePath();
            ctx.fill();
            break;
        case 4: // ✻ six teardrops around a dot
            dot(ctx, 0, 0, r * 0.17);
            for (i = 0; i < 6; i++) {
                teardrop(ctx, i * Math.PI / 3, r * 0.34, r * 0.74, r * 0.17, r * 0.04);
            }
            break;
        case 5: // ✽ six heavy teardrops
            for (i = 0; i < 6; i++) {
                teardrop(ctx, i * Math.PI / 3, 0, r * 0.78, r * 0.15, r * 0.04);
            }
            break;
        }
    }

    Timer {
        // A full cycle in 3.75 s: calm enough to sit in the panel all day.
        interval: 375
        repeat: true
        running: spinner.animating && spinner.style === "frames"
        onTriggered: spinner.frame = (spinner.frame + 1) % spinner.frames.length
    }

    // About 30 frames a second: smooth at panel size, light on the CPU. The
    // wave goes by the clock, so a late tick never slows it down.
    Timer {
        property double started: 0
        interval: 33
        repeat: true
        running: spinner.animating && spinner.style === "wave"
        onRunningChanged: started = Date.now() - spinner.phase * spinner.waveMs
        onTriggered: spinner.phase = ((Date.now() - started) / spinner.waveMs) % 1
    }
}
