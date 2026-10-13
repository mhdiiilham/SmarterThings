# Contributing to SmarterThings

Thanks for helping. Bug reports, TV compatibility reports and pull requests are all welcome.

## Reporting bugs and TV compatibility

[Open an issue](../../issues/new/choose) using the bug report template. The most useful details are:

- your **TV model** (e.g. `UA50UE100FKXXD`, from the TV's Settings › Support › About This TV) and year
- your **macOS version**
- what you pressed, what you expected, and what happened
- any notice the app showed

Logs help a lot. After reproducing the problem, run:

```sh
log show --last 10m --info --predicate 'subsystem == "com.mhdiiilham.SmarterThings"'
```

## Development setup

You need macOS 26 and a Swift 6 toolchain. Xcode's Command Line Tools are enough.

```sh
make run     # debug build, restart the app
make test    # run the tests
make dmg     # release build → build/SmarterThings-<version>.dmg
```

A real Samsung TV (2016 or later) on the same network is needed to try changes end to end. The [README](README.md#how-it-works) explains the protocols.

## Code guidelines

- **Architecture.** `SmarterThingsCore` holds the domain (types and ports), the application logic (`PowerControl`) and the infrastructure (Wi-Fi, Bluetooth). `SmarterThings` is the SwiftUI menu bar app. The core never depends on the UI; inject dependencies through the ports.
- **Tests.** New behavior and logic need tests (Swift Testing, in `Tests/SmarterThingsCoreTests`). Keep protocol details (message formats, key codes, parsing) in pure functions so they can be tested without a TV. Real captured responses make good fixtures.
- **Style.** Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and the surrounding code: clear names, small functions, comments only for the *why*.
- **SwiftUI `@State`.** Use `State(initialValue:)` as a stored property instead of the `@State` macro, so the app keeps building with Command Line Tools alone (see the README).

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `chore:`. Write a short subject line plus a body that says what changed and why.
- Keep pull requests focused on one change, and run `make test` before opening one.
- Fill in the pull request template, including which TV you tested on.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE), and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
