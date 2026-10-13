# SmarterThings

A macOS menu bar remote for Samsung smart TVs. Click the TV icon in the menu bar to get a remote with a D-pad, volume and channel rockers, media keys, input sources, favorite app shortcuts and a field for typing into the TV's search boxes.

> Not affiliated with or endorsed by Samsung. "Samsung" and "SmartThings" are trademarks of Samsung Electronics.

## Requirements

- macOS 26 or later (the UI uses Liquid Glass)
- Swift 6 toolchain. Xcode's Command Line Tools are enough; full Xcode isn't needed.
- A Samsung TV from 2016 or later (Tizen), added to your SmartThings account
- For typing and app shortcuts: the Mac and the TV on the same network

## Install

1. Download the latest `SmarterThings-<version>.dmg` from the [Releases page](../../releases/latest), open it, and drag **SmarterThings** onto **Applications**.
2. Open SmarterThings from Applications. It appears as a TV icon in the menu bar, with no Dock icon.

The app is ad-hoc signed, not notarized by Apple, so the first launch on another Mac shows *"Apple could not verify SmarterThings…"*. To open it anyway, go to **System Settings › Privacy & Security** and click **Open Anyway** next to SmarterThings, or run:

```sh
xattr -dr com.apple.quarantine /Applications/SmarterThings.app
```

## Build from source

```sh
make run     # debug build, restart the app
make stop    # quit the app (or click Quit in the remote's footer)
make app     # optimized universal build → SmarterThings.app
make dmg     # → build/SmarterThings-<version>.dmg (+ .sha256)
make test    # run the tests
```

Set the version with `make dmg VERSION=1.1.0`. Release builds are universal (Apple Silicon and Intel).

## Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`). Push a version tag:

```sh
git tag v1.1.0
git push origin v1.1.0
```

The workflow runs the tests on a macOS runner, builds `SmarterThings-1.1.0.dmg` with `make dmg`, and publishes a GitHub Release with the DMG, its `.sha256` file and auto-generated notes. The version comes from the tag, minus the leading `v`.

## How to use

### 1. Connect to SmartThings

1. Create a Personal Access Token at <https://account.smartthings.com/tokens>. Give it access to read devices and run commands on them.
2. Click the TV icon in the menu bar, paste the token and click **Connect**.

Your TV appears by its SmartThings name. If you have several TVs, a picker shows up in the header.

### 2. Remote buttons

| Control | Notes |
|---|---|
| Power (top right) | Toggle. Red means on, grey means off or unknown. |
| D-pad, OK | Arrow keys, Return and Esc also work while the remote has focus. |
| Back, Home, Menu | |
| VOL / CH rockers, Mute | |
| ⏪ ▶ ⏸ ⏹ ⏩ | Playback in apps that support it |
| Source (header) | Lists the TV's inputs, e.g. HDMI 1 |

Buttons the TV doesn't support are greyed out.

### 3. Type and search on the TV

The field at the bottom does two things:

- **Return (↑)** types into whatever **Samsung keyboard** is open on the TV, e.g. Tizen's own search or the browser's address bar. It goes over the local network.
- **🔍** runs the **TV's own search** with your text and shows Samsung's search results. It goes through the SmartThings cloud, so it works anywhere and needs no pairing.

Use 🔍 for YouTube: its search box uses YouTube's own keyboard, which ignores typed text.

The first time you press Return, two prompts appear:
1. **macOS** asks to allow SmarterThings to access the local network. Click Allow.
2. **The TV** asks whether to allow "SmarterThings (Mac)". Accept it with the physical remote.

The app finds the TV on your network automatically. If you have several Samsung TVs, pick one from the Wi-Fi menu in the footer. Your choice is remembered by the TV's own ID, not its IP, so it keeps working when the router gives the TV a new address. If no TV can be found, the error message under the field has a box for the TV's IP address as a fallback. On the TV it's under Settings › General › Network › Network Status › IP Settings.

### 4. App shortcuts

Click ✎ next to **Shortcuts**. The app checks which known apps are installed on the TV and lists only those, using the TV's names. Tick up to four, then click ✓. Clicking a tile opens that app on the TV through SmartThings, which also works away from home.

## How it works

The app reaches the TV in two ways, because neither one can do everything:

| | SmartThings cloud | Local network |
|---|---|---|
| Used for | Other remote buttons, power state, inputs, opening apps, TV search, and D-pad/volume when the TV isn't reachable locally | D-pad, OK and volume ±, typing into the open keyboard, checking installed apps, finding the TV |
| Endpoint | `https://api.smartthings.com/v1` | `wss://<tv-ip>:8002/...` (typing), `http://<tv-ip>:8001/api/v2/...` (info, apps) |
| Auth | Personal Access Token (Bearer) | Typing: TV pairing token, issued after you click "Allow" on the TV. Info and apps: none |
| Works | Anywhere with internet | Only on the same network as the TV |

### SmartThings cloud

- `GET /devices` lists devices. TVs are recognized by having the `samsungvd.remoteControl` or `tvChannel` capability.
- `POST /devices/{id}/commands` sends `{"commands":[{"component":"main","capability":…,"command":…,"arguments":[…]}]}`.
- `GET /devices/{id}/components/main/capabilities/{capability}/status` reads the power state (`switch`) and the input list (`samsungvd.mediaInputSource` or `mediaInputSource`).

| Button | Capability → command |
|---|---|
| Power | `switch` → `on` / `off` |
| Volume, mute | `audioVolume` → `volumeUp` / `volumeDown`, `audioMute` → `mute` / `unmute` |
| Channel | `tvChannel` → `channelUp` / `channelDown` |
| D-pad, OK, Back, Home, Menu | `samsungvd.remoteControl` → `send` with `[KEY, "PRESS_AND_RELEASED"]` |
| Media | `mediaPlayback` → `play` / `pause` / `stop` / `rewind` / `fastForward` |
| Source | `samsungvd.mediaInputSource` → `setInputSource` with an input ID |
| App shortcut | `custom.launchapp` → `launchApp` with `[appId, appName]` |
| 🔍 search | `custom.tvsearch` → `search` with `[query, ""]` |

The command shapes come from SmartThings' capability definitions (`GET /capabilities/{id}/1`). For example, `samsungvd.remoteControl.send` takes a `keyValue` and an optional `keyState`.

### Local network (Samsung Tizen remote protocol)

1. **Discovery.** SSDP `M-SEARCH` for `urn:samsung.com:device:RemoteControlReceiver:1` (older TVs) and `urn:dial-multiscreen-org:service:dial:1` (newer TVs, e.g. 2025 models), keeping only replies whose `SERVER` header says Samsung. Each reply's address is then asked for `http://<host>:8001/api/v2/`, which gives the TV's name and its stable `uuid:` ID; only `type: "Samsung SmartTV"` is kept. The TV chosen in the footer menu is matched by that ID. A manually entered IP is used only when discovery finds nothing, so a TV that gets a new IP from the router is found again automatically.
2. **Installed apps.** For each known app ID, `GET http://<tv-ip>:8001/api/v2/applications/<id>` returns 200 with the app's name if it's installed, or 404 if not. There's no cloud API for listing apps, and `ed.installedApp.get` over the WebSocket isn't confirmed to work on newer firmware.
3. **Connect (for typing).** A WebSocket to port 8002, with the app name base64-encoded in `name` and the saved pairing token in `token`. The TV replies `ms.channel.connect`; the first time, that reply includes the new token. The TV uses a self-signed certificate, which the app trusts only for the TV's own address. The TV drops idle connections, so a failed send reconnects once and retries.
4. **Typing.** `ms.remote.control` with `TypeOfRemote: "SendInputString"` and base64 text, then `SendInputEnd` to apply it.
5. **Keys.** `ms.remote.control` with `TypeOfRemote: "SendRemoteKey"`, `Cmd: "Click"` and a key code (`KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`, `KEY_ENTER`, `KEY_VOLUP`, `KEY_VOLDOWN`). `KeyDispatcher` sends the D-pad and volume this way because the cloud allows only 12 commands a minute. If the local connection fails, the key goes through SmartThings and local is skipped for 60 seconds. Concurrent presses share one connection attempt, so the TV only asks "Allow" once.

### Code layout

Clean architecture: the UI depends on the core, and the core's domain doesn't depend on any network or storage code.

```
Sources/SmarterThingsCore/
  Domain/           RemoteKey, TV, TVApp, TVCommand, LocalTVDevice, and the ports
                    TVController, TVKeyboard, InstalledAppFinder, TokenStore
  Infrastructure/   SmartThingsClient (cloud), LocalTVRemote + LocalRemoteProtocol
                    (typing), LocalInstalledApps, SSDPDiscovery, LocalTVDiscovery,
                    TVHostFinder, FileTokenStore
Sources/SmarterThings/  SwiftUI MenuBarExtra: views, view models, PopularApps (known app IDs)
Tests/SmarterThingsCoreTests/  Swift Testing, using fake HTTP transport and token stores
scripts/bundle.sh     builds SmarterThings.app (Info.plist, ad-hoc signature)
scripts/dmg.sh        packages it into a drag-to-Applications DMG
```

### Where data is stored

| What | Where |
|---|---|
| SmartThings token | `~/Library/Application Support/SmarterThings/smartthings-token` |
| TV pairing token | `~/Library/Application Support/SmarterThings/local-tv-token` |
| Chosen local TV (by ID), manually entered TV IP, favorite apps | app defaults (`com.mhdiiilham.SmarterThings`) |

The token folder is readable only by your user account (0700, with files 0600). Tokens aren't kept in the Keychain because the app is ad-hoc signed: the Keychain treats every rebuild as a new app and asks for your password again.

## Limitations

- **SmartThings allows 12 commands per minute per TV.** D-pad and volume avoid this by going over the local network at home. Other buttons, and D-pad/volume away from home, can still hit it. The app then shows a short notice with the seconds until the limit resets, from the `x-ratelimit-reset` header, and the remote stays usable. See [SmartThings rate limits](https://developer.smartthings.com/docs/getting-started/rate-limits).
- **SmartThings tokens expire after 24 hours.** Personal Access Tokens created since late 2024 are short-lived. When one expires, the remote asks for a new one. A long-lived connection would need SmartThings OAuth through a registered SmartApp, which this app doesn't implement.
- **Power on depends on the TV.** Turning the TV on from the cloud only works if network standby is enabled on the TV. Turning it off always works.
- **Power and mute state can drift.** Power is re-read each time you open the remote. Mute state is only tracked locally, so it can get out of sync if you use the physical remote.
- **Typing only reaches Samsung's keyboard.** YouTube draws its own keyboard and ignores typed text; use 🔍 search there. Text is sent on Return, not as you type.
- **Shortcuts only know listed apps.** The picker checks the app IDs in `Sources/SmarterThings/PopularApps.swift` against the TV, so an installed app missing from that list won't appear. Add its Tizen app ID to the list to include it.
- **TV search shows Samsung's results page.** 🔍 runs the TV's universal search; it doesn't open a specific app's search directly.
- **App tiles show letters, not icons.** Tiles are colored letters; the TV's icons aren't downloaded.
- **One TV pairing at a time.** Only one local TV token is stored, so switching between TVs makes the new TV ask "Allow" again.
- **Some features need the same network.** Typing, finding the TV and checking installed apps need it. Buttons, shortcuts and 🔍 search work anywhere.
- **Older TVs aren't supported.** Models from 2014–2015 use an older PIN-based pairing protocol.
- **It isn't notarized.** The app is ad-hoc signed, so other Macs show a Gatekeeper warning on first launch (see Install). Fixing that needs an Apple Developer ID ($99/year) and notarization.
- **SwiftUI `@State` isn't used.** In the macOS 27 SDK, `@State` is a macro whose plugin ships only with Xcode. The views use the `State` type directly so the app builds with Command Line Tools alone.

## Status

| Feature | Verified on a real TV |
|---|---|
| SmartThings connection, TV detection | ✅ |
| D-pad arguments | ✅ Match SmartThings' `samsungvd.remoteControl` definition |
| Finding the TV on the network (2025 model) | ✅ |
| Typing into Tizen's own search | ✅ (YouTube ignores it, as noted above) |
| 🔍 TV search (`custom.tvsearch`) | ✅ Shows results |
| Checking installed apps (`/api/v2/applications/<id>`) | ✅ 7 of 31 known IDs found on the test TV |
| Opening apps (`custom.launchapp`) | ❓ Not tested yet |
| Power toggle and the other cloud buttons | Not explicitly confirmed yet |

The protocol messages and API calls are covered by unit tests (`make test`). The rows marked ❓ still need a check against a real TV.

## License

[MIT](LICENSE) © 2026 Muhammad Ilham
