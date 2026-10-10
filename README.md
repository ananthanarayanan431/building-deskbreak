# DeskBreak

A small macOS menu bar app that reminds one person to **drink water every hour** and **walk every two hours** of *active* Mac time. Every reminder asks for an answer, and each one is logged as done, skipped or missed.

- Only time spent working counts. Timers freeze while the Mac sleeps, and pause while the screen is locked or there has been no input for 15 minutes. After an idle break the walk timer starts over, because being away already counts as a break.
- Each reminder is a silent notification with **I did**, **Not doing** and **Remind me in 15 min**. A snooze runs as its own timer and never moves the regular schedule.
- The menu shows time to the next reminders and today's done-out-of-fired counts, plus **Pause for 1 hour** and **Resume now**.
- Local only: no network access, no accounts, no analytics, no third-party dependencies.

Requires macOS 13 (Ventura) or later and Xcode or the Xcode Command Line Tools.

## Install (Homebrew)

```sh
brew tap ananthanarayanan431/tap
brew install deskbreak
open "$(brew --prefix)/opt/deskbreak/DeskBreak.app"
```

Then, once:

1. Allow notifications when macOS asks.
2. **System Settings → Notifications → DeskBreak**: set the style to **Alerts** so reminders stay until answered. (macOS puts the three buttons under **Options** on the alert.)
3. Turn on **Launch at login** in DeskBreak's Settings. After `brew upgrade`, turn it off and on again so the login item points at the new version.

The tap repository must be named `homebrew-tap` on GitHub for `brew tap ananthanarayanan431/tap` to find it.

## Using the app

DeskBreak lives in the menu bar and has no Dock icon. The icon shows its state: a drop while counting, a moon while you are away or the screen is locked, and a pause symbol while paused.

Click the icon to see:

- **Water** and **Walk**: time to the next reminder, any pending snooze, and today's count as done out of fired (for example `5/7`). Counts reset at midnight.
- **Pause for 1 hour** / **Resume now**.
- **Settings…**: see below.
- **Quit DeskBreak**: stops all activity immediately. Timer state is saved, so the next launch picks up where it left off.

Warnings appear in the menu if notifications are turned off, if the style is still "Banners" instead of "Alerts", or if launch at login needs approval. Each one has a button that opens the right System Settings page.

When a reminder fires, answer it from the notification's **Options** menu:

| Button | Recorded as |
| --- | --- |
| I did | done |
| Not doing | skipped |
| Remind me in 15 min | the answer to the follow-up, which returns after 15 minutes of active time |
| No answer within 10 minutes, the X, or clicking the notification body | missed |

## Settings

Changes apply immediately. **Restore defaults** resets every value.

| Setting | Default | Allowed range |
| --- | --- | --- |
| Water every | 1 h | 15 min – 8 h, in 15-minute steps |
| Walk every | 2 h | 15 min – 8 h, in 15-minute steps |
| Snooze for | 15 min | 1 – 60 min |
| Answer within (response window) | 10 min | 1 – 30 min |
| Away after (idle threshold) | 15 min | 1 – 60 min |
| Launch at login | off | |

If you shorten an interval, a countdown longer than the new interval is cut down to it. Longer intervals leave the current countdown as it is.

## Build from source

```sh
scripts/build-app.sh          # creates build/DeskBreak.app, signed ad hoc
open build/DeskBreak.app
```

The app must run from the `.app` bundle; notifications need its `Info.plist` and bundle identifier. `swift build` alone only checks that the code compiles.

Unit tests cover the scheduling and log rules in `DeskBreakCore`:

```sh
swift test
```

With only the Command Line Tools installed (no Xcode), SwiftPM may not find the Testing framework. Point it there explicitly:

```sh
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F"
```

Shortcuts are in the `Makefile`: `make build`, `make app`, `make test`, `make clean`.

## How it works

| Situation | Water timer | Walk timer |
| --- | --- | --- |
| Lid closed / Mac asleep | Freezes, resumes on wake | Freezes, resumes on wake |
| Screen locked, or no input for the idle threshold (15 min) | Pauses, resumes on return | Resets to the full interval |
| "Pause for 1 hour" | Pauses, with any pending snooze | Pauses, with any pending snooze |

- A regular timer restarts the moment its reminder fires, whatever the answer.
- If the next regular reminder of the same kind fires while a snooze is pending, the snooze is cancelled and that earlier reminder is recorded as missed.
- No answer within the response window (default 10 minutes), closing with the X, or clicking the notification without choosing a button records **missed** and removes the notification.
- Daily counts go by the day the reminder fired, so a reminder fired at 23:55 and answered at 00:05 counts for the earlier day.
- Timer state is saved continuously, so quitting or restarting resumes from the remaining time.
- "Pause for 1 hour" runs on wall-clock time. If the Mac sleeps through the pause, the pause has ended when it wakes.
- If a reminder is still on screen when the next one of the same kind fires, the older one is recorded as missed.
- Only one copy runs at a time. A second launch quits itself.

Active time comes from `SuspendingClock`, which does not advance during sleep. The app keeps a single timer that wakes only when something can change: a reminder becoming due, a response window closing, the pause ending, or the idle threshold possibly being reached. While you are away it checks for your return every 5 seconds. It does not poll while locked, because unlocking sends a notification.

### Reminder log

Every reminder is one entry in `~/Library/Application Support/DeskBreak/reminder-log.json`, human-readable JSON:

```json
{
  "records" : [
    {
      "firedAt" : "2026-10-10T09:00:00Z",
      "id" : "3F2B…",
      "kind" : "water",
      "resolvedAt" : "2026-10-10T09:02:14Z",
      "snoozeCount" : 0,
      "status" : "done"
    }
  ],
  "schemaVersion" : 1
}
```

`status` is `done`, `skipped` or `missed` once final, and `awaiting` or `snoozed` while a reminder is still open. Final entries older than 60 days are removed automatically.

If the file cannot be read, it is copied to `reminder-log.unreadable.json` in the same folder and a new log is started, so nothing is silently lost. A log written by a newer version of the app is never overwritten.

### Source layout

```
Sources/DeskBreakCore/   Pure logic (Foundation only): schedule rules, log, log file store
Sources/DeskBreak/       Menu bar app: controller, notifications, idle/lock monitor, SwiftUI views
Tests/                   Unit tests for DeskBreakCore
Resources/Info.plist     Bundle metadata template (LSUIElement: no Dock icon)
scripts/build-app.sh     Builds, assembles and ad hoc signs DeskBreak.app
packaging/homebrew/      Formula to copy into the homebrew-tap repository
```

## What the app touches

| Item | Location | How to remove |
| --- | --- | --- |
| The app | `$(brew --prefix)/Cellar/deskbreak/` | `brew uninstall deskbreak` |
| Reminder log (one JSON file) | `~/Library/Application Support/DeskBreak/` | `rm -rf ~/Library/Application\ Support/DeskBreak` |
| Settings and timer state | `~/Library/Preferences/io.github.ananthanarayanan431.deskbreak.plist` | `defaults delete io.github.ananthanarayanan431.deskbreak` |
| Login item | System Settings → General → Login Items | Turn off in DeskBreak, or remove from the list |
| Notification permission | System Settings → Notifications | Revoke at any time |

Safety rules enforced in the code:

- **One write path.** `LogFileStore.write(_:to:)` is the only code that writes files, and it refuses any path other than the log file (and a copy of an unreadable log) inside the app's own folder. There is no file picker, no user-supplied path and no delete operation.
- **No network, no subprocesses.** The source uses no networking API and never launches another process.
- **No elevated permissions.** No sudo, no Accessibility, Input Monitoring, Full Disk Access or Screen Recording. Idle detection reads only the seconds since the last input (`CGEventSource.secondsSinceLastEventType`).
- **Atomic writes.** The log is written to a temporary file and renamed into place.
- **No dependencies.** Only Apple frameworks.
- **Pinned source.** The formula builds a tagged release verified by SHA-256.

Diagnostics go to the unified log only: in Console.app, filter on subsystem `io.github.ananthanarayanan431.deskbreak`.

### Checks before daily use

- [ ] Read the source in full.
- [ ] `grep -rnE "URLSession|Process\(|FileManager" Sources`: the first two never appear; every `FileManager` use is in `LogFileStore.swift`.
- [ ] DeskBreak appears only under Login Items and Notifications in System Settings, and in no Privacy & Security list.
- [ ] CPU and memory in Activity Monitor stay near zero between reminders.
- [ ] `brew uninstall deskbreak`, then delete the data folder and preferences, and confirm nothing else remains.
- [ ] Make a Time Machine backup before the first install.

## Uninstall

```sh
osascript -e 'quit app "DeskBreak"'       # or Quit DeskBreak from the menu
brew uninstall deskbreak
rm -rf ~/Library/Application\ Support/DeskBreak
defaults delete io.github.ananthanarayanan431.deskbreak
```

Then remove DeskBreak from **System Settings → General → Login Items** if it is still listed. Its entry in **System Settings → Notifications** disappears once the app is gone.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| No reminders appear | Check that notifications are allowed for DeskBreak in System Settings → Notifications, and that no Focus mode is on. |
| Reminders vanish before I answer | Set the notification style to **Alerts**, not **Banners**. |
| Only one button is visible | macOS shows the three buttons under **Options** on the alert. |
| Launch at login stopped working after an upgrade | Turn **Launch at login** off and on again in Settings. |
| Running the binary prints "must run from DeskBreak.app" | Build the bundle with `scripts/build-app.sh` and open the `.app`. |
| I want to see what the app is doing | Open Console.app and filter on subsystem `io.github.ananthanarayanan431.deskbreak`. |

## Releasing

1. Bump `VERSION`, commit, then `git tag v$(cat VERSION) && git push --tags`.
2. `curl -L https://github.com/ananthanarayanan431/deskbreak/archive/refs/tags/v<version>.tar.gz | shasum -a 256`
3. Update `url`, `version` and `sha256` in `packaging/homebrew/deskbreak.rb` and copy it to `Formula/deskbreak.rb` in the `homebrew-tap` repository.

## Known limits (version 1)

- In a Focus mode or while sharing the screen, macOS may hide reminders; they are recorded as missed.
- Watching a video or reading without input counts as idle after the threshold.
- Idle is detected when the threshold is reached, so the 15 idle minutes themselves count as active time. A reminder can fire during those minutes and then be recorded as missed.
- The source is about 1,700 lines (not counting tests), more than the few hundred first planned.
