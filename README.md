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

## Build from source

```sh
scripts/build-app.sh          # creates build/DeskBreak.app, signed ad hoc
open build/DeskBreak.app
```

The app must run from the `.app` bundle; notifications need its `Info.plist` and bundle identifier. `swift build` alone only checks that the code compiles.

```sh
swift test                    # unit tests for the scheduling and log rules
```

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

Active time comes from `SuspendingClock`, which does not advance during sleep. The app keeps a single timer that wakes only when something can change: a reminder becoming due, a response window closing, the pause ending, or the idle threshold possibly being reached. While you are away it checks for your return every 5 seconds. It does not poll while locked, because unlocking sends a notification.

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

## Releasing

1. Bump `VERSION`, commit, then `git tag v$(cat VERSION) && git push --tags`.
2. `curl -L https://github.com/ananthanarayanan431/deskbreak/archive/refs/tags/v<version>.tar.gz | shasum -a 256`
3. Update `url`, `version` and `sha256` in `packaging/homebrew/deskbreak.rb` and copy it to `Formula/deskbreak.rb` in the `homebrew-tap` repository.

## Known limits (version 1)

- In a Focus mode or while sharing the screen, macOS may hide reminders; they are recorded as missed.
- Watching a video or reading without input counts as idle after the threshold.
- Idle is detected when the threshold is reached, so the 15 idle minutes themselves count as active time.
