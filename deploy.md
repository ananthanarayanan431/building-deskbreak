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


## Website

The website is plain HTML and CSS in `docs/`: `index.html`, `privacy.html`, `terms.html`, `style.css` and `favicon.svg`. There is no build step. To preview it, open `docs/index.html` in a browser.

To publish it with GitHub Pages:

1. Push the repository to GitHub.
2. In the repository, open **Settings → Pages**. Under **Build and deployment**, choose **Deploy from a branch**, branch `main`, folder `/docs`, and save.
3. After a minute the site is live at `https://ananthanarayanan431.github.io/deskbreak/`.

Before launch (see `CLAUDE.md`), connect a custom domain: buy one, enter it under **Settings → Pages → Custom domain**, add the DNS records GitHub shows, and tick **Enforce HTTPS**. GitHub then adds a `docs/CNAME` file; pull it so your copy matches.

The privacy policy says the site is hosted on GitHub Pages and loads fonts from Google Fonts. If you change either, update the "This website" section of `docs/privacy.html`.
