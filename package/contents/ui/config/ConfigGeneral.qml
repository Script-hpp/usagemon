import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_claudeCommand: claudeCommandField.text
    property alias cfg_pollIntervalSeconds: pollIntervalSpin.value
    property alias cfg_warnThreshold: warnThresholdSpin.value
    property alias cfg_criticalThreshold: criticalThresholdSpin.value
    property alias cfg_widePopup: widePopupCheck.checked
    property alias cfg_dataSourceMode: sourceCombo.currentIndex
    property alias cfg_agentService: serviceCombo.currentIndex
    property alias cfg_notificationsEnabled: notifyCheck.checked
    property alias cfg_notifyThreshold: notifyThresholdSpin.value

    // Icon shown per agentService index in the combo box below; "" for All
    // since it represents every service at once rather than one brand.
    readonly property var serviceIcons: ["../../icons/anthropic.svg", "../../icons/cline.svg", "", "../../icons/antigravity.svg"]

    QQC2.ComboBox {
        id: serviceCombo
        Kirigami.FormData.label: i18n("Agent / Service:")
        model: [
            i18n("Claude Code"),
            i18n("Cline"),
            i18n("All"),
            i18n("Antigravity")
        ]

        delegate: QQC2.ItemDelegate {
            width: serviceCombo.width
            highlighted: serviceCombo.highlightedIndex === index
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Image {
                    visible: page.serviceIcons[index].length > 0
                    source: page.serviceIcons[index].length > 0 ? Qt.resolvedUrl(page.serviceIcons[index]) : ""
                    sourceSize.width: Kirigami.Units.iconSizes.small
                    sourceSize.height: Kirigami.Units.iconSizes.small
                }
                QQC2.Label {
                    text: modelData
                    Layout.fillWidth: true
                }
            }
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Image {
                visible: page.serviceIcons[serviceCombo.currentIndex].length > 0
                source: page.serviceIcons[serviceCombo.currentIndex].length > 0
                        ? Qt.resolvedUrl(page.serviceIcons[serviceCombo.currentIndex]) : ""
                sourceSize.width: Kirigami.Units.iconSizes.small
                sourceSize.height: Kirigami.Units.iconSizes.small
            }
            QQC2.Label {
                text: serviceCombo.displayText
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }

    QQC2.ComboBox {
        id: sourceCombo
        Kirigami.FormData.label: i18n("Data source:")
        visible: serviceCombo.currentIndex === 0 || serviceCombo.currentIndex === 2
        model: [
            i18n("Automatic (OAuth API, then CLI)"),
            i18n("OAuth API only"),
            i18n("Terminal / CLI only (claude -p /usage)")
        ]
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentIndex === 0
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("OAuth API reuses your existing local Claude Code login — the token is read locally and sent only to api.anthropic.com, never stored. CLI runs the claude command instead.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentIndex === 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("Cline reuses your existing local Cline login — the access token is read from ~/.cline/data/settings/providers.json and sent only to api.cline.bot, never stored. Cline has no CLI fallback, so this source is API-only.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentIndex === 2
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("All: parallel Claude Code + Cline + Antigravity display. Claude uses the OAuth API (or CLI if configured), Cline and Antigravity use their own sources. Click the panel to cycle between details in the popup.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentIndex === 3
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("Antigravity reads quota from the local agy CLI's loopback server — it reuses an already-running agy session if found, otherwise launches one briefly just to read quota. No Google account credentials are touched. Requires agy and lsof on PATH.")
    }

    QQC2.TextField {
        id: claudeCommandField
        visible: serviceCombo.currentIndex === 0 || serviceCombo.currentIndex === 2
        Kirigami.FormData.label: i18n("Claude command:")
        placeholderText: "claude"
    }

    QQC2.CheckBox {
        id: widePopupCheck
        Kirigami.FormData.label: i18n("Popup:")
        text: i18n("Wider layout (show full reset time)")
    }

    QQC2.SpinBox {
        id: pollIntervalSpin
        Kirigami.FormData.label: i18n("Poll interval (seconds):")
        from: 60
        to: 3600
        stepSize: 30
    }

    QQC2.SpinBox {
        id: warnThresholdSpin
        Kirigami.FormData.label: i18n("Warn threshold (%):")
        from: 1
        to: 100
    }

    QQC2.SpinBox {
        id: criticalThresholdSpin
        Kirigami.FormData.label: i18n("Critical threshold (%):")
        from: 1
        to: 100
    }

    QQC2.CheckBox {
        id: notifyCheck
        Kirigami.FormData.label: i18n("Notifications:")
        text: i18n("Notify when a limit is high")
    }

    QQC2.SpinBox {
        id: notifyThresholdSpin
        Kirigami.FormData.label: i18n("Notify threshold (%):")
        enabled: notifyCheck.checked
        from: 1
        to: 100
    }
}
