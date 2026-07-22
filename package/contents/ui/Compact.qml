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

    // Session percent + color for a single usage object, falling back to
    // week (then the first extra limit) when session isn't available. The
    // panel is glanceable real estate: session is the number that changes
    // fast enough to matter without expanding, so it takes priority over
    // the slower-moving week figure.
    function glancePct(u) {
        if (u.session) return u.session.percent
        if (u.week) return u.week.percent
        if (u.extraLimits && u.extraLimits.length > 0) return u.extraLimits[0].percent
        return -1
    }
    function glanceColor(u) {
        let e = u.session || u.week || (u.extraLimits && u.extraLimits[0])
        if (!e) return root.levelColor(0)
        return root.levelColor(root.limitLevel(e.percent, e.severity || ""))
    }

    function hasGoodData(u) {
        return u && u.ok && (!!u.session || !!u.week || (u.extraLimits && u.extraLimits.length > 0))
    }

    // Brand icon for the single active service (Both mode shows all three
    // separately instead), so the panel reads at a glance without a label.
    readonly property string singleModeIcon: {
        if (root.agentService === 1) return "cline.svg"
        if (root.agentService === 3) return "antigravity.svg"
        return "anthropic.svg"
    }

    // --- Both-mode layout: labelled indicators side by side ----------
    readonly property bool bothMode: root.agentService === 2
    readonly property int  claudePct: bothMode ? glancePct(root.claudeUsage) : -1
    readonly property int  clinePct:  bothMode ? glancePct(root.clineUsage) : -1
    readonly property int  antigravityPct: bothMode ? glancePct(root.antigravityUsage) : -1
    readonly property bool claudeOk: bothMode && hasGoodData(root.claudeUsage)
    readonly property bool clineOk:  bothMode && hasGoodData(root.clineUsage)
    readonly property bool antigravityOk: bothMode && hasGoodData(root.antigravityUsage)

    Layout.preferredWidth: {
        if (!horizontal) return Kirigami.Units.iconSizes.medium
        if (bothMode) return bothRow.implicitWidth + Kirigami.Units.smallSpacing * 3
        return row.implicitWidth + Kirigami.Units.smallSpacing * 3
    }
    Layout.preferredHeight: horizontal ? Kirigami.Units.iconSizes.medium
                                       : (bothMode ? bothRow.implicitHeight : row.implicitHeight) + Kirigami.Units.smallSpacing * 2
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
            } else if (bothMode) {
                root.activeTab = (root.activeTab + 1) % 3
                if (!root.expanded) root.expanded = true
            } else {
                root.expanded = !root.expanded
            }
        }
    }

    // --- Both-mode: dual indicator -----------------------------------------------
    RowLayout {
        id: bothRow
        visible: bothMode
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: [
                { icon: "anthropic.svg", pct: claudePct, ok: claudeOk, color: glanceColor(root.claudeUsage), active: root.activeTab === 0 },
                { icon: "cline.svg", pct: clinePct,  ok: clineOk,  color: glanceColor(root.clineUsage),  active: root.activeTab === 1 },
                { icon: "antigravity.svg", pct: antigravityPct, ok: antigravityOk, color: glanceColor(root.antigravityUsage), active: root.activeTab === 2 }
            ]
            delegate: RowLayout {
                spacing: Kirigami.Units.smallSpacing / 2

                // Brand icon from Lobe Icons project (MIT, github.com/lobehub/lobe-icons).
                // SVG renders as-is; the percentage label already carries the
                // severity colour. The active tab icon is opaque, inactive is dimmed.
                Image {
                    visible: plasmoid.configuration.showPanelIcon
                    source: Qt.resolvedUrl("../icons/" + modelData.icon)
                    sourceSize.width: Kirigami.Units.iconSizes.small
                    sourceSize.height: Kirigami.Units.iconSizes.small
                    opacity: modelData.active ? 1 : 0.45
                }

                PlasmaComponents3.Label {
                    visible: modelData.ok
                    text: modelData.ok ? (modelData.pct >= 0 ? modelData.pct + "%" : "…") : "—"
                    color: modelData.ok ? modelData.color : Kirigami.Theme.disabledTextColor
                    font.bold: modelData.active
                }
            }
        }
    }

    // --- Single-mode: original session · week layout ------------------------------
    RowLayout {
        id: row
        visible: !bothMode
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        // Brand icon from Lobe Icons project (MIT, github.com/lobehub/lobe-icons).
        Image {
            visible: plasmoid.configuration.showPanelIcon
            source: Qt.resolvedUrl("../icons/" + compact.singleModeIcon)
            sourceSize.width: Kirigami.Units.iconSizes.small
            sourceSize.height: Kirigami.Units.iconSizes.small
        }

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
                color: compact.hasData && root.usage.session ? root.limitColor(root.usage.session.percent, root.usage.session.severity || "") : Kirigami.Theme.disabledTextColor
            }
            PlasmaComponents3.Label {
                text: (root.usage.session ? root.usage.session.percent : 0) + "%"
                color: compact.hasData && root.usage.session ? root.limitColor(root.usage.session.percent, root.usage.session.severity || "") : Kirigami.Theme.disabledTextColor
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
                color: compact.hasData && root.usage.week ? root.limitColor(root.usage.week.percent, root.usage.week.severity || "") : Kirigami.Theme.disabledTextColor
            }
            PlasmaComponents3.Label {
                text: (root.usage.week ? root.usage.week.percent : 0) + "%"
                color: compact.hasData && root.usage.week ? root.limitColor(root.usage.week.percent, root.usage.week.severity || "") : Kirigami.Theme.disabledTextColor
                font.bold: true
            }
        }
    }
}
