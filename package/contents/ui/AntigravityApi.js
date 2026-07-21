.pragma library

// Parses the `agy` CLI's local RetrieveUserQuotaSummary response (fetched by
// fetch-antigravity-usage.sh) into the same shape UsageApi.js/ClineApi.js
// produce, so the rest of the widget is source-agnostic:
//
//   { ok, error, session, week, extraLimits: [], raw }
//
// where session/week/each-extra are { label, percent, resets, resetsAt, severity }.
//
// Antigravity's response shape (observed live via `agy`'s embedded server):
//   { groups: [
//       { displayName: "Gemini Models", buckets: [
//           { bucketId: "gemini-weekly", window: "weekly", remainingFraction, resetTime },
//           { bucketId: "gemini-5h",     window: "5h",      remainingFraction, resetTime }
//       ] },
//       { displayName: "Claude and GPT models", buckets: [ ... "3p-weekly", "3p-5h" ... ] }
//   ] }
//
// Antigravity pools quota per *group* (Gemini vs. Claude+GPT), not per
// model, and each group has its own 5h/weekly pair. There is no severity
// field, so colors fall back to the configurable warning/critical
// thresholds. To fit the widget's single session/week pair, the more-used
// bucket of each window kind becomes session/week and the other group's
// buckets land in extraLimits (labelled with their group name) so nothing
// is lost — just deprioritized in the compact view.

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
        result.error = "Empty Antigravity response";
        return result;
    }

    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        result.error = "Invalid Antigravity response";
        return result;
    }

    if (!data || typeof data !== "object") {
        result.error = "Empty Antigravity response";
        return result;
    }

    if (data.error) {
        result.error = (typeof data.error === "string")
                     ? data.error
                     : (data.error.message || "Antigravity error");
        return result;
    }

    var groups = data.groups;
    if (!Array.isArray(groups) || groups.length === 0) {
        result.error = "No quota groups in Antigravity response";
        return result;
    }

    // Flatten every bucket, tagging it with its group's display name.
    var entries = [];
    for (var i = 0; i < groups.length; i++) {
        var g = groups[i];
        if (!g || !Array.isArray(g.buckets)) continue;
        var groupName = g.displayName || "Antigravity";
        for (var j = 0; j < g.buckets.length; j++) {
            var b = g.buckets[j];
            if (!b || typeof b.remainingFraction !== "number") continue;
            var resetsAt = b.resetTime ? Date.parse(b.resetTime) : 0;
            if (isNaN(resetsAt)) resetsAt = 0;
            entries.push({
                group: groupName,
                window: (b.window || "").toString(),
                percent: Math.round((1 - b.remainingFraction) * 100),
                resets: formatReset(b.resetTime),
                resetsAt: resetsAt,
                severity: ""
            });
        }
    }

    if (entries.length === 0) {
        result.error = "No usable buckets in Antigravity response";
        return result;
    }

    // Pick the most-used bucket per window kind for session/week; the rest
    // (the other group's bucket of that kind) goes to extraLimits.
    function worstOf(list) {
        var best = null;
        for (var k = 0; k < list.length; k++) {
            if (!best || list[k].percent > best.percent) best = list[k];
        }
        return best;
    }

    var fiveHour = entries.filter(function (e) { return e.window === "5h"; });
    var weekly = entries.filter(function (e) { return e.window === "weekly"; });
    var sessionPick = worstOf(fiveHour);
    var weekPick = worstOf(weekly);

    entries.forEach(function (e) {
        if (e === sessionPick || e === weekPick) return;
        result.extraLimits.push({
            label: e.group + " " + (e.window === "5h" ? "session" : "week"),
            percent: e.percent,
            resets: e.resets,
            resetsAt: e.resetsAt,
            severity: e.severity
        });
    });

    if (sessionPick) {
        result.session = {
            label: "session",
            group: sessionPick.group,
            percent: sessionPick.percent,
            resets: sessionPick.resets,
            resetsAt: sessionPick.resetsAt,
            severity: sessionPick.severity
        };
    }
    if (weekPick) {
        result.week = {
            label: "week (all models)",
            group: weekPick.group,
            percent: weekPick.percent,
            resets: weekPick.resets,
            resetsAt: weekPick.resetsAt,
            severity: weekPick.severity
        };
    }

    if (!result.session && !result.week && result.extraLimits.length === 0) {
        result.error = "No usable limits in Antigravity response";
        return result;
    }

    result.ok = true;
    return result;
}
