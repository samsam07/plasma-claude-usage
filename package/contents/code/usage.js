/*
 * Usage logic for the Claude Usage plasmoid.
 *
 * Deliberately free of QML types so it can be exercised under gjs — see
 * tests/test-usage.js. The input is the response of
 * GET https://api.anthropic.com/api/oauth/usage, the endpoint behind Claude
 * Code's /usage screen, authorised with Claude Code's own sign-in.
 */

// Claude Code's theme colours — the `claude`, `warning` and `error` entries of
// the dark and light themes it ships. Its /usage bars themselves are a fixed
// blue, so these are the colours it uses for the same three states elsewhere.
var COLORS = {
    dark: { normal: "#d77757", warning: "#ffc107", critical: "#ff6b80" },
    light: { normal: "#d77757", warning: "#966c1e", critical: "#ab2b3f" }
};

var LEVELS = ["normal", "warning", "critical"];

// Claude decides when to warn on its servers, so there is no client-side
// threshold to copy; these are the widget's own defaults.
var DEFAULT_WARNING_PERCENT = 75;
var DEFAULT_CRITICAL_PERCENT = 90;

// The session window first, then the weekly ones.
var KIND_ORDER = { session: 0, weekly: 1, weeklyModel: 2 };

// ------------------------------------------------------------- credentials

/*
 * Reads Claude Code's ~/.claude/.credentials.json. Only a claude.ai
 * subscription sign-in carries plan limits; an API-key login has no
 * claudeAiOauth entry at all, and yields null.
 */
function parseCredentials(text) {
    var data = JSON.parse(text);
    var oauth = data ? data.claudeAiOauth : null;
    if (!oauth || typeof oauth.accessToken !== "string" || oauth.accessToken === "") {
        return null;
    }
    return {
        accessToken: oauth.accessToken,
        expiresAt: typeof oauth.expiresAt === "number" ? oauth.expiresAt : 0,
        plan: planName(oauth.subscriptionType, oauth.rateLimitTier),
        account: typeof data.organizationUuid === "string" ? data.organizationUuid : ""
    };
}

// "max" with a "default_claude_max_20x" tier reads "Max 20x".
function planName(subscriptionType, rateLimitTier) {
    var type = String(subscriptionType || "").toLowerCase();
    if (type === "") {
        return "";
    }
    if (type === "max") {
        var multiplier = /(\d+)x$/.exec(String(rateLimitTier || ""));
        return multiplier ? "Max " + multiplier[1] + "x" : "Max";
    }
    return type.charAt(0).toUpperCase() + type.slice(1);
}

// ------------------------------------------------------------------ parsing

// The API writes microseconds ("…13:00:00.335842+00:00"); not every JS engine
// accepts more than three fractional digits.
function parseTime(text) {
    if (typeof text !== "string" || text === "") {
        return 0;
    }
    var ms = Date.parse(text.replace(/(\.\d{3})\d+/, "$1"));
    return isNaN(ms) ? 0 : ms;
}

function limitKey(kind, model) {
    return model ? kind + ":" + model.toLowerCase() : kind;
}

// The flat five_hour / seven_day objects — the numbers Claude Code prints.
function fromWindow(kind, model, window) {
    if (!window || typeof window.utilization !== "number") {
        return null;
    }
    return {
        key: limitKey(kind, model),
        kind: kind,
        model: model,
        percent: window.utilization,
        resetsAt: parseTime(window.resets_at),
        severity: "",
        locked: !!window.locked_reason
    };
}

// An entry of the newer `limits` array, which also carries a severity.
function fromLimitsEntry(entry) {
    if (!entry || typeof entry.percent !== "number") {
        return null;
    }
    var kind;
    var model = "";
    if (entry.kind === "session") {
        kind = "session";
    } else if (entry.kind === "weekly_all") {
        kind = "weekly";
    } else if (entry.kind === "weekly_scoped" && entry.scope && entry.scope.model
               && typeof entry.scope.model.display_name === "string") {
        kind = "weeklyModel";
        model = entry.scope.model.display_name;
    } else {
        // Anything else has no wording we could give it.
        return null;
    }
    return {
        key: limitKey(kind, model),
        kind: kind,
        model: model,
        percent: entry.percent,
        resetsAt: parseTime(entry.resets_at),
        severity: typeof entry.severity === "string" ? entry.severity : "",
        locked: false
    };
}

var CURRENCY_SYMBOLS = { USD: "$", EUR: "€", GBP: "£" };

function moneyText(money) {
    if (!money || typeof money.amount_minor !== "number") {
        return "";
    }
    var exponent = typeof money.exponent === "number" ? money.exponent : 2;
    var amount = (money.amount_minor / Math.pow(10, exponent)).toFixed(exponent);
    var symbol = CURRENCY_SYMBOLS[money.currency];
    return symbol ? symbol + amount : (amount + " " + (money.currency || "")).trim();
}

// Usage credits — paid usage past the plan limits. Null unless switched on.
function parseCredits(json) {
    var spend = json.spend;
    if (spend && spend.enabled) {
        return {
            used: moneyText(spend.used),
            limit: moneyText(spend.limit),
            percent: typeof spend.percent === "number" ? spend.percent : null,
            severity: typeof spend.severity === "string" ? spend.severity : ""
        };
    }
    var extra = json.extra_usage;
    if (extra && extra.is_enabled) {
        return {
            used: "",
            limit: "",
            percent: typeof extra.utilization === "number" ? extra.utilization : null,
            severity: ""
        };
    }
    return null;
}

/*
 * The flat windows give the exact figures Claude Code shows, so they go in
 * first; the `limits` array then adds its severity to those and contributes
 * any per-model weekly limits the flat fields do not have.
 */
function parse(responseText) {
    var json = JSON.parse(responseText);
    if (!json || typeof json !== "object") {
        throw new Error("Unexpected usage response");
    }

    var limits = [];
    var byKey = {};

    function add(limit) {
        if (!limit) {
            return;
        }
        var existing = byKey[limit.key];
        if (existing) {
            if (limit.severity) {
                existing.severity = limit.severity;
            }
            if (!existing.resetsAt) {
                existing.resetsAt = limit.resetsAt;
            }
            return;
        }
        // "Sonnet" from seven_day_sonnet and "Sonnet 4.5" from the limits
        // array are the same bar.
        if (limit.kind === "weeklyModel") {
            for (var i = 0; i < limits.length; i++) {
                var other = limits[i];
                if (other.kind === "weeklyModel" && sameModel(other.model, limit.model)) {
                    if (limit.severity) {
                        other.severity = limit.severity;
                    }
                    return;
                }
            }
        }
        byKey[limit.key] = limit;
        limits.push(limit);
    }

    add(fromWindow("session", "", json.five_hour));
    add(fromWindow("weekly", "", json.seven_day));
    add(fromWindow("weeklyModel", "Sonnet", json.seven_day_sonnet));
    add(fromWindow("weeklyModel", "Opus", json.seven_day_opus));
    if (Array.isArray(json.limits)) {
        json.limits.forEach(function (entry) {
            add(fromLimitsEntry(entry));
        });
    }

    // Stable by construction, whatever the engine's sort does.
    limits = limits
        .map(function (limit, index) { return { limit: limit, index: index }; })
        .sort(function (a, b) {
            return (KIND_ORDER[a.limit.kind] - KIND_ORDER[b.limit.kind]) || (a.index - b.index);
        })
        .map(function (pair) { return pair.limit; });

    return { limits: limits, credits: parseCredits(json), breakdown: parseBreakdown(json) };
}

/*
 * This week's usage split by product — Claude Code, Chats, Cowork, Other — as
 * shares of the week's total, the way claude.ai's usage page lists them.
 */
function parseBreakdown(json) {
    var breakdown = json.seven_day_breakdown;
    if (!breakdown || !Array.isArray(breakdown.rows)) {
        return null;
    }
    var rows = breakdown.rows
        .filter(function (row) {
            return row && typeof row.percent === "number" && typeof row.display_name === "string";
        })
        .map(function (row) {
            return {
                key: typeof row.key === "string" ? row.key : row.display_name,
                name: row.display_name,
                percent: row.percent
            };
        });
    return rows.length > 0 ? rows : null;
}

function sameModel(a, b) {
    a = a.toLowerCase();
    b = b.toLowerCase();
    return a.indexOf(b) === 0 || b.indexOf(a) === 0;
}

// ------------------------------------------------------------------- levels

/*
 * The API's severity strings are not documented; only "normal" has been seen.
 * Read them by intent, and treat an unrecognised one as a warning rather than
 * ignoring it.
 */
function severityRank(severity) {
    var s = String(severity || "").toLowerCase();
    if (s === "" || /^(normal|ok|none|low|info)$/.test(s)) {
        return 0;
    }
    if (/warn|approach|elevated|medium|moderate/.test(s)) {
        return 1;
    }
    if (/crit|exceed|reach|reject|block|lock|high|error|severe|exhaust/.test(s)) {
        return 2;
    }
    return 1;
}

function levelFor(percent, severity, warningPercent, criticalPercent) {
    var rank = percent >= criticalPercent ? 2 : (percent >= warningPercent ? 1 : 0);
    return LEVELS[Math.max(rank, severityRank(severity))];
}

function colorFor(level, dark) {
    var palette = dark ? COLORS.dark : COLORS.light;
    return palette[level] || palette.normal;
}

/*
 * What the widget draws, as of `now`. A window whose reset time has passed is
 * back at zero even before the next fetch confirms it, so cached figures never
 * show usage that has already been forgiven.
 */
function rows(data, now, warningPercent, criticalPercent) {
    if (!data) {
        return [];
    }
    return data.limits.map(function (limit) {
        var hasReset = limit.resetsAt > 0 && now >= limit.resetsAt;
        var percent = hasReset ? 0 : limit.percent;
        var level = hasReset
            ? "normal"
            : levelFor(percent, limit.locked ? "locked" : limit.severity, warningPercent, criticalPercent);
        return {
            key: limit.key,
            kind: limit.kind,
            model: limit.model,
            percent: percent,
            ratio: Math.max(0, Math.min(1, percent / 100)),
            level: level,
            resetsAt: limit.resetsAt,
            hasReset: hasReset
        };
    });
}

/*
 * The row the ring shows: "session", "weekly", or "closest" — the most severe
 * level, then the highest percentage, earlier rows winning ties.
 */
function pickRing(rowList, mode) {
    if (!rowList || rowList.length === 0) {
        return null;
    }
    if (mode === "closest") {
        var best = rowList[0];
        for (var i = 1; i < rowList.length; i++) {
            var row = rowList[i];
            var rankDiff = LEVELS.indexOf(row.level) - LEVELS.indexOf(best.level);
            if (rankDiff > 0 || (rankDiff === 0 && row.percent > best.percent)) {
                best = row;
            }
        }
        return best;
    }
    var kind = mode === "weekly" ? "weekly" : "session";
    for (var j = 0; j < rowList.length; j++) {
        if (rowList[j].kind === kind) {
            return rowList[j];
        }
    }
    return rowList[0];
}

// ------------------------------------------------------------ session trend

/*
 * The service reports only the current window, so the widget keeps its own
 * history: one entry per session window, holding the window's reset time and
 * the highest percentage any fetch saw in it.
 */

var SESSION_MS = 5 * 3600000;
var TREND_DAYS = 7;

// Kept a day past the chart, so a window straddling its left edge survives.
var HISTORY_MS = (TREND_DAYS + 1) * 86400000;

// Successive fetches of one window disagree on its reset time by a fraction of
// a second ("12:59:59.838", then "13:00:00.335").
var SAME_WINDOW_MS = 10 * 60000;

function parseHistory(text) {
    var empty = { since: 0, windows: [] };
    try {
        var data = JSON.parse(text);
        if (!data || !Array.isArray(data.windows)) {
            return empty;
        }
        return {
            since: typeof data.since === "number" ? data.since : 0,
            windows: data.windows.filter(function (w) {
                return w && typeof w.resetsAt === "number" && typeof w.peak === "number";
            })
        };
    } catch (e) {
        return empty;
    }
}

// The current session's figure, if a session is under way.
function sessionSample(data) {
    if (!data) {
        return null;
    }
    for (var i = 0; i < data.limits.length; i++) {
        var limit = data.limits[i];
        if (limit.kind === "session") {
            return limit.resetsAt > 0 && limit.percent > 0
                ? { resetsAt: limit.resetsAt, percent: limit.percent }
                : null;
        }
    }
    return null;
}

// Returns a new history; the one passed in is left alone.
function recordSession(history, sample, now) {
    var windows = history.windows.filter(function (w) {
        return w.resetsAt > now - HISTORY_MS;
    });
    var since = history.since > 0 ? history.since : now;
    if (!sample) {
        return { since: since, windows: windows };
    }

    var merged = false;
    windows = windows.map(function (w) {
        if (Math.abs(w.resetsAt - sample.resetsAt) < SAME_WINDOW_MS) {
            merged = true;
            return { resetsAt: w.resetsAt, peak: Math.max(w.peak, sample.percent) };
        }
        return w;
    });
    if (!merged) {
        windows.push({ resetsAt: sample.resetsAt, peak: sample.percent });
    }
    windows.sort(function (a, b) { return a.resetsAt - b.resetsAt; });
    return { since: since, windows: windows };
}

/*
 * The chart: the last seven local days, today included, one bar per session
 * window placed at the time it ran. `days` holds each day's start, plus the end
 * of today. Walking the dates keeps days with a DST change the right length.
 */
function sessionTrend(history, now, warningPercent, criticalPercent) {
    var days = [];
    var date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - (TREND_DAYS - 1));
    for (var i = 0; i <= TREND_DAYS; i++) {
        days.push(date.getTime());
        date.setDate(date.getDate() + 1);
    }
    var from = days[0];
    var to = days[TREND_DAYS];

    var bars = [];
    var busiest = null;
    (history ? history.windows : []).forEach(function (w) {
        var start = w.resetsAt - SESSION_MS;
        if (w.resetsAt <= from || start >= to) {
            return;
        }
        var bar = {
            start: start,
            end: w.resetsAt,
            // Where it is drawn: clipped to the chart.
            left: Math.max(start, from),
            right: Math.min(w.resetsAt, to),
            peak: w.peak,
            ratio: Math.max(0, Math.min(1, w.peak / 100)),
            level: levelFor(w.peak, "", warningPercent, criticalPercent),
            current: now < w.resetsAt
        };
        if (!busiest || bar.peak > busiest.peak) {
            busiest = bar;
        }
        bars.push(bar);
    });

    return { from: from, to: to, days: days, bars: bars, busiest: busiest };
}

// --------------------------------------------------------------- formatting

// Claude Code floors: 99.6% used still reads "99%".
function percentText(percent) {
    return Math.floor(percent) + "%";
}

/*
 * "2 h 13 min", "45 min", "3 d 4 h". Minutes round up, so a reset 20 seconds
 * away reads "1 min" rather than "0 min".
 */
function formatDuration(ms, units) {
    units = units || { day: "d", hour: "h", minute: "min" };
    var total = Math.max(0, Math.ceil(ms / 60000));
    var days = Math.floor(total / 1440);
    var hours = Math.floor((total % 1440) / 60);
    var minutes = total % 60;
    if (days > 0) {
        return days + " " + units.day + (hours ? " " + hours + " " + units.hour : "");
    }
    if (hours > 0) {
        return hours + " " + units.hour + (minutes ? " " + minutes + " " + units.minute : "");
    }
    return minutes + " " + units.minute;
}
