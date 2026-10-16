/*
 * The session under way, from its start to its reset: the usage fetched so
 * far as a line over a shaded area, a dot at the latest figure, and a dashed
 * line on to where the pace leads — the limit, marked with a dot, or the reset.
 *
 * Drawn on a Canvas, which repaints only when the figures do, about once a
 * minute. Its context has no line dashes, so they are drawn as segments.
 */

import QtQuick

import org.kde.kirigami as Kirigami

Canvas {
    id: chart

    // Usage.sessionProgress(); null draws nothing.
    property var progress: null
    property color color: Kirigami.Theme.highlightColor
    property color paceColor: Kirigami.Theme.disabledTextColor

    readonly property var pace: progress ? progress.pace : null
    // Room for the dots at the top and right edges.
    readonly property real inset: Math.round(Kirigami.Units.smallSpacing * 0.875)
    readonly property real dotRadius: Kirigami.Units.smallSpacing * 0.875

    implicitHeight: Kirigami.Units.gridUnit * 2.5

    onProgressChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaceColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function textColor(alpha) {
        var c = Kirigami.Theme.textColor;
        return Qt.rgba(c.r, c.g, c.b, alpha);
    }

    function dashedLine(ctx, x1, y1, x2, y2, dash, gap) {
        var length = Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
        if (length <= 0) {
            return;
        }
        var dx = (x2 - x1) / length;
        var dy = (y2 - y1) / length;
        ctx.beginPath();
        for (var d = 0; d < length; d += dash + gap) {
            var e = Math.min(length, d + dash);
            ctx.moveTo(x1 + dx * d, y1 + dy * d);
            ctx.lineTo(x1 + dx * e, y1 + dy * e);
        }
        ctx.stroke();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (!progress) {
            return;
        }
        var left = 0;
        var right = width - inset;
        var top = inset;
        var bottom = height - 0.5;
        var span = progress.end - progress.start;
        function x(t) { return left + (t - progress.start) / span * (right - left); }
        function y(percent) { return bottom - Math.min(100, Math.max(0, percent)) / 100 * (bottom - top); }

        ctx.lineWidth = 1;
        // The limit, dashed, and the baseline.
        ctx.strokeStyle = textColor(0.12);
        dashedLine(ctx, left, Math.round(top) + 0.5, right, Math.round(top) + 0.5, 2, 3);
        ctx.strokeStyle = textColor(0.3);
        ctx.beginPath();
        ctx.moveTo(left, bottom);
        ctx.lineTo(right, bottom);
        ctx.stroke();

        var points = progress.points;
        var last = progress.newest;

        // The area under the line, then the line.
        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.22);
        ctx.beginPath();
        ctx.moveTo(x(points[0].t), bottom);
        for (var i = 0; i < points.length; i++) {
            ctx.lineTo(x(points[i].t), y(points[i].percent));
        }
        ctx.lineTo(x(last.t), bottom);
        ctx.closePath();
        ctx.fill();

        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(x(points[0].t), y(points[0].percent));
        for (var j = 1; j < points.length; j++) {
            ctx.lineTo(x(points[j].t), y(points[j].percent));
        }
        ctx.stroke();

        // Where the pace leads: the limit if it comes before the reset.
        if (pace && !pace.reached) {
            var endX = pace.limitAt > 0 ? x(pace.limitAt) : right;
            var endY = pace.limitAt > 0 ? y(100) : y(pace.atReset);
            ctx.strokeStyle = paceColor;
            ctx.lineWidth = 1.5;
            ctx.lineCap = "butt";
            dashedLine(ctx, x(last.t), y(last.percent), endX, endY, 3, 3);
            if (pace.limitAt > 0) {
                ctx.fillStyle = paceColor;
                ctx.beginPath();
                ctx.arc(endX, endY, dotRadius, 0, 2 * Math.PI);
                ctx.fill();
            }
        }

        // Now.
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(x(last.t), y(last.percent), dotRadius, 0, 2 * Math.PI);
        ctx.fill();
    }
}
