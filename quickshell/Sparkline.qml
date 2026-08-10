import QtQuick

// Tiny polyline sparkline. One or two series; fixed (minY/maxY) or autoscaled Y.
Canvas {
    id: spark
    property var values: []
    property color stroke: Theme.text
    property var values2: []
    property color stroke2: Theme.subtext
    property real minY: NaN            // NaN → autoscale to the data
    property real maxY: NaN
    implicitHeight: 28
    implicitWidth: 120
    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var series = [[values, stroke], [values2, stroke2]];
        for (var s = 0; s < series.length; s++) {
            var vals = series[s][0], col = series[s][1];
            if (!vals || vals.length < 2)
                continue;
            var lo = minY, hi = maxY;
            if (isNaN(lo) || isNaN(hi)) {
                lo = Math.min.apply(null, vals);
                hi = Math.max.apply(null, vals);
            }
            if (hi - lo < 1e-6)
                hi = lo + 1;
            ctx.lineWidth = 2;
            ctx.strokeStyle = col;
            ctx.lineJoin = "round";
            ctx.beginPath();
            for (var i = 0; i < vals.length; i++) {
                var x = width * i / (vals.length - 1);
                var y = height - 1 - (height - 2) * (vals[i] - lo) / (hi - lo);
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
    }
}
