<div align="center">
  <img src="docs/assets/mx3-lite-icon.png" width="128" height="128" alt="mx3-lite app icon">
  <h1>mx3-lite</h1>
  <p><strong>Essential MX Master gestures and scrolling controls for macOS, without keeping Logi Options+ running.</strong></p>
  <p>Native Swift, manually started, local-only, and built around a small event-driven worker.</p>

  <p>
    <a href="https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/actions/workflows/test.yml"><img src="https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/actions/workflows/test.yml/badge.svg?branch=main" alt="Test status"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/macOS-12%2B-black?logo=apple" alt="macOS 12 or newer">
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  </p>

  <p>
    <a href="#installation">Installation</a>
    &middot;
    <a href="config/README.md">Terminal and configuration guide</a>
    &middot;
    <a href="LICENSE">MIT License</a>
  </p>
</div>

## Why mx3-lite

mx3-lite focuses on the controls many MX Master users rely on every day while
keeping the runtime deliberately small and predictable.

- Native Swift worker and SwiftUI settings app
- Gesture-button desktop switching and Mission Control
- Back and forward side-button mappings
- MX Master-only scroll reversal and smoothing
- MacBook trackpad scrolling and gestures left unchanged in the recommended mode
- Manual Start and Stop with no automatic login item
- No account, telemetry, advertisements, updater, or runtime network access
- No Electron, Node.js, Python runtime, kernel extension, or persistent IPC socket
- No normal-mode background log, polling loop, or periodic status timer

This is not a complete replacement for every Logi Options+ feature. It does not
configure DPI, SmartShift, HID++ hardware settings, per-application profiles, or
device firmware.

## Features

| Area | Behavior |
| --- | --- |
| Gesture left | Switch desktops; direction can be reversed in Settings |
| Gesture right | Switch desktops; direction can be reversed in Settings |
| Gesture up | Open Mission Control |
| Gesture down | Send Control + Down, or disable the action |
| Back button | Send Command + `[` |
| Forward button | Send Command + `]` |
| Scrolling | Optional vertical/horizontal reversal, speed controls, and bounded smoothing |
| Wheel modes | Ratchet and free-spin handling with spike damping and a maximum step |
| Settings | Native Start/Stop, gesture, button, scroll, and diagnostic controls |
| Diagnostics | Read-only permission, config, worker, and device checks |
| Terminal | Optional `mxmaster` wrapper, inspector, foreground debug, and self-test commands |

Only one action is sent during each gesture-button hold. The default movement
threshold is intentionally conservative to reduce accidental desktop switches.

## Performance

The release helper remains event-driven. Pointer-movement delivery is enabled
only while a gesture is active, and normal operation does not use a polling loop
or periodic timer.

| Metric | Measured result |
| --- | ---: |
| Helper size | `433,528 bytes` |
| Increase over frozen baseline | `976 bytes` / `0.226%` |
| `__TEXT` segment | `212,992 bytes`, equal to baseline |
| Controlled idle CPU | `0.000000%` in the recorded 150.086-second run |
| Worker threads | `2`, stable |
| RSS | approximately `10.1 MiB` |
| Physical footprint | approximately `3.22 MiB` |
| Idle wakeups | `0` |
| Network sockets | `0` |
| Normal-mode log files | `0` |

These values come from one controlled 150.086-second idle run on the measured
candidate. They do not guarantee identical counters on every Mac or workload.
See the [complete candidate report](docs/performance/final-feature-candidate.md)
and [performance release matrix](docs/performance/performance-release-matrix.md)
for the environment, method, limitations, and feature-by-feature evidence.

## Compatibility and validation

- Requires macOS 12 Monterey or newer.
- Builds are validated for Apple Silicon (`arm64`) and Intel (`x86_64`).
- The final candidate was physically tested on one Logitech MX Master 3S with
  macOS 26.5.1.
- That test covered gestures, side buttons, ratchet and free-spin scrolling,
  reversal, pause/resume, trackpad coexistence, mouse reconnect, power cycle,
  sleep/wake recovery, and worker lifecycle.
- MX Master 3 support is implemented and expected, but the final validation
  matrix was not repeated on an MX Master 3.

This is single-device functional evidence, not a universal compatibility claim.
Connection-specific button IDs can differ, so diagnostics and inspector mode are
available when the defaults do not match another setup.

## Installation

### Current distribution status

An official Developer ID signed and notarized download is not available yet.
The historical v0.3.0 app asset is an older, ad-hoc-signed Apple Silicon
validation build and does not contain the final candidate. Until a new signed
release is published, installing the current source is the recommended path.

### Install the native app from source

1. Open Terminal.
2. Install Apple's command-line developer tools if they are not already present:

   ```sh
   xcode-select --install
   ```

3. Download and install mx3-lite:

   ```sh
   git clone https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased.git
   cd Mx-Master-3-For-mac-lightweight-swiftBased
   bash scripts/install-app.sh
   open "$HOME/Applications/mx3-lite.app"
   ```

The app is installed to `~/Applications/mx3-lite.app`. The optional terminal
wrapper is installed to `/usr/local/bin/mxmaster` and may ask for an administrator
password. Use `bash scripts/install-app.sh --skip-wrapper` to install only the app.

Local source builds are ad-hoc signed. On first launch, macOS may require you to
Control-click `mx3-lite.app`, choose **Open**, and confirm **Open**. Do not disable
Gatekeeper globally.

## macOS permissions

mx3-lite needs permission to observe the mouse and send the configured keyboard
shortcuts.

1. Open mx3-lite and select **Diagnostics**.
2. Open **Accessibility settings** and enable mx3-lite.
3. Open **Input Monitoring settings** and enable mx3-lite if macOS requires it.
4. If macOS lists the bundled `mx3-lite` helper separately, enable that entry too.
5. Quit and reopen the app after changing permissions.

The exact executable you run must have permission. Rebuilding or moving the app
can cause macOS to request permission again.

## Quick usage

1. Open mx3-lite.
2. Click **Start**. The status changes to **Running**.
3. Use the gesture, side-button, and scroll controls normally.
4. Quit the settings app with Command + Q if desired. The lightweight worker
   continues because Start and Stop are explicit choices.
5. Reopen mx3-lite and click **Stop** to stop completely. No worker remains after
   a successful stop.

Nothing starts automatically after login. Open mx3-lite and click **Start** when
you want to use it again.

## Settings overview

After changing a setting, click **Save**. If the app reports that a restart is
required, click **Restart now**.

| Setting | Guidance |
| --- | --- |
| Movement threshold | Start at `220`; lower triggers sooner, higher reduces accidental actions |
| Desktop direction | Reverse left/right if desktop movement feels opposite to the gesture |
| Down gesture | Choose Control + Down or disable it |
| Button IDs | Defaults are gesture `5`, back `3`, forward `4`; an empty value disables a mapping |
| Scroll transform | Keep **MX Master only** selected so the MacBook trackpad is unchanged |
| Wheel direction | Reverse vertical or horizontal scrolling independently |
| Multiplier and acceleration | Keep both at `1.0` until basic direction feels correct |
| Balanced (EMA) | Recommended responsive smoothing; factor `0.35` is the default |
| Dampen free-spin spikes | Useful when large free-spin bursts travel too far |
| Inertia | Experimental and optional; it can feel less immediate |
| Action backend | Keep **System Events** selected; CGEvent equivalence remains unqualified |

Use **Run diagnostics** if gestures or scrolling do not work. Diagnostics are
read-only: they do not change settings or send mouse or keyboard actions.

## Troubleshooting

### Gestures do nothing

Confirm the app says **Running**, run Diagnostics, grant any missing permission,
then Stop and Start the worker. If necessary, verify that the gesture button ID
is `5` or use inspector mode from the [technical guide](config/README.md).

### Desktop direction is wrong

Change **Reverse left and right desktop direction**, save, and restart the worker.

### Gestures trigger too easily

Increase **Movement threshold** in steps of 20 until the gesture feels deliberate.

### The trackpad scroll direction changed

Set **Scroll transform** to **MX Master only**. **All pointing devices** is a
fallback that intentionally changes trackpad scrolling too.

### Scrolling feels delayed or too strong

Keep **Balanced (EMA)** selected and reduce its factor, or disable smoothing.
Return Multiplier and Acceleration to `1.0` before tuning other values.

## Privacy and architecture

The native SwiftUI app is a transient control surface. The separate worker owns
the event tap, device detection, gesture state, scroll transformation, and
synthetic actions. Closing the settings app does not add another resident UI
process; only the worker remains after Start.

- Configuration stays in
  `~/Library/Application Support/mx3-lite/config.json`.
- Configuration is read once when the worker starts.
- Scroll events are modified and returned in place rather than reposted.
- Smoothing keeps bounded constant-size state and uses no background timer in
  the normal EMA or spike-damping modes.
- System Events is launched only when a mapped action actually fires.
- There is no telemetry, runtime network path, updater, login item, launch agent,
  normal-mode log file, or automatic worker start.

See [Native app architecture](docs/APP_ARCHITECTURE.md) for the process and
lifecycle contract.

## Project status and limitations

The integrated candidate has passing CI, controlled idle evidence, and a
maintainer-run single-device physical validation matrix. The following work is
deliberately not represented as complete:

- Official Developer ID signing, notarization, stapling, and clean-machine tests
- A fixed combined active-input CPU and latency benchmark
- Qualification of CGEvent as an equivalent action backend
- DPI, SmartShift, HID++ hardware configuration, profiles, and firmware support
- Broad validation across every MX Master model, connection type, and macOS release

Before making the repository public or distributing binaries, review
[Publication readiness](docs/PUBLICATION_READINESS.md) and the
[Public release guide](docs/PUBLIC_RELEASE.md).

## Building from source

```sh
swift build
swift test
swift build -c release
bash scripts/build-app.sh
```

Build separate validation archives for Apple Silicon and Intel:

```sh
bash scripts/package-release.sh --arch arm64
bash scripts/package-release.sh --arch x86_64
```

These default to ad-hoc signing and are validation artifacts, not official
public downloads. Developer ID and notarization instructions are in the
[public release guide](docs/PUBLIC_RELEASE.md). Terminal commands, configuration
fields, inspector mode, and debug tools are in the
[technical guide](config/README.md).

## Uninstall

1. Open mx3-lite and click **Stop**.
2. Quit the app.
3. Run the included uninstall scripts from the project folder:

   ```sh
   bash scripts/uninstall.sh
   bash scripts/uninstall-app.sh
   ```

The user configuration is intentionally preserved. Remove it manually only if
you also want to erase your saved settings:

```text
~/Library/Application Support/mx3-lite/config.json
```

## Contributing

Focused bug reports and reproducible hardware observations are useful,
especially when they include the mouse model, connection method, macOS version,
button IDs, and read-only Diagnostics output. Run `swift test` and both debug and
release builds before proposing source changes.

The project is available under the MIT License. Open an issue before investing
in a large change.

## License

mx3-lite is available under the [MIT License](LICENSE).

## Trademark disclaimer

This project is independent and is not affiliated with or endorsed by Logitech.
Logitech, MX Master, and Logi Options+ are trademarks of their respective owner.
