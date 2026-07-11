import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: bar

    property string label: ""
    property int percent: 0
    property string resets: ""
    property bool fullResets: false
    property color accentColor: Kirigami.Theme.positiveTextColor

    // In the compact popup, drop the trailing "(Timezone)" to keep the line
    // short; in the wide popup, keep the full reset string.
    readonly property string shortResets: fullResets ? resets : resets.replace(/\s*\(.*\)\s*$/, "")

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
            visible: bar.shortResets.length > 0
            text: i18n("· resets %1", bar.shortResets)
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
