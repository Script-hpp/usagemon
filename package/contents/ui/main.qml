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

    // Dual-service data store. Both are always populated in Both mode; only the
    // active one in single mode. The rest of the widget reads `usage`, which
    // always resolves to the currently active tab.
    property var claudeUsage: ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
    property var clineUsage: ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
    property string claudeModel: ""
    property string clineModel: ""
    // Which service the popup shows (0 = Claude, 1 = Cline).  In Both mode,
    // clicking the panel icon cycles tabs; in single mode it is fixed.
    property int activeTab: root.agentService === 1 ? 1 : 0

    // Convenience binding — every function/callback reads this, so they
    // automatically follow the active tab.
    readonly property var usage: activeTab === 0 ? claudeUsage : clineUsage
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

    // 0 = Claude Code, 1 = Cline, 2 = Both
    readonly property int agentService: plasmoid.configuration.agentService

    // Drop any stale numbers from the previous source so the panel never shows
    // the other agent's limits after a settings switch.
    function resetUsageState() {
        const empty = { ok: false, error: null, session: null, week: null, extraLimits: [] }
        root.claudeUsage = empty
        root.clineUsage = empty
        root.claudeModel = ""
        root.clineModel = ""
        root.activeTab = root.agentService === 1 ? 1 : 0
        root.lastError = ""
        root.lastUpdated = ""
        root.notifiedOver = false
    }

    onAgentServiceChanged: {
        root.resetUsageState()
        root.refresh()
    }

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
    toolTipMainText: {
        if (root.agentService === 2) return i18n("usagemon — Claude + Cline")
        return root.agentService === 1 ? i18n("usagemon — Cline Usage")
                                       : i18n("usagemon — Claude Code Usage")
    }
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
        // In Both mode, show summary from both services.
        function svcLines(u, name) {
            if (!u.ok) return [i18n("%1: —", name)]
            let lines = []
            if (u.session) lines.push(i18n("%1 session: %2%", name, u.session.percent))
            if (u.week) lines.push(i18n("%1 week: %2%", name, u.week.percent))
            return lines
        }
        if (root.agentService === 2) {
            let lines = svcLines(root.claudeUsage, i18n("Claude"))
            lines = lines.concat(svcLines(root.clineUsage, i18n("Cline")))
            if (root.lastUpdated.length > 0) lines.push(i18n("Updated %1", root.lastUpdated))
            return lines.join("\n")
        }
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

            // --- Model reads (best-effort) ---

            // Claude model from ~/.claude/settings.json
            if (sourceName.indexOf("settings.json") !== -1) {
                try {
                    const cfg = JSON.parse(stdout)
                    root.claudeModel = root.prettyModel(cfg.model || "")
                } catch (e) {
                    root.claudeModel = ""
                }
                root.activeModel = root.claudeModel
                return
            }
            // Cline model from ~/.cline/.../providers.json
            if (sourceName.indexOf("providers.json") !== -1) {
                try {
                    const cfg = JSON.parse(stdout)
                    const provs = cfg.providers || {}
                    const name = cfg.lastUsedProvider || Object.keys(provs)[0] || ""
                    const prov = provs[name] || {}
                    const model = (prov.settings || {}).model || ""
                    root.clineModel = root.prettyModel(model)
                } catch (e) {
                    root.clineModel = ""
                }
                if (root.agentService === 1) root.activeModel = root.clineModel
                return
            }

            // --- Claude usage ---

            // Claude OAuth usage API (via the bundled fetch script).
            if (sourceName.indexOf("fetch-usage") !== -1) {
                const apiParsed = UsageApi.parseUsage(stdout)
                if (apiParsed.ok) {
                    root.applyClaude(apiParsed, "api")
                    return
                }
                root.pendingApiError = apiParsed.error || ""
                // In Auto mode, fall back to the CLI once before giving up.
                if (root.sourceMode === 0 && !root.triedCliFallback) {
                    root.triedCliFallback = true
                    executable.exec(root.cliCommand())
                    return   // keep busy until the CLI result arrives
                }
                root.busy = false
                if (!root.claudeUsage.ok) {
                    root.lastError = apiParsed.error || i18n("Usage unavailable")
                }
                scheduleRetry()
                return
            }

            // Cline usage API (no CLI fallback).
            if (sourceName.indexOf("fetch-cline") !== -1) {
                root.busy = false
                const clineParsed = ClineApi.parseUsage(stdout)
                if (clineParsed.ok) {
                    root.applyCline(clineParsed, "api")
                    return
                }
                if (!root.clineUsage.ok) {
                    root.lastError = clineParsed.error || i18n("Usage unavailable")
                }
                scheduleRetry()
                return
            }

            // --- Claude CLI fallback ---
            // (reached only when sourceName matches no known patterns —
            //  this is the catch-all for `claude -p /usage` output)
            root.busy = false
            const exitCode = data["exit code"]
            const stderr = (data["stderr"] || "").toString()

            if (exitCode !== 0 && stdout.trim().length === 0) {
                if (!root.claudeUsage.ok) {
                    root.lastError = stderr.trim().length > 0
                        ? stderr.trim()
                        : i18n("claude exited with code %1", exitCode)
                }
                scheduleRetry()
                return
            }

            const parsed = UsageParser.parseUsage(stdout)
            if (!parsed.ok) {
                if (!root.claudeUsage.ok) {
                    root.lastError = root.pendingApiError.length > 0
                        ? root.pendingApiError
                        : (parsed.error || i18n("Could not parse usage output"))
                }
                scheduleRetry()
                return
            }

            root.applyClaude(parsed, "cli")
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

    function applyClaude(parsed, source) {
        root.claudeUsage = parsed
        root.lastError = ""
        root.pendingApiError = ""
        root.dataSource = source
        root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm")
        root.checkNotifications()
    }
    function applyCline(parsed, source) {
        root.clineUsage = parsed
        root.lastError = ""
        root.dataSource = source
        root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm")
        root.checkNotifications()
    }
    function applyUsage(parsed, source) {
        if (root.activeTab === 0) root.claudeUsage = parsed
        else root.clineUsage = parsed
        root.lastError = ""
        root.pendingApiError = ""
        root.dataSource = source
        root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm")
        root.checkNotifications()
    }

    function checkNotifications() {
        if (!plasmoid.configuration.notificationsEnabled) return
        const threshold = plasmoid.configuration.notifyThreshold
        let allEntries = []
        function collect(u) {
            if (u.session) allEntries.push(u.session)
            if (u.week) allEntries.push(u.week)
            if (u.extraLimits) u.extraLimits.forEach(x => allEntries.push(x))
        }
        if (root.agentService === 2) {
            collect(root.claudeUsage)
            collect(root.clineUsage)
        } else {
            collect(root.usage)
        }
        let over = allEntries.filter(e => e.percent >= threshold)
        if (over.length === 0) { root.notifiedOver = false; return }
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
        title: {
            if (root.agentService === 2) return i18n("Usage high")
            return root.agentService === 1 ? i18n("Cline usage high")
                                           : i18n("Claude usage high")
        }
        iconName: "utilities-system-monitor"
        urgency: Notification.NormalUrgency
    }

    readonly property int sourceMode: plasmoid.configuration.dataSourceMode

    onSourceModeChanged: {
        root.resetUsageState()
        root.refresh()
    }

    function refresh() {
        if (root.busy) return

        // Both: fire everything in parallel, set busy=false immediately
        // so the poll timer keeps running even while subprocesses fly.
        if (root.agentService === 2) {
            root.claudeUsage = ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
            root.clineUsage = ({ ok: false, error: null, session: null, week: null, extraLimits: [] })
            root.busy = true
            root.triedCliFallback = false
            if (sourceMode === 2)
                executable.exec(cliCommand())
            else
                executable.exec("bash " + JSON.stringify(root.fetchScript))
            executable.exec("bash " + JSON.stringify(root.fetchClineScript))
            executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.claude/settings.json\""))
            executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.cline/data/settings/providers.json\""))
            return
        }

        root.busy = true
        root.triedCliFallback = false
        if (root.agentService === 1) {
            executable.exec("bash " + JSON.stringify(root.fetchClineScript))
            executable.exec("bash -lc " + JSON.stringify("cat \"$HOME/.cline/data/settings/providers.json\""))
            return
        }
        if (sourceMode === 2) {
            executable.exec(cliCommand())
        } else {
            executable.exec("bash " + JSON.stringify(root.fetchScript))
        }
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
