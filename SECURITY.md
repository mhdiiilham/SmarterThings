# Security Policy

## Supported versions

Only the [latest release](../../releases/latest) receives security fixes.

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them privately through GitHub's [private vulnerability reporting](https://github.com/mhdiiilham/SmarterThings/security/advisories/new) instead.

Include what you found, how to reproduce it, and the impact you expect. You'll get a reply within a week. Once a fix is released, the advisory can be published, with credit to you if you'd like.

## What's in scope

SmarterThings talks to TVs on your local network and acts as a Bluetooth keyboard, so these are the areas that matter most:

- **The TV pairing token**, stored in `~/Library/Application Support/SmarterThings/` (folder 0700, file 0600)
- **TLS to the TV.** The TV uses a self-signed certificate, which the app trusts only for the TV's own address.
- **Bluetooth keyboard input.** Key presses are captured only while SmarterThings' own menu is open and typing is turned on.
- **Network input** from devices answering discovery or pretending to be the TV

Vulnerabilities in Samsung TV firmware itself should be reported to Samsung.
