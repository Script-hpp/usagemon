.pragma library

// Parses the JSON body from
// https://api.cline.bot/api/v1/users/me/plan/usage-limits into the same shape
// UsageApi.js produces for Claude Code, so the rest of the widget is
// source-agnostic:
//
//   { ok, error, session, week, extraLimits: [], raw }
//
// where session/week/each-extra are { label, percent, resets, resetsAt, severity }.
//
// Cline's response shape differs from Claude's:
//   { data: { limits: [ { type, percentUsed, resetsAt } ] }, success: true }
//
// type values observed: "five_hour" (≈ session), "weekly", "monthly", plus any
// future ones. There is no severity field, so colors fall back to the
// configurable warning/critical thresholds (and there is no per-model scope).

function formatReset(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    var h = d.getHours();
    var m = d.getMinutes();
    var ap = h < 12 ? "am" : "pm";
    var h12 = h % 12;
    if (h12 === 0) h12 = 12;
    // Match the CLI style: drop ":00" for on-the-hour times.
    var time = m === 0 ? ("" + h12 + ap)
                       : (h12 + ":" + (m < 10 ? "0" : "") + m + ap);
    return months[d.getMonth()] + " " + d.getDate() + ", " + time;
}

function parseUsage(jsonText) {
    var result = {
        ok: false,
        error: null,
        session: null,
        week: null,
        extraLimits: [],
        raw: jsonText || ""
    };

    if (!jsonText || jsonText.trim().length === 0) {
        result.error = "Empty API response";
        return result;
    }

    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        result.error = "Invalid API response";
        return result;
    }

    if (!data || typeof data !== "object") {
        result.error = "Empty API response";
        return result;
    }

    // In-band API error. Cline returns {"error": "..."} (string) on auth
    // failures, so handle both string and {message} shapes.
    if (data.error) {
        result.error = (typeof data.error === "string")
                     ? data.error
                     : (data.error.message || data.error.type || "API error");
        return result;
    }

    // Cline wraps the payload in { data: { limits: [...] }, success: true }.
    var payload = data.data || data;
    if (typeof data.success === "boolean" && !data.success) {
        result.error = "API reported failure";
        return result;
    }

    var limits = payload.limits;
    if (!Array.isArray(limits) || limits.length === 0) {
        result.error = "No limits in API response";
        return result;
    }

    for (var i = 0; i < limits.length; i++) {
        var l = limits[i];
        if (l === null || typeof l !== "object") {
            continue;
        }
        // Cline uses "percentUsed"; tolerate "percent" for forward-compat.
        var pct = (typeof l.percentUsed === "number") ? l.percentUsed
                : (typeof l.percent === "number") ? l.percent : NaN;
        if (isNaN(pct)) {
            continue;
        }
        var resetsAt = l.resetsAt ? Date.parse(l.resetsAt) : 0;
        if (isNaN(resetsAt)) resetsAt = 0;
        var entry = {
            percent: Math.round(pct),
            resets: formatReset(l.resetsAt),
            resetsAt: resetsAt,
            severity: ""   // Cline provides no severity -> threshold fallback
        };

        var t = (l.type || l.kind || "").toString();
        if (t === "five_hour" || t === "session") {
            entry.label = "session";
            result.session = entry;
        } else if (t === "weekly" || t === "weekly_all" || t === "week") {
            entry.label = "week (all models)";
            result.week = entry;
        } else if (t === "monthly" || t === "month") {
            entry.label = "month";
            result.extraLimits.push(entry);
        } else {
            entry.label = t || "limit";
            result.extraLimits.push(entry);
        }
    }

    if (!result.session && !result.week && result.extraLimits.length === 0) {
        result.error = "No usable limits in API response";
        return result;
    }

    result.ok = true;
    return result;
}
