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
    property alias cfg_showPanelIcon: showPanelIconCheck.checked
    property alias cfg_showPopupIcon: showPopupIconCheck.checked
    property alias cfg_dataSourceMode: sourceCombo.currentIndex
    // agentService's stored int (0=Claude, 1=Cline, 2=All, 3=Antigravity) is
    // fixed by the rest of the widget; valueRole lets the dropdown show a
    // different order (All last) without renumbering that meaning.
    property alias cfg_agentService: serviceCombo.currentValue
    property alias cfg_notificationsEnabled: notifyCheck.checked
    property alias cfg_notifyThreshold: notifyThresholdSpin.value

    QQC2.ComboBox {
        id: serviceCombo
        Kirigami.FormData.label: i18n("Agent / Service:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Claude Code"), value: 0 },
            { text: i18n("Cline"), value: 1 },
            { text: i18n("Antigravity"), value: 3 },
            { text: i18n("All"), value: 2 }
        ]
    }

    QQC2.ComboBox {
        id: sourceCombo
        Kirigami.FormData.label: i18n("Data source:")
        visible: serviceCombo.currentValue === 0 || serviceCombo.currentValue === 2
        model: [
            i18n("Automatic (OAuth API, then CLI)"),
            i18n("OAuth API only"),
            i18n("Terminal / CLI only (claude -p /usage)")
        ]
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentValue === 0
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("OAuth API reuses your existing local Claude Code login — the token is read locally and sent only to api.anthropic.com, never stored. CLI runs the claude command instead.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentValue === 1
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("Cline reuses your existing local Cline login — the access token is read from ~/.cline/data/settings/providers.json and sent only to api.cline.bot, never stored. Cline has no CLI fallback, so this source is API-only.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentValue === 2
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("All: parallel Claude Code + Cline + Antigravity display. Claude uses the OAuth API (or CLI if configured), Cline and Antigravity use their own sources. Click the panel to cycle between details in the popup.")
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        visible: serviceCombo.currentValue === 3
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("Antigravity reads quota from the local agy CLI's loopback server — it reuses an already-running agy session if found, otherwise launches one briefly just to read quota. No Google account credentials are touched. Requires agy and lsof on PATH.")
    }

    QQC2.TextField {
        id: claudeCommandField
        visible: serviceCombo.currentValue === 0 || serviceCombo.currentValue === 2
        Kirigami.FormData.label: i18n("Claude command:")
        placeholderText: "claude"
    }

    QQC2.CheckBox {
        id: widePopupCheck
        Kirigami.FormData.label: i18n("Popup:")
        text: i18n("Wider layout (show full reset time)")
    }

    QQC2.CheckBox {
        id: showPanelIconCheck
        Kirigami.FormData.label: i18n("Vendor logo:")
        text: i18n("Show in panel")
    }

    QQC2.CheckBox {
        id: showPopupIconCheck
        text: i18n("Show in popup")
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
