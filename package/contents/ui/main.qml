import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.notification
import "UsageParser.js" as UsageParser
import "UsageApi.js" as UsageApi
import "ClineApi.js" as ClineApi

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
    property bool notifiedOver: false   // already notified for the current over-threshold state

    // Path to the bundled fetch script (reads the local OAuth token and calls
    // the usage API in a subprocess; the token never enters this QML).
    readonly property string fetchScript: Qt.resolvedUrl("fetch-usage.sh").toString().replace(/^file:\/\//, "")

    // Path to the bundled Cline fetch script — derived from fetchScript (same
    // package directory, file:// prefix already stripped), just swapping the
    // script name. The token never enters this QML.
    readonly property string fetchClineScript: root.fetchScript.replace("fetch-usage.sh", "fetch-cline-usage.sh")

    // 0 = Claude Code, 1 = Cline
    readonly property int agentService: plasmoid.configuration.agentService

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
        // Provider-prefixed model ids like "cline-pass/glm-5.2" -> "Glm-5.2".
        let slashIdx = raw.lastIndexOf("/")
        let name = slashIdx >= 0 ? raw.slice(slashIdx + 1) : raw
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    readonly property int warnThreshold: plasmoid.configuration.warnThreshold
    readonly property int criticalThreshold: plasmoid.configuration.criticalThreshold

    // Live clock so reset countdowns tick down without a full data refresh.
    property double nowMs: Date.now()

    // All limits as a flat list (each has percent + severity).
    function allEntries() {
        let e = []
        if (usage.session) e.push(usage.session)
        if (usage.week) e.push(usage.week)
        usage.extraLimits.forEach(x => e.push(x))
        return e
    }

    // Colour level: 0 = ok/green, 1 = warn/yellow, 2 = critical/red.
    // Prefer the API's own severity when present; otherwise use thresholds.
    function limitLevel(percent, severity) {
        if (severity && severity.length > 0) {
            if (severity === "normal" || severity === "ok") return 0
            if (severity === "warning" || severity === "warn" || severity === "approaching") return 1
            return 2   // critical / exceeded / anything more severe
        }
        if (percent >= criticalThreshold) return 2
        if (percent >= warnThreshold) return 1
        return 0
    }

    function levelColor(level) {
        if (level >= 2) return Kirigami.Theme.negativeTextColor
        if (level === 1) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.positiveTextColor
    }

    function limitColor(percent, severity) {
        return levelColor(limitLevel(percent, severity))
    }

    readonly property int highestPercent: {
        let values = allEntries().map(e => e.percent)
        return values.length > 0 ? Math.max(...values) : -1
    }

    // Overall panel colour = the worst (most severe) of all limits.
    readonly property color usageColor: {
        let entries = allEntries()
        if (entries.length === 0) return Kirigami.Theme.disabledTextColor
        let worst = 0
        entries.forEach(e => {
            let lvl = limitLevel(e.percent, e.severity || "")
            if (lvl > worst) worst = lvl
        })
        return levelColor(worst)
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: root.agentService === 1 ? i18n("usagemon — Cline Usage") : i18n("usagemon — Claude Code Usage")
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
            // Cline model read: ~/.cline/data/settings/providers.json carries
            // the active provider's model id under providers.<name>.settings.model.
            if (sourceName.indexOf("providers.json") !== -1) {
                try {
                    const cfg = JSON.parse(stdout)
                    const provs = cfg.providers || {}
                    const name = cfg.lastUsedProvider
                        || Object.keys(provs)[0] || ""
                    const prov = provs[name] || {}
                    const model = (prov.settings || {}).model || ""
                    root.activeModel = root.prettyModel(model)
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

            // Cline source: the Cline usage API (via the bundled fetch script).
            // Cline has no CLI fallback, so an API failure is final for a cycle.
            if (sourceName.indexOf("fetch-cline") !== -1) {
                root.busy = false
                const clineParsed = ClineApi.parseUsage(stdout)
                if (clineParsed.ok) {
                    root.applyUsage(clineParsed, "api")
                    return
                }
                if (!root.usage.ok) {
                    root.lastError = clineParsed.error || i18n("Usage unavailable")
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
        root.checkNotifications()
    }

    // Fire a desktop notification the first time a limit crosses the notify
    // threshold; reset once everything is back below it (so we notify once per
    // crossing, not every poll).
    function checkNotifications() {
        if (!plasmoid.configuration.notificationsEnabled) return
        const threshold = plasmoid.configuration.notifyThreshold
        let over = root.allEntries().filter(e => e.percent >= threshold)
        if (over.length === 0) {
            root.notifiedOver = false
            return
        }
        if (root.notifiedOver) return
        root.notifiedOver = true

        let parts = over.map(e => {
            let name = e.label === "session" ? i18n("Session")
                     : (e.label === "week (all models)" ? i18n("Week") : e.label)
            return i18n("%1 %2%", name, e.percent)
        })
        usageNotification.text = i18n("Usage at or above %1%: %2", threshold, parts.join(", "))
        usageNotification.sendEvent()
    }

    Notification {
        id: usageNotification
        componentName: "plasma_workspace"
        eventId: "notification"
        title: root.agentService === 1 ? i18n("Cline usage high") : i18n("Claude usage high")
        iconName: "utilities-system-monitor"
        urgency: Notification.NormalUrgency
    }

    // 0 = Auto (API, then CLI), 1 = OAuth API only, 2 = CLI only
    readonly property int sourceMode: plasmoid.configuration.dataSourceMode

    function refresh() {
        if (root.busy) return
        root.busy = true
        root.triedCliFallback = false
        if (root.agentService === 1) {
            // Cline: usage API via the bundled Cline fetch script (API-only,
            // there is no CLI fallback for Cline).
            executable.exec("bash " + JSON.stringify(root.fetchClineScript))
            // Read the configured model from Cline's providers.json (best effort).
            executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.cline/data/settings/providers.json\""))
            return
        }
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

    // Advances the reset countdowns between data refreshes.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
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
