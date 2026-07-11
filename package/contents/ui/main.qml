import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "UsageParser.js" as UsageParser

PlasmoidItem {
    id: root

    readonly property int formFactor: Plasmoid.formFactor
    readonly property bool horizontal: formFactor === PlasmaCore.Types.Horizontal

    property var usage: ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
    property bool busy: false
    property string lastError: ""
    property string lastUpdated: ""
    property string activeModel: ""

    function prettyModel(raw) {
        if (!raw || raw.length === 0) return ""
        // Short aliases like "opus"/"sonnet"/"haiku" -> capitalized.
        // Full ids like "claude-opus-4-8" -> "Opus 4.8".
        let m = raw.match(/claude-(opus|sonnet|haiku|fable)-?(\d+)?-?(\d+)?/i)
        if (m) {
            let name = m[1].charAt(0).toUpperCase() + m[1].slice(1)
            let ver = [m[2], m[3]].filter(x => x).join(".")
            return ver.length > 0 ? name + " " + ver : name
        }
        if (raw === "default") return i18n("Default")
        return raw.charAt(0).toUpperCase() + raw.slice(1)
    }

    readonly property int warnThreshold: plasmoid.configuration.warnThreshold
    readonly property int criticalThreshold: plasmoid.configuration.criticalThreshold

    readonly property int highestPercent: {
        let values = []
        if (usage.session) values.push(usage.session.percent)
        if (usage.week) values.push(usage.week.percent)
        usage.extraLimits.forEach(e => values.push(e.percent))
        return values.length > 0 ? Math.max(...values) : -1
    }

    readonly property color usageColor: {
        if (highestPercent < 0) return Kirigami.Theme.disabledTextColor
        if (highestPercent >= criticalThreshold) return Kirigami.Theme.negativeTextColor
        if (highestPercent >= warnThreshold) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: i18n("usagemon — Claude Code Usage")
    toolTipTextFormat: Text.PlainText
    toolTipSubText: root.tooltipText()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Now")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    function tooltipText() {
        if (root.lastError.length > 0) {
            return i18n("Error: %1", root.lastError)
        }
        if (!usage.ok) {
            return i18n("Fetching usage…")
        }
        let lines = []
        if (usage.session) {
            lines.push(i18n("Session: %1% (resets %2)", usage.session.percent, usage.session.resets))
        }
        if (usage.week) {
            lines.push(i18n("Week: %1% (resets %2)", usage.week.percent, usage.week.resets))
        }
        usage.extraLimits.forEach(entry => {
            lines.push(i18n("%1: %2% (resets %3)", entry.label, entry.percent, entry.resets))
        })
        if (root.activeModel.length > 0) {
            lines.push(i18n("Model: %1", root.activeModel))
        }
        if (root.lastUpdated.length > 0) {
            lines.push(i18n("Updated %1", root.lastUpdated))
        }
        return lines.join("\n")
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)

            const stdout = (data["stdout"] || "").toString()

            // The model read is a separate, best-effort source.
            if (sourceName.indexOf("settings.json") !== -1) {
                try {
                    const cfg = JSON.parse(stdout)
                    root.activeModel = root.prettyModel(cfg.model || "")
                } catch (e) {
                    root.activeModel = ""
                }
                return
            }

            root.busy = false
            const exitCode = data["exit code"]
            const stderr = (data["stderr"] || "").toString()

            if (exitCode !== 0 && stdout.trim().length === 0) {
                root.lastError = stderr.trim().length > 0
                    ? stderr.trim()
                    : i18n("claude exited with code %1", exitCode)
                return
            }

            const parsed = UsageParser.parseUsage(stdout)
            if (!parsed.ok) {
                root.lastError = parsed.error || i18n("Could not parse usage output")
                return
            }

            root.lastError = ""
            root.usage = parsed
            root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm")
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function refresh() {
        if (root.busy) return
        root.busy = true
        const command = plasmoid.configuration.claudeCommand || "claude"
        // Run inside a login shell: plasmashell doesn't inherit the PATH set up
        // in ~/.bash_profile or ~/.zshrc, where user-installed CLIs often live
        // (e.g. ~/.local/bin).
        executable.exec("bash -lc " + JSON.stringify(command + " -p /usage"))
        // Read the configured model from Claude Code's settings (best effort).
        executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.claude/settings.json\""))
    }

    Timer {
        id: pollTimer
        interval: Math.max(10, plasmoid.configuration.pollIntervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: Compact {}
    fullRepresentation: Full {}
}
