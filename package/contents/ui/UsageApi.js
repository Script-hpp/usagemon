.pragma library

// Parses the JSON body from https://api.anthropic.com/api/oauth/usage into the
// same shape UsageParser.js produces for the CLI, so the rest of the widget is
// source-agnostic:
//
//   { ok, error, session, week, extraLimits: [], raw }
//
// where session/week/each-extra are { label, percent, resets }.

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

    // Rate limit / auth / other in-band API errors.
    if (data.error) {
        result.error = data.error.message || data.error.type || "API error";
        return result;
    }

    var limits = data.limits;
    if (!Array.isArray(limits) || limits.length === 0) {
        result.error = "No limits in API response";
        return result;
    }

    for (var i = 0; i < limits.length; i++) {
        var l = limits[i];
        if (l === null || typeof l !== "object" || typeof l.percent !== "number") {
            continue;
        }
        var entry = {
            percent: Math.round(l.percent),
            resets: formatReset(l.resets_at)
        };

        if (l.kind === "session") {
            entry.label = "session";
            result.session = entry;
        } else if (l.kind === "weekly_all") {
            entry.label = "week (all models)";
            result.week = entry;
        } else {
            var name = (l.scope && l.scope.model && l.scope.model.display_name)
                ? l.scope.model.display_name : "scoped";
            entry.label = "week (" + name + ")";
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
