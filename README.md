# TV Remote

A macOS menu bar remote for Samsung smart TVs. Click the TV icon in the menu bar to get a remote with a D-pad, volume and channel rockers, media keys, input sources, favorite app shortcuts and a field for typing into the TV's search boxes.

> Not affiliated with or endorsed by Samsung. "Samsung" and "SmartThings" are trademarks of Samsung Electronics.

## Requirements

- macOS 14 or later
- Swift 6 toolchain. Xcode's Command Line Tools are enough; full Xcode isn't needed.
- A Samsung TV from 2016 or later (Tizen), added to your SmartThings account
- For typing and app shortcuts: the Mac and the TV on the same network

## Quick start

```sh
make run     # debug build, restart the app
make app     # optimized build → TVRemote.app (then: open TVRemote.app)
make test    # run the tests
```

`make run` and `make app` produce `TVRemote.app`, which runs as a menu bar app with no Dock icon. To keep it, copy `TVRemote.app` into `/Applications`.

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

### 3. Type on the TV

Open a search box on the TV (for example in the TV's browser), type in **Type on TV…** and press **Return**. The text is sent when you press Return, not as you type.

The first time, two prompts appear:
1. **macOS** asks to allow TV Remote to access the local network. Click Allow.
2. **The TV** asks whether to allow "TV Remote (Mac)". Accept it with the physical remote.

If the TV can't be found automatically, the error message under the field has a box for the TV's IP address. On the TV it's under Settings › General › Network › Network Status › IP Settings.

### 4. App shortcuts

Click ✎ next to **Shortcuts** to load the apps installed on the TV, tick up to four, then click ✓. Clicking a tile opens that app on the TV.

## How it works

The app reaches the TV in two ways, because neither one can do everything:

| | SmartThings cloud | Local network |
|---|---|---|
| Used for | All remote buttons, power state, inputs | Typing text, listing and opening apps |
| Endpoint | `https://api.smartthings.com/v1` | `wss://<tv-ip>:8002/api/v2/channels/samsung.remote.control` |
| Auth | Personal Access Token (Bearer) | TV pairing token, issued after you click "Allow" on the TV |
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

### Local network (Samsung Tizen remote protocol)

1. **Discovery.** SSDP `M-SEARCH` for `urn:samsung.com:device:RemoteControlReceiver:1` (older TVs) and `urn:dial-multiscreen-org:service:dial:1` (newer TVs, e.g. 2025 models), keeping only replies whose `SERVER` header says Samsung. A manually entered IP is used only when discovery finds nothing, so a TV that gets a new IP from the router is found again automatically.
2. **Connect.** A WebSocket to port 8002, with the app name base64-encoded in `name` and the saved pairing token in `token`. The TV replies `ms.channel.connect`; the first time, that reply includes the new token. The TV uses a self-signed certificate, which the app trusts only for the TV's own address.
3. **Typing.** `ms.remote.control` with `TypeOfRemote: "SendInputString"` and base64 text, then `SendInputEnd` to apply it.
4. **Apps.** `ms.channel.emit` with `ed.installedApp.get` lists the apps. `ed.apps.launch` opens one, using `DEEP_LINK` for web apps (`app_type` 2) and `NATIVE_LAUNCH` for the others.

The TV drops idle connections, so a failed send reconnects once and retries.

### Code layout

Clean architecture: the UI depends on the core, and the core's domain doesn't depend on any network or storage code.

```
Sources/TVRemoteCore/
  Domain/           RemoteKey, TV, TVApp, TVCommand, and the ports
                    TVController, TVKeyboard, TVAppLauncher, TokenStore
  Infrastructure/   SmartThingsClient (cloud), LocalTVRemote + LocalRemoteProtocol
                    (local WebSocket), SSDPDiscovery, TVHostFinder, FileTokenStore
Sources/TVRemoteApp/  SwiftUI MenuBarExtra: views and view models
Tests/TVRemoteCoreTests/  Swift Testing, using fake HTTP transport and token stores
scripts/bundle.sh     builds TVRemote.app (Info.plist, ad-hoc signature)
```

### Where data is stored

| What | Where |
|---|---|
| SmartThings token | `~/Library/Application Support/TVRemote/smartthings-token` |
| TV pairing token | `~/Library/Application Support/TVRemote/local-tv-token` |
| Manually entered TV IP, favorite apps | app defaults (`com.mo.TVRemote`) |

The token folder is readable only by your user account (0700, with files 0600). Tokens aren't kept in the Keychain because the app is ad-hoc signed: the Keychain treats every rebuild as a new app and asks for your password again.

## Limitations

- **SmartThings tokens expire after 24 hours.** Personal Access Tokens created since late 2024 are short-lived. When one expires, the remote asks for a new one. A long-lived connection would need SmartThings OAuth through a registered SmartApp, which this app doesn't implement.
- **Power on depends on the TV.** Turning the TV on from the cloud only works if network standby is enabled on the TV. Turning it off always works.
- **Power and mute state can drift.** Power is re-read each time you open the remote. Mute state is only tracked locally, so it can get out of sync if you use the physical remote.
- **Typing is sent on Return, and only into Samsung's keyboard.** Apps that draw their own on-screen keyboard (possibly YouTube) may ignore the text.
- **Some TVs don't list apps.** Some newer Samsung firmware doesn't answer `ed.installedApp.get`. Shortcuts then show "The TV didn't answer".
- **App tiles show letters, not icons.** Tiles are colored letters; the TV's icons aren't downloaded.
- **The local features need the same network.** Typing and shortcuts don't work away from home, though the cloud buttons do.
- **Older TVs aren't supported.** Models from 2014–2015 use an older PIN-based pairing protocol.
- **It isn't notarized.** The app is ad-hoc signed for local use. Sharing a built copy would trigger Gatekeeper warnings on other Macs.
- **SwiftUI `@State` isn't used.** In the macOS 27 SDK, `@State` is a macro whose plugin ships only with Xcode. The views use the `State` type directly so the app builds with Command Line Tools alone.

## Status

| Feature | Verified on a real TV |
|---|---|
| SmartThings connection, TV detection | ✅ |
| Power toggle and the other cloud buttons | Not explicitly confirmed yet |
| D-pad arguments (`PRESS_AND_RELEASED`) | ❓ Not confirmed. Check here first if the D-pad does nothing. |
| Typing, app list, app launch | ❓ Not tested on a TV yet |

The protocol messages and API calls are covered by unit tests (`make test`). The rows marked ❓ still need a check against a real TV.

## License

[MIT](LICENSE) © 2026 Muhammad Ilham
