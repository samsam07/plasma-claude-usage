/*
 * Assertions for contents/code/usage.js. Concatenated after usage.js by
 * run-tests.sh and executed with gjs.
 *
 * fixture-usage.json is a real response captured from the endpoint, so its
 * figures were read off the service rather than derived from this code.
 * fixture-near-limit.json is synthetic; see the comment inside it.
 */

const GLib = imports.gi.GLib;

let failures = 0;
let checks = 0;

function check(name, actual, expected) {
    checks += 1;
    const ok = String(actual) === String(expected);
    if (!ok) {
        failures += 1;
        print("  FAIL  " + name);
        print("        expected: " + expected);
        print("        actual:   " + actual);
    } else {
        print("  ok    " + name + "  ->  " + actual);
    }
}

function load(path) {
    const [, bytes] = GLib.file_get_contents(path);
    return new TextDecoder().decode(bytes);
}

const here = ARGV[0];
const WARN = DEFAULT_WARNING_PERCENT;
const CRIT = DEFAULT_CRITICAL_PERCENT;
const utc = Date.UTC;

print("\ncaptured response");
// Captured at 2026-09-17 09:07:54 UTC. Its product split — Claude Code 74%,
// Chats 26%, Cowork 0%, Other 0% — is what claude.ai's usage page showed that day.
let data = parse(load(here + "/fixture-usage.json"));
let now = utc(2026, 8, 17, 9, 7, 54);
let list = rows(data, now, WARN, CRIT);
check("two limits", list.length, 2);
check("session first", list[0].kind, "session");
check("session percent", percentText(list[0].percent), "26%");
check("session reset parses microseconds", new Date(list[0].resetsAt).toISOString(), "2026-09-17T12:59:59.838Z");
check("weekly percent", percentText(list[1].percent), "3%");
check("weekly reset", new Date(list[1].resetsAt).toISOString(), "2026-09-23T14:59:59.838Z");
check("levels are normal", list.map(r => r.level).join(","), "normal,normal");
check("no credits when switched off", data.credits, "null");
check("ring follows the session", pickRing(list, "session").kind, "session");
check("ring can follow the week", pickRing(list, "weekly").kind, "weekly");

print("\nusage by product");
check("products in the service's order", data.breakdown.map(r => r.name).join(","), "Claude Code,Chats,Cowork,Other");
check("shares", data.breakdown.map(r => r.percent).join(","), "74,26,0,0");
check("keys", data.breakdown[0].key, "claude_code");
check("absent breakdown", parse("{\"seven_day_breakdown\":null}").breakdown, "null");
check("malformed rows are dropped", parse(JSON.stringify({ seven_day_breakdown: { rows: [
    { key: "a", display_name: "A", percent: 60 }, { key: "b", percent: 40 }, null
] } })).breakdown.length, 1);

print("\nwindows that reset before the next fetch");
now = utc(2026, 8, 17, 13, 0, 1);
list = rows(data, now, WARN, CRIT);
check("session back to zero", list[0].percent, 0);
check("and marked as reset", list[0].hasReset, true);
check("weekly untouched", list[1].hasReset, false);

print("\nnear the limits (synthetic)");
data = parse(load(here + "/fixture-near-limit.json"));
now = utc(2026, 8, 17, 8, 14, 0);
list = rows(data, now, WARN, CRIT);
check("order", list.map(r => r.key).join(","), "session,weekly,weeklyModel:sonnet,weeklyModel:opus");
check("flat figure wins over the rounded one", list[0].percent, 92.4);
check("percent is floored", percentText(list[0].percent), "92%");
check("over the red threshold despite a normal severity", list[0].level, "critical");
check("server severity lifts 61% to yellow", list[1].level, "warning");
check("legacy Sonnet and 'Sonnet 4.5' are one bar", list.filter(r => r.kind === "weeklyModel").length, 2);
check("Opus comes from the limits array", list[3].model, "Opus");
check("unknown kinds are left out", list.some(r => r.key.indexOf("future") >= 0), false);
check("closest picks the critical one", pickRing(list, "closest").key, "session");
check("credits used", data.credits.used, "$12.34");
check("credits limit", data.credits.limit, "$50.00");
check("credits percent", percentText(data.credits.percent), "24%");

print("\nclosest prefers severity over a bigger number");
const mixed = [
    { key: "a", kind: "session", percent: 70, level: "normal" },
    { key: "b", kind: "weekly", percent: 60, level: "warning" }
];
check("warning at 60% beats normal at 70%", pickRing(mixed, "closest").key, "b");
check("ties keep the earlier row", pickRing([
    { key: "a", kind: "session", percent: 10, level: "normal" },
    { key: "b", kind: "weekly", percent: 10, level: "normal" }
], "closest").key, "a");
check("no rows, no ring", pickRing([], "session"), "null");

print("\nlevels");
check("below warning", levelFor(74.9, "", 75, 90), "normal");
check("at warning", levelFor(75, "", 75, 90), "warning");
check("at critical", levelFor(90, "normal", 75, 90), "critical");
check("custom thresholds", levelFor(55, "", 50, 80), "warning");
check("critical severity", levelFor(5, "critical", 75, 90), "critical");
check("unknown severity reads as a warning", levelFor(5, "mystery", 75, 90), "warning");
check("locked window", levelFor(5, "locked", 75, 90), "critical");

print("\ncolours — Claude Code's theme values");
check("dark normal", colorFor("normal", true), "#d77757");
check("dark warning", colorFor("warning", true), "#ffc107");
check("dark critical", colorFor("critical", true), "#ff6b80");
check("light warning", colorFor("warning", false), "#966c1e");
check("light critical", colorFor("critical", false), "#ab2b3f");

print("\ncredentials (synthetic)");
let creds = parseCredentials(JSON.stringify({
    claudeAiOauth: {
        accessToken: "sk-ant-oat01-test", refreshToken: "sk-ant-ort01-test",
        expiresAt: 1789661223001, scopes: ["user:profile"],
        subscriptionType: "max", rateLimitTier: "default_claude_max_20x"
    },
    organizationUuid: "00000000-0000-0000-0000-000000000000"
}));
check("token", creds.accessToken, "sk-ant-oat01-test");
check("expiry", creds.expiresAt, 1789661223001);
check("plan with multiplier", creds.plan, "Max 20x");
check("account", creds.account, "00000000-0000-0000-0000-000000000000");
check("refresh token is not carried", creds.refreshToken, "undefined");
check("pro plan", planName("pro", "default_claude_ai"), "Pro");
check("API-key login has no subscription", parseCredentials("{\"primaryApiKey\":\"x\"}"), "null");

print("\nsession history");
const hour = 3600000;
let history = parseHistory("not json");
check("garbage history is empty", history.windows.length, 0);
now = utc(2026, 8, 17, 9, 7, 54);
const sample = sessionSample(parse(load(here + "/fixture-usage.json")));
check("sample percent", sample.percent, 26);
history = recordSession(history, sample, now);
check("first record starts the history", history.since, now);
check("one window", history.windows.length, 1);
// The same window again, with the reset time a fraction of a second off.
history = recordSession(history, { resetsAt: utc(2026, 8, 17, 13, 0, 0) + 335, percent: 31 }, now + 10 * 60000);
check("jittered reset time is the same window", history.windows.length, 1);
check("peak rises", history.windows[0].peak, 31);
history = recordSession(history, { resetsAt: utc(2026, 8, 17, 12, 59, 59) + 838, percent: 12 }, now + 20 * 60000);
check("peak never falls", history.windows[0].peak, 31);
check("since is kept", history.since, now);
history = recordSession(history, { resetsAt: utc(2026, 8, 16, 20, 0, 0), percent: 95 }, now);
check("an earlier window is added in order", history.windows.map(w => new Date(w.resetsAt).getUTCHours()).join(","), "20,12");
check("no session, no sample", sessionSample({ limits: [{ kind: "session", percent: 0, resetsAt: 0 }] }), "null");
history = recordSession({ since: 1, windows: [{ resetsAt: now - 9 * 24 * hour, peak: 50 }] }, null, now);
check("windows past eight days are dropped", history.windows.length, 0);
check("round-trips through JSON", parseHistory(JSON.stringify({ since: 5, windows: [{ resetsAt: 7, peak: 8 }] })).windows[0].peak, 8);

print("\nseven-day trend (TZ=UTC)");
history = { since: 0, windows: [
    { resetsAt: utc(2026, 8, 11, 2, 0, 0), peak: 40 },   // started the day before the chart
    { resetsAt: utc(2026, 8, 10, 12, 0, 0), peak: 99 },  // entirely before it
    { resetsAt: utc(2026, 8, 15, 19, 0, 0), peak: 92 },
    { resetsAt: utc(2026, 8, 16, 15, 0, 0), peak: 76 },
    { resetsAt: utc(2026, 8, 17, 13, 0, 0), peak: 31 }   // under way
] };
let trend = sessionTrend(history, utc(2026, 8, 17, 9, 7, 54), WARN, CRIT);
check("seven days plus the end of today", trend.days.length, 8);
check("starts six days back at midnight", new Date(trend.from).toISOString(), "2026-09-11T00:00:00.000Z");
check("ends at the end of today", new Date(trend.to).toISOString(), "2026-09-18T00:00:00.000Z");
check("windows outside the chart are left out", trend.bars.length, 4);
check("a straddling window is clipped", new Date(trend.bars[0].left).toISOString(), "2026-09-11T00:00:00.000Z");
check("but keeps its real start", new Date(trend.bars[0].start).toISOString(), "2026-09-10T21:00:00.000Z");
check("levels", trend.bars.map(b => b.level).join(","), "normal,critical,warning,normal");
check("only the last is under way", trend.bars.map(b => b.current).join(","), "false,false,false,true");
check("busiest", trend.busiest.peak, 92);
check("empty history", sessionTrend(null, utc(2026, 8, 17, 9, 0, 0), WARN, CRIT).bars.length, 0);
check("empty history has no busiest", sessionTrend(null, utc(2026, 8, 17, 9, 0, 0), WARN, CRIT).busiest, "null");

print("\ndurations");
check("minutes", formatDuration(45 * 60000), "45 min");
check("rounds up", formatDuration(20000), "1 min");
check("hours and minutes", formatDuration((2 * 60 + 13) * 60000), "2 h 13 min");
check("whole hours", formatDuration(3 * 3600000), "3 h");
check("days", formatDuration((3 * 24 + 4) * 3600000), "3 d 4 h");
check("custom units", formatDuration(90 * 60000, { day: "j", hour: "h", minute: "mn" }), "1 h 30 mn");

print("\n" + (failures ? "FAILED " + failures + " of " + checks : "all " + checks + " checks passed"));
if (failures) {
    imports.system.exit(1);
}
