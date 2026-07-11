import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: compact

    readonly property bool horizontal: root.horizontal
    readonly property bool hasData: root.usage.ok && root.lastError.length === 0

    function colorFor(percent) {
        if (percent >= root.criticalThreshold) return Kirigami.Theme.negativeTextColor
        if (percent >= root.warnThreshold) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    Layout.preferredWidth: horizontal ? row.implicitWidth + Kirigami.Units.smallSpacing * 3 : Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: horizontal ? Kirigami.Units.iconSizes.medium : row.implicitHeight + Kirigami.Units.smallSpacing * 2
    Layout.minimumWidth: Layout.preferredWidth
    Layout.minimumHeight: Layout.preferredHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 4
        color: Kirigami.ColorUtils.tintWithAlpha(root.usageColor, Kirigami.Theme.backgroundColor, 0.88)
        border.width: 1
        border.color: Kirigami.ColorUtils.linearInterpolation(root.usageColor, Kirigami.Theme.backgroundColor, 0.55)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
            }
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        // Placeholder (loading / error) — only when we have no numbers.
        RowLayout {
            visible: !compact.hasData
            spacing: Kirigami.Units.smallSpacing / 2
            Kirigami.Icon {
                source: root.lastError.length > 0 ? "data-warning-symbolic" : "speedometer-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                color: root.usageColor
            }
            PlasmaComponents3.Label {
                text: root.lastError.length > 0 ? i18n("!") : i18n("…")
                color: root.usageColor
                font.bold: true
            }
        }

        // Session segment
        RowLayout {
            visible: compact.hasData && !!root.usage.session
            spacing: Kirigami.Units.smallSpacing / 2
            Kirigami.Icon {
                source: "chronometer-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                color: compact.colorFor(root.usage.session ? root.usage.session.percent : 0)
            }
            PlasmaComponents3.Label {
                text: (root.usage.session ? root.usage.session.percent : 0) + "%"
                color: compact.colorFor(root.usage.session ? root.usage.session.percent : 0)
                font.bold: true
            }
        }

        PlasmaComponents3.Label {
            visible: compact.hasData && !!root.usage.session && !!root.usage.week
            text: "·"
            opacity: 0.45
        }

        // Week segment
        RowLayout {
            visible: compact.hasData && !!root.usage.week
            spacing: Kirigami.Units.smallSpacing / 2
            Kirigami.Icon {
                source: "view-calendar-week-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                color: compact.colorFor(root.usage.week ? root.usage.week.percent : 0)
            }
            PlasmaComponents3.Label {
                text: (root.usage.week ? root.usage.week.percent : 0) + "%"
                color: compact.colorFor(root.usage.week ? root.usage.week.percent : 0)
                font.bold: true
            }
        }
    }
}
