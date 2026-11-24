# Reddit Enhancement Suite for Safari

RES as a Safari web extension on the Mac. It is the same extension as the
Chrome and Firefox builds, built from the same source with a `safari` target,
and Safari installs it from a small Mac app, *Reddit Enhancement Suite.app*.

It needs Safari 18.4 or later. RES works on old.reddit.com, which Reddit only
shows to signed-in accounts.

## Install

Building the app needs a Developer ID Application certificate in the keychain
and a `notarytool` keychain profile, because Safari only keeps a Developer ID
extension that Apple has notarised.

```bash
safari/build-app.sh --notarize --install
```

This builds the extension, signs and notarises the app, copies it to
/Applications and opens it. Then, in Safari:

1. Settings ▸ Extensions: turn on **Reddit Enhancement Suite**.
2. In the same pane, *Edit Websites…*: set reddit.com to **Allow**, or choose
   *Always Allow on This Website* the first time Safari asks on Reddit.
3. Reload old.reddit.com. The RES gear appears beside your username.

The app's window says whether the extension is on and opens Safari's
settings for it.

## What differs from Chrome and Firefox

- **Visited links.** Safari does not let extensions read its history, so RES
  keeps its own record of the Reddit pages you open, the links you follow from
  them and the media it opens. *Mark visited* and the visited and
  comments-opened filters use it. Clearing Safari's history does not clear
  it; entries are forgotten after a year. RES is written to skip private windows.
- **Downloading media.** The download button saves the file through Safari's
  own downloads, under the post's title; Safari may ask once whether
  old.reddit.com may download files. If the media's host does not allow it,
  the file opens in a new tab instead, to save from there.

Checked in Safari 27.2. Not yet checked: private windows, earlier versions of
Safari, backups to Dropbox, Google Drive and OneDrive (their sign-in windows),
and the permission prompts for embeds from other sites.

## Build and test

| Command | What it does |
|---|---|
| `corepack yarn once --browsers safari` | Builds the unpacked extension into `dist/safari/`. |
| `safari/tests/run.sh` | Builds it and checks it in WebKit's own extension runtime (below). `--no-build` checks the existing `dist/safari/`. |
| `safari/build-app.sh` | Builds and signs `dist/safari-app/Reddit Enhancement Suite.app`. `--notarize` notarises and staples it; `--install` also puts it in /Applications. |

`build-app.sh` reads three optional settings from the environment:
`RES_SIGN_ID` (the signing certificate's SHA-1; by default the Developer ID
Application certificate that expires last), `RES_NOTARY_PROFILE` (the
`notarytool` keychain profile, by default `rewired-notary`) and `RES_APP_ID`
(the app's bundle identifier, by default `hu.triglavmodular.RES`; the
extension's is that plus `.Extension`).

### The WebKit test

Safari's automation windows do not load extensions, so `safari/tests/run.sh`
loads the build with `WKWebExtensionController`, the engine Safari runs
extensions on, into an off-screen web view. The page is an archived
old.reddit.com listing (r/EarthPorn, from the Wayback Machine) served at its
real address, with the permissions a person grants in Safari. It checks that
RES starts and adds its menu, that messages and storage reach the background,
that visits are recorded and matched, that an i.redd.it image expands and its
download button saves the file, that the toolbar button works as the
subreddit style toggle, and that the settings console opens and renders. It
also fails on any missing-API error from RES's scripts.

Reddit answers a signed-out client's API calls with a login page. The test
answers the one call image expandos need (`/by_id/…json`) from the post's
data in the page; RES's other calls to Reddit fail there, and their errors
are listed but do not fail the test.

It needs macOS 15.4 or later and the network (the page's own scripts and
images load from Reddit). The archived page is fetched once into
`safari/tests/fixtures/`.
