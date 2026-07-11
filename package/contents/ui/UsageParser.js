.pragma library

// Parses the text output of `claude -p "/usage"`.
//
// Example input:
//   Current session: 9% used · resets Jul 11, 12:59pm (Europe/Berlin)
//   Current week (all models): 34% used · resets Jul 12, 6:59am (Europe/Berlin)
//   Current week (Fable): 2% used · resets Jul 12, 6:59am (Europe/Berlin)
//
// Returns:
//   {
//     ok: bool,
//     error: string | null,
//     session: { percent, resets, label } | null,
//     week: { percent, resets, label } | null,
//     extraLimits: [{ percent, resets, label }],
//     raw: string
//   }

// The CLI uses a middle dot (U+00B7) as a separator; match it loosely
// alongside a plain "-" or ";" in case output formatting changes slightly.
const LIMIT_LINE = /^Current\s+(.+?):\s*(\d+)%\s*used(?:\s*[·;-]\s*resets\s+(.+?))?\s*$/;

function parseUsage(text) {
    const result = {
        ok: false,
        error: null,
        session: null,
        week: null,
        extraLimits: [],
        raw: text || ""
    };

    if (!text || text.trim().length === 0) {
        result.error = "No output from claude CLI";
        return result;
    }

    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].trim().match(LIMIT_LINE);
        if (!match) {
            continue;
        }

        const entry = {
            label: match[1].trim(),
            percent: parseInt(match[2], 10),
            resets: match[3] ? match[3].trim() : ""
        };

        if (entry.label === "session") {
            result.session = entry;
        } else if (entry.label === "week (all models)" || entry.label === "week") {
            result.week = entry;
        } else {
            result.extraLimits.push(entry);
        }
    }

    if (!result.session && !result.week && result.extraLimits.length === 0) {
        result.error = "Could not parse usage output";
        return result;
    }

    result.ok = true;
    return result;
}
