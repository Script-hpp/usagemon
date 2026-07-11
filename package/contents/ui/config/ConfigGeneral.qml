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
        from: 10
        to: 3600
        stepSize: 10
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
