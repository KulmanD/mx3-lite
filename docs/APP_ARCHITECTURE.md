# Native app architecture

## Goals

The macOS app provides native controls for the existing mx3-lite worker. It does not replace the worker's event-driven implementation and does not add SwiftUI, AppKit, polling, telemetry, network access, an updater, a launch agent, or a login item to the worker process.

## Process layout

```text
mx3-lite.app
  Contents/MacOS/mx3-lite-app       SwiftUI control application
  Contents/Helpers/mx3-lite         existing CLI and event worker
  Contents/Info.plist

/usr/local/bin/mxmaster             optional terminal wrapper
  -> mx3-lite.app/Contents/Helpers/mx3-lite
```

The app invokes the helper only for explicit actions: start, stop, status, config refresh, config save follow-up, and doctor. The worker remains a separate process so closing the settings window does not silently change the user's explicit on/off choice.

## Lifecycle contract

The project release binary and the app-bundled helper are copies at different paths. Lifecycle commands recognize either path only when its final executable name is exactly `mx3-lite`.

Before status or signaling, the lifecycle layer still requires all recorded process identity fields to match the live process:

- PID
- canonical executable path
- process start seconds
- process start microseconds

This preserves stale and reused PID protection while allowing `mxmaster off` to stop a worker started from the app, and allowing the app to recognize a worker started from the terminal. Any process with a different executable name is rejected.

The lifecycle lock and PID metadata remain in:

```text
~/Library/Application Support/mx3-lite/
```

## UI ownership

The app owns:

- running/stopped presentation and explicit Start/Stop actions
- config form state and atomic config writes
- config validation messages
- read-only doctor presentation
- links to macOS privacy settings and the config file

The helper owns:

- event taps and IOHIDManager
- gesture state and scroll transformation
- synthetic key actions
- worker PID lifecycle and duplicate prevention
- terminal output and debug modes

## Refresh policy

There is no periodic status timer. The app refreshes when:

- its main scene becomes active
- the user presses Refresh
- a start, stop, save, or diagnostic action completes

Configuration is read only during an explicit refresh or save workflow. The worker continues to read it once at startup, so the app shows a restart-required state after saving while the worker is running.

## Distribution

Local bundles are ad-hoc signed for structural validation. Public distribution should use a Developer ID Application certificate and Apple notarization. Those credentials are intentionally not assumed or emulated by repository scripts.
