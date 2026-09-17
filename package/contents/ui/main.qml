/*
 * Claude Usage — a Plasma 6 panel applet.
 *
 * Shows how much of the Claude plan's session and weekly limits are used, from
 * the endpoint behind Claude Code's /usage screen, authorised with Claude
 * Code's own sign-in. The widget only ever reads that sign-in. It never
 * refreshes or rewrites it, so it cannot log Claude Code out.
 */

import QtQuick
import QtQuick.LocalStorage

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

import "../code/usage.js" as Usage

PlasmoidItem {
    id: root

    readonly property string endpoint: "https://api.anthropic.com/api/oauth/usage"
    readonly property string usagePage: "https://claude.ai/settings/usage"
    readonly property string credentialsPath: Plasmoid.configuration.credentialsPath
    readonly property int warningPercent: Plasmoid.configuration.warningPercent
    readonly property int criticalPercent: Math.max(warningPercent, Plasmoid.configuration.criticalPercent)

    // Parsed usage; null until the cache or the network provides some.
    property var usage: null
    property string plan: ""
    property string account: ""

    // Held only in memory, and only between reading the file and the request.
    property string token: ""

    // unknown | ok | missing | expired | denied
    property string authState: "unknown"

    property bool loading: false
    property bool stale: false
    property string errorText: ""
    property double lastFetch: 0

    // Grows on consecutive failures; cleared by the next success.
    property int retryDelay: 0

    // The clock the bindings below are evaluated against; advanced each minute.
    property double now: Date.now()

    readonly property bool hasData: usage !== null
    readonly property var rows: Usage.rows(usage, now, warningPercent, criticalPercent)
    readonly property var ring: Usage.pickRing(rows, Plasmoid.configuration.ringLimit)
    readonly property var credits: hasData ? usage.credits : null
    readonly property var breakdown: hasData ? usage.breakdown : null

    // Peak of each session window, as recorded by this widget; see recordSession().
    property var sessionHistory: ({ since: 0, windows: [] })
    readonly property var trend: Usage.sessionTrend(sessionHistory, now, warningPercent, criticalPercent)
    readonly property string lastFetchText: lastFetch > 0
        ? Qt.formatTime(new Date(lastFetch), Qt.locale(), Locale.ShortFormat)
        : ""

    readonly property var durationUnits: ({
        day: i18nc("abbreviated days", "d"),
        hour: i18nc("abbreviated hours", "h"),
        minute: i18nc("abbreviated minutes", "min")
    })

    // The full popup on the desktop. In a panel it must stay unset rather than
    // name compactRepresentation: the system tray only opens the popup of an
    // applet with no preferred representation, and ignores clicks on any other.
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        || Plasmoid.formFactor === PlasmaCore.Types.Vertical

    preferredRepresentation: inPanel ? null : fullRepresentation

    Plasmoid.icon: "com.github.samsam07.claudeusage"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.busy: loading && !hasData

    toolTipMainText: i18n("Claude Usage")
    toolTipSubText: {
        if (!hasData) {
            return errorText !== "" ? errorText : i18n("Loading usage…");
        }
        var lines = rows.map(function (row) {
            var line = i18nc("limit name: percentage used", "%1: %2", titleFor(row), Usage.percentText(row.percent));
            var reset = resetText(row);
            return reset !== "" ? line + " · " + reset : line;
        });
        if (stale) {
            lines.push("⚠ " + (errorText !== "" ? errorText : i18n("Showing usage from %1", lastFetchText)));
        }
        return lines.join("\n");
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Usage")
            icon.name: "view-refresh"
            enabled: !root.loading
            onTriggered: root.refresh()
        },
        PlasmaCore.Action {
            text: i18n("Open Usage on claude.ai")
            icon.name: "internet-web-browser"
            onTriggered: Qt.openUrlExternally(root.usagePage)
        }
    ]

    compactRepresentation: CompactRepresentation { applet: root }
    fullRepresentation: FullRepresentation { applet: root }

    // ------------------------------------------------------------- wording

    function titleFor(row) {
        if (!row) {
            return "";
        }
        switch (row.kind) {
        case "session":
            return i18n("Current session");
        case "weekly":
            return i18n("Current week (all models)");
        default:
            return i18nc("%1 is a model name, such as Sonnet", "Current week (%1)", row.model);
        }
    }

    function resetText(row) {
        if (!row || row.resetsAt <= 0) {
            return "";
        }
        var at = new Date(row.resetsAt);
        var clock = Qt.formatTime(at, Qt.locale(), Locale.ShortFormat);
        if (row.hasReset) {
            return i18n("Reset at %1", clock);
        }
        var remaining = row.resetsAt - now;
        if (remaining < 24 * 3600000) {
            return i18n("Resets in %1", Usage.formatDuration(remaining, durationUnits));
        }
        return i18nc("%1 is a day such as 'Wed 23 Sep', %2 a time", "Resets %1, %2",
                     Qt.locale().toString(at, "ddd d MMM"), clock);
    }

    // "Thu 17 Sep, 08:00–13:00" for one session window of the trend.
    function sessionWindowText(bar) {
        var start = new Date(bar.start);
        var end = new Date(bar.end);
        return i18nc("day, then start and end times", "%1, %2–%3",
                     Qt.locale().toString(start, "ddd d MMM"),
                     Qt.formatTime(start, Qt.locale(), Locale.ShortFormat),
                     Qt.formatTime(end, Qt.locale(), Locale.ShortFormat));
    }

    // Claude Code ships separate palettes for dark and light backgrounds.
    function colorFor(level, background) {
        var dark = Kirigami.ColorUtils.brightnessForColor(background) === Kirigami.ColorUtils.Dark;
        return Usage.colorFor(level, dark);
    }

    // ---------------------------------------------------------------- cache

    /*
     * One row per account, so the ring is right from the moment plasmashell
     * starts, and so a lapsed sign-in still shows the last known figures —
     * which rows() zeroes once their windows reset.
     */
    function database() {
        return LocalStorage.openDatabaseSync("com.github.samsam07.claudeusage", "1.0",
                                             "Claude Usage cache", 100000);
    }

    function readCache() {
        try {
            var payload = null;
            var fetchedAt = 0;
            database().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS usage"
                            + " (account TEXT PRIMARY KEY, payload TEXT, fetchedAt REAL)");
                var rs = tx.executeSql("SELECT payload, fetchedAt FROM usage WHERE account = ?", [account]);
                if (rs.rows.length > 0) {
                    payload = rs.rows.item(0).payload;
                    fetchedAt = rs.rows.item(0).fetchedAt;
                }
            });
            if (payload) {
                applyPayload(payload, fetchedAt);
                stale = (Date.now() - fetchedAt) > poll.interval;
            }
        } catch (e) {
            console.warn("claudeusage: could not read cache:", e);
        }
    }

    function writeCache(payload, fetchedAt) {
        try {
            database().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS usage"
                            + " (account TEXT PRIMARY KEY, payload TEXT, fetchedAt REAL)");
                tx.executeSql("INSERT OR REPLACE INTO usage (account, payload, fetchedAt) VALUES (?, ?, ?)",
                              [account, payload, fetchedAt]);
            });
        } catch (e) {
            console.warn("claudeusage: could not write cache:", e);
        }
    }

    /*
     * The usage service only reports the window in progress, so the seven-day
     * trend is built here: every successful fetch raises the current window's
     * recorded peak. Anything that happened while the widget was not running
     * is simply missing.
     */
    function readHistory() {
        var text = "";
        try {
            database().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS sessions (account TEXT PRIMARY KEY, history TEXT)");
                var rs = tx.executeSql("SELECT history FROM sessions WHERE account = ?", [account]);
                if (rs.rows.length > 0) {
                    text = rs.rows.item(0).history;
                }
            });
        } catch (e) {
            console.warn("claudeusage: could not read session history:", e);
        }
        sessionHistory = Usage.parseHistory(text);
    }

    function recordSession() {
        sessionHistory = Usage.recordSession(sessionHistory, Usage.sessionSample(usage), Date.now());
        try {
            database().transaction(function (tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS sessions (account TEXT PRIMARY KEY, history TEXT)");
                tx.executeSql("INSERT OR REPLACE INTO sessions (account, history) VALUES (?, ?)",
                              [account, JSON.stringify(sessionHistory)]);
            });
        } catch (e) {
            console.warn("claudeusage: could not write session history:", e);
        }
    }

    // ---------------------------------------------------------- credentials

    // Claude Code rewrites the file whenever it renews the sign-in, so it is
    // read afresh before every request rather than once at startup.
    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            root.credentialsRead(data["exit code"], data.stdout);
        }
    }

    function shellQuote(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'";
    }

    function readCommand() {
        var path = credentialsPath.trim();
        if (path === "~") {
            path = "\"$HOME\"";
        } else if (path.indexOf("~/") === 0) {
            path = "\"$HOME\"/" + shellQuote(path.slice(2));
        } else {
            path = shellQuote(path);
        }
        return "cat -- " + path;
    }

    function refresh() {
        if (loading) {
            return;
        }
        loading = true;
        reader.connectSource(readCommand());
    }

    function credentialsRead(exitCode, stdout) {
        var credentials = null;
        if (exitCode === 0) {
            try {
                credentials = Usage.parseCredentials(stdout);
            } catch (e) {
                console.warn("claudeusage: could not parse credentials:", e);
            }
        }

        if (!credentials) {
            loading = false;
            token = "";
            authState = "missing";
            errorText = exitCode === 0
                ? i18n("Claude Code is not signed in with a Claude subscription")
                : i18n("Claude Code is not signed in");
            markStale();
            return;
        }

        plan = credentials.plan;
        if (credentials.account !== account || !hasData) {
            account = credentials.account;
            usage = null;
            lastFetch = 0;
            readCache();
            readHistory();
        }

        if (credentials.expiresAt > 0 && Date.now() >= credentials.expiresAt) {
            loading = false;
            token = "";
            authState = "expired";
            errorText = i18n("Claude Code's sign-in has expired");
            markStale();
            return;
        }

        token = credentials.accessToken;
        fetchUsage();
    }

    // --------------------------------------------------------------- network

    property var pending: null

    function fetchUsage() {
        var request = new XMLHttpRequest();
        pending = request;

        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE || request !== pending) {
                return;
            }
            pending = null;
            watchdog.stop();
            loading = false;
            token = "";

            if (request.status === 200 && request.responseText) {
                var fetchedAt = Date.now();
                try {
                    applyPayload(request.responseText, fetchedAt);
                    writeCache(request.responseText, fetchedAt);
                    recordSession();
                    authState = "ok";
                    stale = false;
                    errorText = "";
                    retry.stop();
                    retryDelay = 0;
                } catch (e) {
                    reportFailure(i18n("Could not read the usage response"), 0);
                }
            } else if (request.status === 401) {
                // Rejected before its stated expiry — revoked, or renewed
                // elsewhere. The next poll re-reads the file.
                authState = "expired";
                errorText = i18n("Claude Code's sign-in has expired");
                markStale();
            } else if (request.status === 403) {
                authState = "denied";
                errorText = i18n("This sign-in cannot read usage — log in to Claude Code again");
                markStale();
            } else if (request.status === 429) {
                // The limit is shared with Claude Code's own /usage, and the
                // service sends "retry-after: 0", so wait a good while anyway.
                var seconds = parseInt(request.getResponseHeader("retry-after"), 10);
                var wait = seconds > 0 ? seconds * 1000 : Math.max(300000, retryDelay * 2);
                reportFailure(i18n("The usage service asked to slow down"), Math.min(wait, 1800000));
            } else if (request.status === 0) {
                reportFailure(i18n("Could not reach the usage service"), 0);
            } else {
                reportFailure(i18n("Usage service returned %1", request.status), 0);
            }
        };

        request.open("GET", endpoint);
        request.setRequestHeader("Authorization", "Bearer " + token);
        request.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        request.setRequestHeader("Accept", "application/json");
        request.send();
        watchdog.restart();
    }

    function markStale() {
        if (hasData) {
            stale = true;
        }
    }

    // A failed refresh must never blank a widget that already has figures.
    function reportFailure(message, delay) {
        console.warn("claudeusage: refresh failed:", message);
        errorText = message;
        markStale();
        // Back off from a minute up to a quarter hour, unless told how long.
        retryDelay = delay > 0
            ? Math.min(delay, 3600000)
            : (retryDelay === 0 ? 60000 : Math.min(retryDelay * 2, 900000));
        retry.interval = retryDelay;
        retry.restart();
    }

    function applyPayload(payload, fetchedAt) {
        usage = Usage.parse(payload);
        lastFetch = fetchedAt;
        now = Date.now();
    }

    // ---------------------------------------------------------------- timing

    function millisecondsToNextMinute() {
        var date = new Date();
        return Math.max(250, 60000 - (date.getSeconds() * 1000 + date.getMilliseconds()));
    }

    function scheduleTick() {
        now = Date.now();
        // A window that reset since the last fetch has a new reset time and a
        // fresh severity waiting; go and get them. And catch the session just
        // before it resets, so the trend records how high it finally went.
        var due = rows.some(function (row) {
            if (row.hasReset) {
                return row.resetsAt > lastFetch;
            }
            return row.kind === "session" && row.resetsAt - now < 120000 && now - lastFetch > 120000;
        });
        if (due && !loading && !retry.running) {
            refresh();
        }
        tick.interval = millisecondsToNextMinute();
        tick.restart();
    }

    Timer {
        id: tick
        repeat: false
        onTriggered: root.scheduleTick()
    }

    Timer {
        id: poll
        repeat: true
        running: true
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60000
        onTriggered: {
            if (!retry.running) {
                root.refresh();
            }
        }
    }

    Timer {
        id: retry
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: watchdog
        interval: 20000
        repeat: false
        onTriggered: {
            var request = root.pending;
            root.pending = null;
            root.loading = false;
            root.token = "";
            if (request) {
                request.abort();
            }
            root.reportFailure(i18n("The usage service did not answer"), 0);
        }
    }

    onExpandedChanged: {
        root.now = Date.now();
        // Opening the popup is when fresh figures matter most — but not at the
        // cost of tripping the rate limit again.
        if (root.expanded && !retry.running && Date.now() - root.lastFetch > 60000) {
            root.refresh();
        }
    }

    onCredentialsPathChanged: {
        account = "";
        usage = null;
        sessionHistory = { since: 0, windows: [] };
        plan = "";
        authState = "unknown";
        errorText = "";
        stale = false;
        lastFetch = 0;
        retryDelay = 0;
        retry.stop();
        refresh();
    }

    Component.onCompleted: {
        scheduleTick();
        refresh();
    }
}
