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
                text: {
                    if (root.agentService === 2) {
                        const names = [i18n("Claude"), i18n("Cline"), i18n("Antigravity")]
                        return i18n("usagemon — %1", names[root.activeTab])
                    }
                    if (root.agentService === 3) return i18n("usagemon — Antigravity")
                    return root.agentService === 1 ? i18n("usagemon — Cline") : i18n("usagemon")
                }
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // In Both mode, show a compact tab switcher under the heading.
            RowLayout {
                visible: root.agentService === 2
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: [i18n("Claude"), i18n("Cline"), i18n("Antigravity")]
                    delegate: PlasmaComponents3.Label {
                        text: modelData
                        font.bold: root.activeTab === index
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: root.activeTab === index ? 1.0 : 0.5
                        color: root.activeTab === index ? Kirigami.Theme.linkColor : Kirigami.Theme.disabledTextColor
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeTab = index
                        }
                    }
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing / 2
                Layout.fillWidth: true

                readonly property string bothModel: root.activeTab === 0 ? root.claudeModel
                                                   : root.activeTab === 1 ? root.clineModel
                                                   : root.antigravityModel
                readonly property string shownModel: root.agentService === 2 ? bothModel : root.activeModel
                // Brand icon for the model family behind the current reading:
                // Claude for Claude Code/Cline (Cline mostly proxies Claude
                // models too), Antigravity's own icon unless its active group
                // is Gemini, in which case that's more informative.
                readonly property string modelIcon: {
                    const antigravityTab = root.agentService === 3 || (root.agentService === 2 && root.activeTab === 2)
                    if (antigravityTab) return shownModel.indexOf("Gemini") !== -1 ? "gemini.svg" : "antigravity.svg"
                    const clineTab = root.agentService === 1 || (root.agentService === 2 && root.activeTab === 1)
                    return clineTab ? "cline.svg" : "anthropic.svg"
                }

                Image {
                    visible: parent.shownModel.length > 0
                    source: Qt.resolvedUrl("../icons/" + parent.modelIcon)
                    sourceSize.width: Kirigami.Units.iconSizes.small
                    sourceSize.height: Kirigami.Units.iconSizes.small
                }

                PlasmaComponents3.Label {
                    visible: parent.shownModel.length > 0
                    text: i18n("Model: %1", parent.shownModel)
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
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
