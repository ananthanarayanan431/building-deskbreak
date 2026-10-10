# Deploying DeskBreak locally

How to install a build you made yourself, and how to update it after changing the code. For building and testing, see [Build from source](README.md#build-from-source) in the README; for publishing a Homebrew release, see [Releasing](README.md#releasing).

## Install a local build

Launch at login needs the app in a permanent location, so install it into `/Applications` rather than running it from `build/`:

```sh
osascript -e 'quit app "DeskBreak"'
rm -rf /Applications/DeskBreak.app
cp -R build/DeskBreak.app /Applications/
open /Applications/DeskBreak.app
```

Then click the menu bar drop → **Settings…** → **Launch at login**. If macOS asks for approval, switch DeskBreak on under **System Settings → General → Login Items**.

## Making changes

Run everything from the repository root (the `deskbreak` folder).

1. **Edit** the Swift files under `Sources/`.
2. **Test**: `make test`. Fix any failures before going on.
3. **Build**: `make app`. This writes `build/DeskBreak.app`; the installed copy is not touched yet.
4. **Replace the installed app** with the commands under [Install a local build](#install-a-local-build). Quit the old app first, or the old version keeps running.
5. **Commit**:

   ```sh
   git add -A
   git commit -m "Describe what you changed"
   ```

Settings, the reminder log, notification permission and launch at login are tied to the bundle identifier, not to a particular build, so they survive a reinstall. Each build is signed ad hoc, so macOS may occasionally ask again for notification or login item approval; approve it again when it does.

