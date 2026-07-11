import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: bar

    property string label: ""
    property int percent: 0
    property string resets: ""
    property double resetsAt: 0   // epoch ms; 0 = unknown (no live countdown)
    property double nowMs: 0
    property bool fullResets: false
    property color accentColor: Kirigami.Theme.positiveTextColor

    // In the compact popup, drop the trailing "(Timezone)" to keep the line
    // short; in the wide popup, keep the full reset string.
    readonly property string shortResets: fullResets ? resets : resets.replace(/\s*\(.*\)\s*$/, "")

    // "in 2h 14m" / "in 3d 4h" / "in 12m". Recomputed whenever nowMs ticks.
    readonly property string countdown: {
        void nowMs   // depend on the clock so this re-evaluates each tick
        if (resetsAt <= 0) return ""
        let diff = resetsAt - (nowMs > 0 ? nowMs : Date.now())
        if (diff <= 0) return i18n("soon")
        let mins = Math.floor(diff / 60000)
        let d = Math.floor(mins / 1440); mins -= d * 1440
        let h = Math.floor(mins / 60); mins -= h * 60
        if (d > 0) return i18n("%1d %2h", d, h)
        if (h > 0) return i18n("%1h %2m", h, mins)
        return i18n("%1m", mins)
    }

    // Narrow popup: just the live countdown (short, never truncated).
    // Wide popup: countdown plus the absolute time.
    readonly property string resetText: {
        void nowMs
        if (countdown.length === 0) {
            return shortResets.length > 0 ? i18n("· resets %1", shortResets) : ""
        }
        if (fullResets && shortResets.length > 0) {
            return i18n("· resets in %1 · %2", countdown, shortResets)
        }
        return i18n("· resets in %1", countdown)
    }

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            implicitWidth: Kirigami.Units.smallSpacing
            implicitHeight: Kirigami.Units.smallSpacing
            radius: width / 2
            color: bar.accentColor
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents3.Label {
            text: bar.label
            font.capitalization: Font.Capitalize
            color: Kirigami.Theme.textColor
        }

        PlasmaComponents3.Label {
            visible: bar.resetText.length > 0
            text: bar.resetText
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            text: bar.percent + "%"
            font.bold: true
            color: bar.accentColor
        }
    }

    Rectangle {
        id: track
        Layout.fillWidth: true
        implicitHeight: Math.max(3, Math.round(Kirigami.Units.smallSpacing * 0.7))
        radius: height / 2
        color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)

        Rectangle {
            id: fill
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: track.width * Math.min(1, Math.max(0, bar.percent / 100))
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.darker(bar.accentColor, 1.15) }
                GradientStop { position: 1.0; color: bar.accentColor }
            }

            Behavior on width {
                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
            }
        }
    }
}
