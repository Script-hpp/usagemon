import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full

    readonly property bool wide: plasmoid.configuration.widePopup

    Layout.minimumWidth: Kirigami.Units.gridUnit * (wide ? 16 : 10)
    Layout.preferredWidth: Kirigami.Units.gridUnit * (wide ? 20 : 11)
    Layout.maximumWidth: Kirigami.Units.gridUnit * (wide ? 26 : 13)
    spacing: Kirigami.Units.smallSpacing

    // Single flat list of every limit, so session/week/extra all render
    // through one identical delegate — no per-item special casing.
    readonly property var limits: {
        if (!root.usage.ok) return []
        let mk = (label, e) => ({ label: label, percent: e.percent, resets: e.resets,
                                  resetsAt: e.resetsAt || 0, severity: e.severity || "" })
        let out = []
        if (root.usage.session) out.push(mk(i18n("Session"), root.usage.session))
        if (root.usage.week) out.push(mk(i18n("Week"), root.usage.week))
        root.usage.extraLimits.forEach(e => out.push(mk(e.label, e)))
        return out
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Kirigami.Heading {
                level: 5
                text: i18n("usagemon")
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                visible: root.activeModel.length > 0
                text: i18n("Model: %1", root.activeModel)
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        PlasmaComponents3.BusyIndicator {
            visible: root.busy
            running: root.busy
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }

        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            display: PlasmaComponents3.AbstractButton.IconOnly
            onClicked: root.refresh()
            PlasmaComponents3.ToolTip.text: i18n("Refresh now")
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: root.lastError.length > 0
        type: Kirigami.MessageType.Error
        text: root.lastError
    }

    PlasmaComponents3.Label {
        visible: root.lastError.length === 0 && !root.usage.ok
        text: i18n("Fetching usage…")
        opacity: 0.7
    }

    Repeater {
        model: full.limits

        delegate: UsageBar {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.topMargin: index > 0 ? Kirigami.Units.smallSpacing : 0
            label: modelData.label
            percent: modelData.percent
            resets: modelData.resets
            resetsAt: modelData.resetsAt
            nowMs: root.nowMs
            fullResets: full.wide
            accentColor: root.limitColor(modelData.percent, modelData.severity)
        }
    }

    PlasmaComponents3.Label {
        Layout.alignment: Qt.AlignRight
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.lastUpdated.length > 0
        text: i18n("Updated %1", root.lastUpdated)
        opacity: 0.6
        font: Kirigami.Theme.smallFont
    }
}
