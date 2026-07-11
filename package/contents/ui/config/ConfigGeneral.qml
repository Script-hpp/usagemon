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

    QQC2.ComboBox {
        id: sourceCombo
        Kirigami.FormData.label: i18n("Data source:")
        model: [
            i18n("Automatic (OAuth API, then CLI)"),
            i18n("OAuth API only"),
            i18n("Terminal / CLI only (claude -p /usage)")
        ]
    }

    QQC2.Label {
        Kirigami.FormData.label: ""
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("OAuth API reuses your existing local Claude Code login — the token is read locally and sent only to api.anthropic.com, never stored. CLI runs the claude command instead.")
    }

    QQC2.TextField {
        id: claudeCommandField
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
}
