# Safari port: decisions

The history behind `safari/README.md`: what was decided, why, the evidence,
and what was rejected. Newest last.

## 2026-11-24: a `safari` build target from the same source

**What.** `build.js` gains a `safari` target (`browserName: 'safari'`, esbuild
target `safari18.4`) with its own `safari/manifest.json`, derived from Chrome's
MV3 manifest: no `history` permission, no optional `downloads`, no
`options_ui.open_in_tab`, `minimum_chrome_version` replaced by
`browser_specific_settings.safari.strict_min_version` 18.4. Code that differs
branches on `process.env.BUILD_TARGET === 'safari'`, as the Firefox code does.

**Why.** `safari-web-extension-converter` (Xcode 27.0) on the Chrome build
flagged exactly `history`, `downloads` and `open_in_tab` as unsupported. 18.4 is
the first Safari that keeps a Developer ID extension installed outside the App
Store.

**Rejected.** Converting `dist/chrome` with the converter and shipping its Xcode
project: the Chrome build calls `chrome.history` and requests `downloads`, and a
generated project would have to be regenerated on every RES release.

## 2026-11-24: bind every extension API call to its object

**What.** Seventeen call sites passed an extension API function detached from its
object: `apiToPromise(chrome.runtime.sendMessage)`, the same for
`tabs.sendMessage`, `tabs.query`, `tabs.remove`, `windows.create`,
`permissions.*`, `scripting.executeScript`, `history.getVisits`,
`identity.launchWebAuthFlow`; `getURL = chrome.runtime.getURL`; and
`(cond ? chrome.pageAction.show : chrome.action.enable)(tab.id)`. Each now
binds or calls as a method. The change is in shared code and harmless in
Chrome and Firefox.

**Why.** In WebKit a detached extension API call returns, throws nothing and
never calls back. RES's foreground messaging is built on one, so in WebKit its
first message to the background never returned and start-up stopped after
options loaded: no menu, no settings console, nothing in any log.

**Evidence.** The WebKit harness (below), 2026-11-24: before, 7 to 8 of the
checks failed; after, 16 of 16 passed, on the development and the production
build. With only `foreground/messaging.js` reverted, 8 of 16 failed again. A
probe in the content world: `chrome.runtime.sendMessage(msg, cb)` answered;
`const send = chrome.runtime.sendMessage; send(msg, cb)` never called back.

## 2026-11-24: a `requestIdleCallback` shim, injected only into the Safari build

**What.** `lib/environment/utils/idleCallback.js` exports `requestIdleCallback`
and `cancelIdleCallback` (the native ones when present, else a 1 ms timeout
with a 50 ms budget). The Safari target lists it in esbuild's `inject`, which
replaces the globals in every bundle.

**Why.** Safari 27.2 has none (`typeof requestIdleCallback` is `"undefined"`,
checked in Safari 27.2 on 2026-11-24), and RES calls it in five places,
including storage pruning and i18n caching.

**Rejected.** Importing a polyfill from the shared entry points: it would ship
to Chrome and Firefox, which have the real one.

## 2026-11-24: an extension-kept record of visits instead of Safari's history

**What.** `lib/environment/background/visits.js` keeps visited URLs in the
background's IndexedDB (`res-visits`), keyed by `normalizeVisitURL`: a Reddit
URL on any `*.reddit.com` host by its path alone (no query, trailing slash), any
other URL without its fragment. The Safari build records the Reddit page each
time RES starts in a top-level window, every http(s) link clicked or
middle-clicked on it, tabs RES opens, and the media RES opens (the existing
`addURLToHistory`). `isURLVisited` answers from it. Entries older than a year
are pruned when the background starts. Private windows are skipped, both in
the content script (`inIncognitoContext`) and in the background
(`sender.tab.incognito`).

**Why.** Safari has no `history` API. Without a record of its own, *Mark
visited* would do nothing and filteReddit's visited and comments-opened filters
would never match.

**Rejected.** A no-op `isURLVisited`, which silently disables those filters.
`storage.local` for the record: RES's backup exports all of `storage.local`,
so browsing history would land in every backup.

**Known limit.** Clearing Safari's history does not clear the record, and there
is no RES control to clear it. Unverified: whether removing the extension in
Safari deletes its IndexedDB.

## 2026-11-24: downloads saved from the page

**What.** On Safari the media download button fetches the file in the content
script, turns it into a blob URL and clicks an `<a download>` with the post's
title as its name. If the fetch fails, the media opens in a new tab. The
Safari build does not ask for the `downloads` permission.

**Why.** Safari has no `downloads` API. A blob URL is same-origin, so
`<a download>` names the file. i.redd.it allows the cross-origin read:
`curl -H 'Origin: https://old.reddit.com'` on an i.redd.it image returned
`access-control-allow-origin: https://old.reddit.com` (2026-11-24).

**Evidence.** In the harness the button saved a 3.8 MB `.jpeg` under the
post's title.

## 2026-11-24: the app is built by a script, signed with the Developer ID and notarised

**What.** `safari/build-app.sh` assembles *Reddit Enhancement Suite.app*
(`hu.triglavmodular.RES`) and its extension (`hu.triglavmodular.RES.Extension`)
without an Xcode project: `swiftc` for `safari/app/App.swift` (the window that
says whether the extension is on) and `safari/app/Handler.swift` (an empty
principal class; RES sends no native messages), `lipo` for a universal binary,
`plutil` for the Info.plists, an icon from `images/icon512.png`. Signed with
exactly the app-sandbox entitlement, notarised with `notarytool`, stapled. This
follows the Safari Web MIDI app's `tools/build.sh`.

**Why.** Safari drops a Developer ID extension that is not notarised, and
notarisation refuses `get-task-allow`; PlugInKit refuses an extension without
the sandbox (both recorded in `~/SDIY/Tooling/practices/web.md`).

**Evidence.** 2026-11-24: notarisation submission
`53e8b52b-2bed-4e7d-9193-42c36371c263` accepted, stapled; `spctl` says
"Notarized Developer ID"; `pluginkit` lists `hu.triglavmodular.RES.Extension`
5.26.3; Safari added it to its extension list
(`Extensions.plist`, origins `https://*.reddit.com/*`), not yet enabled.

## 2026-11-24: testing in WebKit's extension runtime against an archived page

**What.** `safari/tests/run.sh` builds a copy of the extension with two
test-only scripts (a content script listed first, sharing RES's isolated world,
and a service worker that wraps RES's background), and runs
`safari/tests/harness/main.swift`: `WKWebExtensionController`, an off-screen
`WKWebView`, the Wayback capture
`web.archive.org/web/20260101022858id_/https://old.reddit.com/r/EarthPorn/`
loaded with `loadSimulatedRequest` at its real URL. 16 checks.

**Why.** Safari's automation sessions do not load extensions. old.reddit.com
sends every signed-out client to a login page (`/login/?reason=lor2`, checked
with curl and Safari 27.2 on 2026-11-24), and a test may not sign in.

**What the harness needed.** The web view must use the controller's own data
store or no content script is injected; content-script errors reach `onerror`
only as "Script error.", so the test content script wraps timers, listeners,
observers and `then` to record stacks; `/by_id/…json` is answered from the
page's data so image expandos can be built.

**Rejected.** Mocking Reddit's whole API: the test checks the port, and the
one answered call is the one a feature under test cannot do without.

## 2026-11-24: checked in Safari 27.2, signed in on old.reddit.com

**Evidence.** The owner turned the extension on (Safari's `Extensions.plist`:
`Enabled`, granted origins `*://*/*`) and browsed old.reddit.com signed in.
Read-only screenshots of that window showed RES running: the gear beside
*preferences*, the account switcher, the split karma count, the shortcut bar
with *Dashboard*, *show images*, the filteReddit funnel, *Use subreddit style*,
the comment navigator and the user tagger's dialog in use. The extension's
IndexedDB (`res-visits`, under Safari's `WebKit/WebsiteData/Default`) held 9
visits: Reddit pages of several kinds, all keyed under `www.reddit.com`, and
one v.redd.it video RES had expanded. A tab
opened before the extension was turned on had no RES until it was reloaded.

## Open

- **Not checked in Safari itself:** the media download button and the settings
  console (both pass in the WebKit harness).
- **Not exercised anywhere yet:** backup sign-in flows (Dropbox, Google Drive,
  OneDrive: `windows.create` popups and `webRequest.onBeforeRedirect`), runtime
  permission prompts for other sites' embeds, private windows.
- Opening the settings console hides the toolbar button, because the options
  page runs `subredditStyleToggle.onInit` from inside the tab. Upstream
  behaviour, also in Chrome; left as is.
