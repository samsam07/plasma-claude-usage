# Claude Usage — a Plasma 6 panel widget

[github.com/samsam07/plasma-claude-usage](https://github.com/samsam07/plasma-claude-usage)

Shows how much of your Claude plan's limits you have used, as a ring around the
Claude mark in the system tray, next to the network and volume icons. Click it
for every limit and when each one resets, this week's usage split by product,
and a seven-day chart of your sessions. The figures are the ones Claude Code's
`/usage` screen shows, read with Claude Code's own sign-in.

The ring is Claude orange, then turns yellow and red as the limit fills.

## Requirements

- KDE Plasma 6
- [Claude Code](https://claude.com/claude-code), signed in with a Claude
  subscription (Pro, Max, Team or Enterprise). An API-key login has no plan
  limits to show.

## Install

```sh
git clone https://github.com/samsam07/plasma-claude-usage.git
cd plasma-claude-usage
./install.sh
```

To show it with the other tray icons: right-click the system tray's arrow →
**Configure System Tray…** → **Entries** → **Claude Usage** → **Always shown**.
If it is not listed yet, reload the shell first (see below).

To place it on a panel by itself instead: right-click the panel →
**Add or Manage Widgets…** → **Claude Usage**.

If the widget is already showing when you reinstall, reload the shell to pick
up the changes:

```sh
kquitapp6 plasmashell && (kstart plasmashell >/dev/null 2>&1 &)
```

`./uninstall.sh` removes it.

## Settings

Right-click the widget → **Configure Claude Usage…**

| Setting | Default | Notes |
| --- | --- | --- |
| Ring shows | Current session | The 5-hour session, the week across all models, or whichever is closest to its limit |
| Turn yellow at | 75% | |
| Turn red at | 90% | |
| Refresh every | 5 minutes | At least 2; see [Rate limit](#rate-limit) |
| Credentials file | `~/.claude/.credentials.json` | Change only if you run Claude Code with `CLAUDE_CONFIG_DIR` |

## How it behaves

- The ring shows one limit. The popup shows that limit large, then every
  other limit as a bar, usage credits if you have them switched on, this
  week's usage by product, and the session chart.
- Percentages are rounded down, as Claude Code rounds them: 99.6% reads `99%`.
- Resets under a day away read `Resets in 2 h 13 min`; further out,
  `Resets Wed 23 Sep, 7:00 PM`.
- Once a window's reset time passes, it drops to 0% straight away, and the
  widget fetches the new figures without waiting for the next refresh.
- Opening the popup refreshes it if the figures are more than a minute old.

### Usage by product

Claude Code, Chats, Cowork and Other, each as a share of this week's usage,
exactly as claude.ai's usage page lists them. The shares add up to 100% of what
you have used, not of your limit. The bars use your Plasma accent colour, so
they don't look like the limit bars' orange, yellow and red.

### Session chart

One column per 5-hour session over the last seven days, placed at the time it
ran and as tall as the highest percentage it reached. Its colour follows the
same thresholds as the ring. Point at a column, or tab to the chart and use the
arrow keys, to read its figure and times. Otherwise the line under the chart
names the busiest session.

The usage service reports only the session in progress, so **the widget
records this history itself**. Each refresh saves the current session's
highest figure, and the widget checks once more just before a session resets
to catch where it ended.

- The chart starts empty and fills in over the first week. The stretch before
  recording began is shaded.
- Sessions that ran while the widget wasn't running (computer off, logged out)
  are missing, and look the same as sessions that never happened.
- The history is kept per account next to the cache, and trimmed to eight days.

### Rate limit

The usage endpoint is rate limited. The limit is shared with Claude Code's own
`/usage` screen, so a widget that polls too often can make that screen fail
too. Refreshing every minute or two was enough to hit the limit in testing,
hence the 5-minute default. When the service answers `429`, the widget keeps
its figures and waits at least 5 minutes, doubling up to 30, before trying
again. The service's `retry-after` header says `0`, so it isn't useful.

### Colours

These are Claude Code's own theme colours. It ships separate sets for dark and
light backgrounds, so the widget picks the set that suits your Plasma theme.

| State | When | Dark | Light |
| --- | --- | --- | --- |
| Orange | below the yellow threshold | `#d77757` | `#d77757` |
| Yellow | at or past **Turn yellow at** | `#ffc107` | `#966c1e` |
| Red | at or past **Turn red at** | `#ff6b80` | `#ab2b3f` |

In the dark set, the orange and the red are close enough to be hard to tell
apart at a glance, especially with red-green colour blindness. The length of
the ring and the percentages carry the same information.

Claude decides when to warn you on its own servers, so Claude Code has no fixed
percentage to copy. The thresholds are this widget's defaults, but the usage
response also rates each limit's severity. If that rating is higher than the
percentage alone gives, the colour follows the rating.

### Sign-in

The widget reads `accessToken` from Claude Code's credentials file before
every refresh, sends it to `api.anthropic.com` and nowhere else, and holds it
in memory only until that request finishes.

It never renews the sign-in or writes to the file. Renewing a sign-in replaces
the stored refresh token, and doing that from a second program would log Claude
Code out. Claude Code renews its own sign-in whenever you use it, and the
widget picks up the new token on its next refresh.

If the sign-in has lapsed because Claude Code has not been used for a while,
the widget keeps showing the last figures it fetched, dimmed and marked with
`⚠`. The last response is cached per account in SQLite
(`~/.local/share/plasmashell/QML Offline Storage/`), so the ring is filled in
as soon as Plasma starts.

## Layout

```
package/contents/
├── code/usage.js      all usage logic, free of QML types so it can be tested
├── config/            settings schema and page registration
├── icons/claude.svg   the Claude mark
└── ui/
    ├── main.qml                   sign-in, fetching, caching, timers, applet state
    ├── CompactRepresentation.qml  the ring in the panel or tray
    ├── FullRepresentation.qml     the popup
    ├── UsageRing.qml              the ring itself, used in both
    ├── LimitRow.qml               one limit's bar in the popup
    ├── ProductRow.qml             one product's share of the week
    ├── SessionTrend.qml           the seven-day session chart
    └── configGeneral.qml          the settings page
```

`main.qml` owns all state and hands itself to the representations as `applet`,
because QML ids do not cross file boundaries.

## Tests

```sh
./tests/run-tests.sh    # usage logic, against real and synthetic responses
./tests/try-run.sh      # loads the applet and reports any QML errors
```

`run-tests.sh` runs `usage.js` under `gjs`, with `TZ=UTC` so the chart's day
boundaries are predictable. `tests/fixture-usage.json` is a real response from
the endpoint, whose product split matches what claude.ai showed at the time.
`tests/fixture-near-limit.json` is synthetic, with made-up figures and
severities that cover the warning, critical, per-model and usage-credit cases a
lightly used account never returns.

## Data source

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <Claude Code access token>
anthropic-beta: oauth-2025-04-20
```

This is the request behind Claude Code's `/usage` screen. The response has
`five_hour` and `seven_day` windows with a `utilization` percentage and a
`resets_at` time, and a `limits` array that adds a `severity` to each window,
plus per-model weekly limits on plans that have them. `seven_day_breakdown`
holds the week's split by product. It also reports usage credits when those
are switched on. There is no history; see [Session chart](#session-chart).

The endpoint is undocumented, so it can change without warning. If the widget
stops updating, check it first. A failed fetch does not clear the widget: it
keeps the last figures and retries with a backoff.

## Credits

The Claude mark is from [Simple Icons](https://simpleicons.org) (CC0). Claude is
a trademark of Anthropic. This project is not affiliated with or endorsed by
Anthropic.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Hisham Maudarbocus.
