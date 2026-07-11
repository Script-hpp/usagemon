import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "UsageParser.js" as UsageParser
import "UsageApi.js" as UsageApi

PlasmoidItem {
    id: root

    readonly property int formFactor: Plasmoid.formFactor
    readonly property bool horizontal: formFactor === PlasmaCore.Types.Horizontal

    property var usage: ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
    property bool busy: false
    property string lastError: ""
    property string lastUpdated: ""
    property string activeModel: ""
    property string dataSource: ""   // "api" or "cli" — which source last succeeded
    property bool triedCliFallback: false
    property string pendingApiError: ""

    // Path to the bundled fetch script (reads the local OAuth token and calls
    // the usage API in a subprocess; the token never enters this QML).
    readonly property string fetchScript: Qt.resolvedUrl("fetch-usage.sh").toString().replace(/^file:\/\//, "")

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

            // Primary source: the OAuth usage API (via the bundled fetch script).
            if (sourceName.indexOf("fetch-usage") !== -1) {
                const apiParsed = UsageApi.parseUsage(stdout)
                if (apiParsed.ok) {
                    root.applyUsage(apiParsed, "api")
                    root.busy = false
                    return
                }
                root.pendingApiError = apiParsed.error || ""
                // API unavailable (rate limited, no token, network) — in Auto
                // mode, fall back to the CLI once before giving up this cycle.
                if (root.sourceMode === 0 && !root.triedCliFallback) {
                    root.triedCliFallback = true
                    executable.exec(root.cliCommand())
                    return   // keep busy until the CLI result arrives
                }
                root.busy = false
                if (!root.usage.ok) {
                    root.lastError = apiParsed.error || i18n("Usage unavailable")
                }
                scheduleRetry()
                return
            }

            // Fallback source: `claude -p /usage`.
            root.busy = false
            const exitCode = data["exit code"]
            const stderr = (data["stderr"] || "").toString()

            if (exitCode !== 0 && stdout.trim().length === 0) {
                if (!root.usage.ok) {
                    root.lastError = stderr.trim().length > 0
                        ? stderr.trim()
                        : i18n("claude exited with code %1", exitCode)
                }
                scheduleRetry()
                return
            }

            const parsed = UsageParser.parseUsage(stdout)
            if (!parsed.ok) {
                // Keep the last good values instead of wiping them, and retry.
                if (!root.usage.ok) {
                    // Prefer the (more informative) API error if we have one,
                    // e.g. "Rate limited" rather than the vague CLI message.
                    root.lastError = root.pendingApiError.length > 0
                        ? root.pendingApiError
                        : (parsed.error || i18n("Could not parse usage output"))
                }
                scheduleRetry()
                return
            }

            root.applyUsage(parsed, "cli")
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Login shell so we pick up a `claude` installed in ~/.local/bin etc.
    function cliCommand() {
        const command = plasmoid.configuration.claudeCommand || "claude"
        return "bash -lc " + JSON.stringify(command + " -p /usage")
    }

    function applyUsage(parsed, source) {
        root.lastError = ""
        root.pendingApiError = ""
        root.usage = parsed
        root.dataSource = source
        root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm")
    }

    // 0 = Auto (API, then CLI), 1 = OAuth API only, 2 = CLI only
    readonly property int sourceMode: plasmoid.configuration.dataSourceMode

    function refresh() {
        if (root.busy) return
        root.busy = true
        root.triedCliFallback = false
        if (sourceMode === 2) {
            // CLI only.
            executable.exec(cliCommand())
        } else {
            // Auto or API-only: OAuth usage API via the bundled fetch script.
            executable.exec("bash " + JSON.stringify(root.fetchScript))
        }
        // Read the configured model from Claude Code's settings (best effort).
        executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.claude/settings.json\""))
    }

    // The usage endpoint is rate-limited (both the API and the CLI hit the same
    // one), so hammering it just yields 429s / empty bodies. Only retry sooner
    // than the normal interval when we have nothing to show at all (e.g. right
    // after startup), and not too aggressively.
    function scheduleRetry() {
        if (root.usage.ok) return
        if (retryTimer.running) return
        retryTimer.start()
    }

    Timer {
        id: retryTimer
        interval: 60000
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: pollTimer
        // Minimum 60s — the source rate-limits, so faster polling is
        // counterproductive (the numbers change slowly anyway).
        interval: Math.max(60, plasmoid.configuration.pollIntervalSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: Compact {}
    fullRepresentation: Full {}
}
