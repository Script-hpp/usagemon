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

    // Worst percent + color for a single usage object.
    function worstPct(u) {
        let pcts = []
        if (u.session) pcts.push(u.session.percent)
        if (u.week) pcts.push(u.week.percent)
        if (u.extraLimits) u.extraLimits.forEach(x => pcts.push(x.percent))
        return pcts.length > 0 ? Math.max(...pcts) : -1
    }
    function worstColor(u) {
        let level = 0
        function walk(e) {
            if (!e) return
            let l = root.limitLevel(e.percent, e.severity || "")
            if (l > level) level = l
        }
        walk(u.session); walk(u.week)
        if (u.extraLimits) u.extraLimits.forEach(walk)
        return root.levelColor(level)
    }

    function hasGoodData(u) {
        return u && u.ok && (!!u.session || !!u.week || (u.extraLimits && u.extraLimits.length > 0))
    }

    // --- Both-mode layout: two labelled indicators side by side ----------
    readonly property bool bothMode: root.agentService === 2
    readonly property int  claudePct: bothMode ? worstPct(root.claudeUsage) : -1
    readonly property int  clinePct:  bothMode ? worstPct(root.clineUsage) : -1
    readonly property bool claudeOk: bothMode && hasGoodData(root.claudeUsage)
    readonly property bool clineOk:  bothMode && hasGoodData(root.clineUsage)

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
                root.activeTab = root.activeTab === 0 ? 1 : 0
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
                { label: "A", pct: claudePct, ok: claudeOk, color: worstColor(root.claudeUsage), active: root.activeTab === 0 },
                { label: "C", pct: clinePct,  ok: clineOk,  color: worstColor(root.clineUsage),  active: root.activeTab === 1 }
            ]
            delegate: RowLayout {
                spacing: Kirigami.Units.smallSpacing / 2

                // Stylised indicator circle with a letter.
                Rectangle {
                    width: Kirigami.Units.iconSizes.small + 2
                    height: width
                    radius: width / 2
                    color: modelData.active ? modelData.color : Kirigami.Theme.disabledTextColor
                    opacity: modelData.active ? 1 : 0.5
                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: "white"
                    }
                }

                PlasmaComponents3.Label {
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
