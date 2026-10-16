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
 * history, built from every successful fetch:
 *   windows       one entry per session window: its reset time and the
 *                 highest percentage any fetch saw in it, for the bars
 *   samples       each fetch's figure in the window ending at sampleWindow,
 *                 for the session chart and its pace
 *   hours         how many percentage points of the session limit went in
 *                 each local hour, from hoursSince on, for the heatmap
 */

var SESSION_MS = 5 * 3600000;
var WEEK_MS = 7 * 86400000;
var HOUR_MS = 3600000;
var TREND_DAYS = 7;

// Kept a day past the chart, so a window straddling its left edge survives.
var HISTORY_MS = (TREND_DAYS + 1) * 86400000;

// Successive fetches of one window disagree on its reset time by a fraction of
// a second ("12:59:59.838", then "13:00:00.335").
var SAME_WINDOW_MS = 10 * 60000;

function emptyHistory() {
    return { since: 0, windows: [], sampleWindow: 0, samples: [], hoursSince: 0, hours: [] };
}

function parseHistory(text) {
    var history = emptyHistory();
    try {
        var data = JSON.parse(text);
        if (!data || !Array.isArray(data.windows)) {
            return history;
        }
        history.since = typeof data.since === "number" ? data.since : 0;
        history.windows = data.windows.filter(function (w) {
            return w && typeof w.resetsAt === "number" && typeof w.peak === "number";
        });
        // Histories from before samples and hours were kept have neither.
        if (typeof data.sampleWindow === "number" && Array.isArray(data.samples)) {
            history.sampleWindow = data.sampleWindow;
            history.samples = data.samples.filter(function (s) {
                return s && typeof s.t === "number" && typeof s.percent === "number";
            });
        }
        if (typeof data.hoursSince === "number" && Array.isArray(data.hours)) {
            history.hoursSince = data.hoursSince;
            history.hours = data.hours.filter(function (h) {
                return h && typeof h.start === "number" && typeof h.used === "number";
            });
        }
    } catch (e) {
        // An unreadable history starts again.
    }
    return history;
}

function hourStart(ms) {
    var date = new Date(ms);
    date.setMinutes(0, 0, 0);
    return date.getTime();
}

/*
 * Adds `amount` to the hours from `from` to `to`, in proportion to how much of
 * that time each hour holds. With no time between them, all of it goes to the
 * hour of `to`. Returns a new list, oldest hour first.
 */
function spreadOverHours(hours, from, to, amount) {
    var list = hours.map(function (h) { return { start: h.start, used: h.used }; });
    if (!(amount > 0)) {
        return list;
    }
    function add(start, value) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].start === start) {
                list[i].used = Math.round((list[i].used + value) * 1000) / 1000;
                return;
            }
        }
        list.push({ start: start, used: Math.round(value * 1000) / 1000 });
    }
    if (to <= from) {
        add(hourStart(to), amount);
    } else {
        var t = from;
        while (t < to) {
            var start = hourStart(t);
            var next = Math.min(to, start + HOUR_MS);
            add(start, amount * (next - t) / (to - from));
            t = next;
        }
    }
    list.sort(function (a, b) { return a.start - b.start; });
    return list;
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
    var hours = (history.hours || []).filter(function (h) {
        return h.start > now - HISTORY_MS;
    });
    var next = {
        since: since,
        windows: windows,
        sampleWindow: history.sampleWindow || 0,
        samples: history.samples || [],
        hoursSince: history.hoursSince > 0 ? history.hoursSince : now,
        hours: hours
    };
    if (!sample) {
        return next;
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
    next.windows = windows;

    // A new window starts its samples afresh, from 0% when it began.
    if (next.sampleWindow === 0 || Math.abs(next.sampleWindow - sample.resetsAt) >= SAME_WINDOW_MS) {
        next.sampleWindow = sample.resetsAt;
        next.samples = [];
    }
    var start = next.sampleWindow - SESSION_MS;
    var last = next.samples.length > 0
        ? next.samples[next.samples.length - 1]
        : { t: start, percent: 0 };
    // What went since the last figure is spread over the time between them,
    // as nothing says when within it.
    var from = Math.max(start, last.t);
    next.hours = spreadOverHours(hours, from, now, sample.percent - last.percent);
    if (!(history.hoursSince > 0)) {
        next.hoursSince = Math.min(from, now);
    }
    next.samples = next.samples.concat([{ t: now, percent: sample.percent }]);
    return next;
}

// The start of each of the last seven local days, today last, plus the end of
// today. Walking the dates keeps days with a DST change the right length.
function trendDays(now) {
    var days = [];
    var date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - (TREND_DAYS - 1));
    for (var i = 0; i <= TREND_DAYS; i++) {
        days.push(date.getTime());
        date.setDate(date.getDate() + 1);
    }
    return days;
}

/*
 * The bars: the last seven local days, today included, one bar per session
 * window placed at the time it ran.
 */
function sessionTrend(history, now, warningPercent, criticalPercent) {
    var days = trendDays(now);
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

/*
 * The heatmap: the same seven days, one row each, today last, with how much
 * of the session limit went in each of their 24 hours. `ratio` scales each
 * hour against the busiest one, so the busiest is always the strongest colour.
 */
function usageHeatmap(history, now) {
    var days = trendDays(now);
    var used = {};
    var max = 0;
    (history && history.hours ? history.hours : []).forEach(function (h) {
        used[h.start] = h.used;
        max = Math.max(max, h.used);
    });
    var since = history && history.hoursSince > 0 ? history.hoursSince : now;
    var rows = [];
    for (var d = 0; d < TREND_DAYS; d++) {
        var cells = [];
        for (var hour = 0; hour < 24; hour++) {
            var date = new Date(days[d]);
            date.setHours(hour);
            var start = date.getTime();
            var value = used[start] || 0;
            cells.push({
                start: start,
                used: value,
                ratio: max > 0 ? value / max : 0,
                // Before recording began nothing is known, which is not the
                // same as nothing used.
                known: start + HOUR_MS > since && start <= now
            });
        }
        rows.push({ start: days[d], cells: cells });
    }
    return { rows: rows, max: max };
}

/*
 * The session under way, for its chart: the figures fetched in it, starting
 * from 0% when it began, and where the rate of the last hour leads. A line
 * through only a few minutes swings wildly, so until the figures span
 * PACE_MIN_MS the pace stays unknown (null).
 */
var PACE_SPAN_MS = HOUR_MS;
var PACE_MIN_MS = 15 * 60000;

function sessionProgress(history, row, fetchedAt, now) {
    if (!row || row.kind !== "session" || row.resetsAt <= 0 || row.hasReset) {
        return null;
    }
    var end = row.resetsAt;
    var start = end - SESSION_MS;
    var points = [{ t: start, percent: 0 }];
    if (history && history.sampleWindow > 0 && Math.abs(history.sampleWindow - end) < SAME_WINDOW_MS) {
        history.samples.forEach(function (s) {
            if (s.t > start && s.t <= now) {
                points.push({ t: s.t, percent: s.percent });
            }
        });
    }
    // The figure on screen may be newer than the last one recorded.
    var newest = points[points.length - 1];
    if (newest.percent !== row.percent && fetchedAt > newest.t) {
        newest = { t: Math.min(fetchedAt, now), percent: row.percent };
        points.push(newest);
    }

    var pace = null;
    if (row.percent >= 100) {
        pace = { reached: true, rate: 0, limitAt: 0, atReset: 100 };
    } else {
        // The last figure at least an hour older than the newest, or failing
        // that the start of the window.
        var base = points[0];
        for (var i = points.length - 2; i >= 0; i--) {
            if (points[i].t <= newest.t - PACE_SPAN_MS) {
                base = points[i];
                break;
            }
        }
        var span = newest.t - base.t;
        if (span >= PACE_MIN_MS) {
            var rate = Math.max(0, newest.percent - base.percent) / span;
            var limitAt = rate > 0 ? newest.t + (100 - newest.percent) / rate : 0;
            pace = {
                reached: false,
                rate: rate,
                // When the limit would be hit, if before the reset; 0 if not.
                limitAt: limitAt > 0 && limitAt < end ? limitAt : 0,
                atReset: Math.min(100, newest.percent + rate * (end - newest.t))
            };
        }
    }
    return { start: start, end: end, points: points, newest: newest, pace: pace };
}

/*
 * A weekly limit against the week gone by: `elapsed` is the share of the
 * week past, and a limit used faster than that is ahead of pace. At its
 * average rate since the week began it then runs out at `outAt`, before the
 * reset. In the first hours of a week a few messages would read as far ahead,
 * so the pace is only `known` after WEEK_PACE_MIN_MS.
 */
var WEEK_PACE_MIN_MS = 6 * HOUR_MS;

function weekPace(row, now) {
    if (!row || row.resetsAt <= 0 || row.hasReset) {
        return null;
    }
    var start = row.resetsAt - WEEK_MS;
    var elapsed = Math.max(0, Math.min(1, (now - start) / WEEK_MS));
    var known = now - start >= WEEK_PACE_MIN_MS;
    var ahead = known && row.percent > elapsed * 100 && row.percent < 100;
    return {
        elapsed: elapsed,
        known: known,
        ahead: ahead,
        outAt: ahead ? start + (now - start) * 100 / row.percent : 0
    };
}

// The split bar's shares, in the service's order, and the names of products
// with none, which share a single label.
function productSplit(breakdown) {
    var list = breakdown || [];
    return {
        shares: list.filter(function (p) { return p.percent > 0; }),
        unused: list.filter(function (p) { return !(p.percent > 0); }).map(function (p) { return p.name; })
    };
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

// ------------------------------------------------------------ sessions

/*
 * Running Claude Code sessions, from the files it keeps in ~/.claude/sessions,
 * one per process. The widget's reader prints $HOME, then for each file whose
 * process still exists that process's start time and the file, as
 *   HOME RS start US json RS start US json RS ...
 * (RS = \x1e, US = \x1f). A file is only kept when the start time matches the
 * procStart it records, so a reused process id does not resurrect a session.
 * Claude Code writes the same files for its background jobs and for spare
 * processes it starts ahead of need; only sessions someone opened are kept.
 */
function parseSessions(text) {
    var records = String(text || "").split("\x1e");
    var home = records.shift() || "";
    var list = [];
    records.forEach(function (record) {
        var cut = record.indexOf("\x1f");
        if (cut < 0) {
            return;
        }
        var liveStart = record.slice(0, cut).trim();
        var json;
        try {
            json = JSON.parse(record.slice(cut + 1));
        } catch (e) {
            return;
        }
        if (!json || typeof json !== "object") {
            return;
        }
        if (json.procStart !== undefined && String(json.procStart) !== liveStart) {
            return;
        }
        // Files from before Claude Code recorded a kind are interactive.
        if ((json.kind !== undefined && json.kind !== "interactive") || json.spare || json.parkedJobId) {
            return;
        }
        var cwd = typeof json.cwd === "string" ? json.cwd : "";
        list.push({
            name: typeof json.name === "string" && json.name !== "" ? json.name : folderName(cwd),
            folder: homeRelative(cwd, home),
            startedAt: Number(json.startedAt) || 0,
            // When it last started or finished a task.
            lastActive: Number(json.statusUpdatedAt) || Number(json.updatedAt) || Number(json.startedAt) || 0,
            status: typeof json.status === "string" ? json.status : ""
        });
    });
    // Busy ones first, then the most recently active.
    list.sort(function (a, b) {
        var busy = (b.status === "busy") - (a.status === "busy");
        return busy !== 0 ? busy : b.lastActive - a.lastActive;
    });
    return list;
}

function folderName(path) {
    var parts = String(path).split("/").filter(function (part) { return part !== ""; });
    return parts.length > 0 ? parts[parts.length - 1] : String(path);
}

function homeRelative(path, home) {
    home = String(home || "").replace(/\/+$/, "");
    if (home !== "" && (path === home || path.indexOf(home + "/") === 0)) {
        return "~" + path.slice(home.length);
    }
    return path;
}
