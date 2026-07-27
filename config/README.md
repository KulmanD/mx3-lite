# mx3-lite

`mx3-lite` is a native macOS Swift worker and optional SwiftUI control app for lightweight Logitech MX Master 3 gesture control without Logi Options+.

It has no telemetry, no network access, no auto update, and no automatic startup. It only runs when started manually.

For app-first installation and settings instructions, see the [non-technical user guide](../README.md).

## Build

```sh
swift build -c release
```

### Development tests

The repository contains focused unit tests for config validation, gesture state, scroll smoothing, and worker identity handling:

```sh
swift test
```

Tests are development-only. They are not linked into the release executable, installed by `scripts/install.sh`, started by `mxmaster on`, or included in the lightweight sharing ZIP.

The binary is created at:

```sh
.build/release/mx3-lite
```

Install the `mxmaster` terminal wrapper:

```sh
scripts/install.sh
```

The installer runs `swift build -c release` and creates `/usr/local/bin/mxmaster`. The wrapper calls the release binary from this project path. If you move the project folder, run `scripts/install.sh` again.

Uninstall only the wrapper:

```sh
scripts/uninstall.sh
```

This removes `/usr/local/bin/mxmaster` only. It does not remove the project, config, logs, or build artifacts.

No launch agent is installed. Nothing starts automatically on login.

## Native macOS app

Build the native SwiftUI control app and its bundled worker:

```sh
bash scripts/build-app.sh
open dist/mx3-lite.app
```

The app provides manual Start/Stop, gesture and scroll settings, atomic config saving, restart-required state, read-only diagnostics, and links to the required macOS privacy panes. It has no telemetry, network access, updater, login item, launch agent, periodic status timer, or automatic worker start.

Install the app to `~/Applications/mx3-lite.app` and update the terminal wrapper to use its bundled helper:

```sh
bash scripts/install-app.sh
```

The app installation itself does not need administrator access. Updating `/usr/local/bin/mxmaster` may ask for `sudo` in an interactive terminal. To install only the app and leave the current wrapper unchanged:

```sh
bash scripts/install-app.sh --skip-wrapper
```

To uninstall, first remove an app-targeting wrapper and then remove the app:

```sh
bash scripts/uninstall.sh
bash scripts/uninstall-app.sh
```

The uninstall scripts preserve the user config. Nothing is configured to start at login.

Create a standalone versioned app archive:

```sh
bash scripts/package-app.sh
```

Local app builds are ad-hoc signed. Public distribution without macOS Gatekeeper warnings requires a Developer ID Application certificate and Apple notarization; the repository does not pretend those credentials are present.

## Performance

Normal mode is event-driven and has no polling loop or periodic timer. Pointer-movement delivery is enabled only while the gesture button is held; button and scroll handling remain available when required by the config. Development profiling found zero measurable CPU growth during a verified strict-idle interval and a stable low-single-digit MiB physical footprint.

See the [performance and stability report](../docs/PERFORMANCE.md) for the measurement method, controlled before/after results, lifecycle stress test, and hardware-dependent checks that could not be repeated during the profiling session.

## Sharing / installing on another Mac

To share this project with another Mac, copy the whole project folder, not only the wrapper.

Required project files/folders:

- `README.md`
- `Package.swift`
- `Sources/`
- `app/`
- `scripts/`
- `config/README.md`
- `config/defaults.json`
- `docs/PERFORMANCE.md`
- `docs/APP_ARCHITECTURE.md`
- `.gitignore` if present

Do not share/build artifacts unless needed:

- `.build/` can be omitted
- `/usr/local/bin/mxmaster` should not be copied manually because it points to a machine-specific path
- `~/Library/Application Support/mx3-lite/config.json` is user-specific and optional. It is not copied into the sharing ZIP.
- `config/defaults.json` is the neutral source of truth for generated compiled defaults.

Recommended sharing package:

```sh
bash scripts/package.sh
```

This creates `mx3-lite.zip` in the parent directory. The script validates the required project files and excludes `.build/`, `.git/`, `.github/`, `.swiftpm/`, `DerivedData/`, `dist/`, development-only `Tests/`, Xcode artifacts, and `.DS_Store` files. An existing ZIP is replaced only after the new archive passes verification.

On the other Mac:

```sh
unzip mx3-lite.zip
cd mx3-lite
bash scripts/install.sh

# Optional on a new installation only: start from the bundled defaults.
mkdir -p "$HOME/Library/Application Support/mx3-lite"
cp config/defaults.json "$HOME/Library/Application Support/mx3-lite/config.json"

mxmaster config
mxmaster on
```

macOS permissions:

The other Mac may need to allow Terminal and/or `mx3-lite` in:

- System Settings -> Privacy & Security -> Accessibility
- System Settings -> Privacy & Security -> Input Monitoring

Notes:

- The wrapper is installed to `/usr/local/bin/mxmaster`.
- The wrapper points to the local project path at install time.
- If the project folder is moved later, run `bash scripts/install.sh` again.
- The config file lives separately at `~/Library/Application Support/mx3-lite/config.json`.
- The neutral defaults file lives at `config/defaults.json`. Do not copy it over an existing user config unless you intend to replace your settings.
- Button IDs may differ on another Mac or connection method, so use inspect/debug if needed.

Helper commands:

```sh
# Build
swift build -c release

# Create a lightweight sharing ZIP
bash scripts/package.sh

# Build / install the native app
bash scripts/build-app.sh
bash scripts/install-app.sh

# Create a standalone app ZIP
bash scripts/package-app.sh

# Install wrapper
bash scripts/install.sh

# Uninstall wrapper
bash scripts/uninstall.sh

# Start / stop / status
mxmaster on
mxmaster off
mxmaster status

# Config
mxmaster config

# Read-only readiness check
mxmaster doctor
mxmaster doctor --verbose

# Debug
mxmaster debug
mxmaster scroll-debug
```

## Permissions

macOS must allow the installed `mx3-lite` binary to observe mouse input and post keyboard shortcuts.

Grant:

- Accessibility: required for the CGEvent tap and synthetic key events.
- Input Monitoring: may be required for IOHID inspection and low-level mouse input visibility.

Go to System Settings -> Privacy & Security -> Accessibility / Input Monitoring and add the exact binary you run.

If you rebuild or move the binary, macOS may treat it as a different executable and require permission again.

## Inspect first

Do not assume MX Master 3 button IDs. Run inspector mode first:

```sh
mx3-lite --inspect
```

Then press:

- thumb / gesture button
- back side button
- forward side button

Use the `cg button ... button=N` values from the output. IOHID usage values are also printed for cross-checking, but the runtime mappings use CGEvent button numbers.

Example inspector lines:

```text
cg button otherMouseDown button=3 clickState=1 loc=(900,500)
cg button otherMouseUp button=3 clickState=1 loc=(900,500)
hid product="MX Master 3" usagePage=0x9 usage=0x4 button=4 value=1
```

## Configure

`config/defaults.json` is the one editable authority for first-run values.
`scripts/generate-config-defaults.swift` generates target-local constants for
the terminal worker and native app, and CI rejects stale generated files. The
worker does not parse the bundled file at runtime. Existing user config files
are never silently migrated or overwritten.

Create the default config file:

```sh
mx3-lite init-config
```

Default path:

```text
~/Library/Application Support/mx3-lite/config.json
```

Default config, based on the captured MX Master 3S CGEvent button IDs:

```json
{
  "buttons" : {
    "back" : 3,
    "forward" : 4,
    "gesture" : 5
  },
  "actionBackend" : "systemEvents",
  "allowGlobalScrollTransform" : false,
  "downAction" : "ctrlDown",
  "freeSpinDamping" : 0.75,
  "invertDesktopGestureDirection" : true,
  "invertHorizontalScroll" : false,
  "invertVerticalScroll" : true,
  "invertY" : false,
  "maxScrollStep" : 8,
  "ratchetStepMultiplier" : 1,
  "scrollAcceleration" : 1,
  "scrollDeadzone" : 0,
  "scrollMultiplier" : 1,
  "scrollTransformMode" : "mxMasterOnly",
  "smoothScroll" : true,
  "smoothScrollFactor" : 0.35,
  "smoothScrollMode" : "ema",
  "threshold" : 220
}
```

Set a button ID to `null` to disable that mapping. For example:

```json
{
  "buttons" : {
    "back" : null,
    "forward" : 4,
    "gesture" : 5
  },
  "actionBackend" : "systemEvents",
  "allowGlobalScrollTransform" : false,
  "downAction" : "ctrlDown",
  "freeSpinDamping" : 0.75,
  "invertDesktopGestureDirection" : true,
  "invertHorizontalScroll" : false,
  "invertVerticalScroll" : true,
  "invertY" : false,
  "maxScrollStep" : 8,
  "ratchetStepMultiplier" : 1,
  "scrollAcceleration" : 1,
  "scrollDeadzone" : 0,
  "scrollMultiplier" : 1,
  "scrollTransformMode" : "mxMasterOnly",
  "smoothScroll" : true,
  "smoothScrollFactor" : 0.35,
  "smoothScrollMode" : "ema",
  "threshold" : 220
}
```

`threshold` is measured in accumulated mouse delta while the gesture button is held. The default `220` is intentionally conservative to avoid accidental Mission Control / desktop switching.

`invertDesktopGestureDirection` controls only horizontal desktop gestures:

- `true`: gesture-left posts the same action as `mxmaster test-right`; gesture-right posts the same action as `mxmaster test-left`.
- `false`: gesture-left posts the same action as `mxmaster test-left`; gesture-right posts the same action as `mxmaster test-right`.

Vertical gestures are unchanged. Gesture-up always posts the same action as `mxmaster test-up`.

`actionBackend` can be:

- `"cgEvent"`: HID-level `CGEvent` keyDown/keyUp posting.
- `"systemEvents"`: default for now, using System Events `key code 123/124/126 using control down` for Ctrl+Left/Right/Up.

Scroll transform settings:

- `scrollTransformMode`: `"mxMasterOnly"`, `"global"`, or `"disabled"`.
- `"mxMasterOnly"` is the default. It detects connected Logitech devices with vendor ID `0x046D` and product names containing `MX Master`, then avoids continuous scroll events that are likely from the MacBook trackpad.
- `"global"` is a fallback that transforms every non-gesture scroll event, including trackpad events.
- `"disabled"` passes all non-gesture scroll events through unchanged.
- `allowGlobalScrollTransform`: legacy field retained for config visibility; ignored by the current transformer.
- `invertVerticalScroll`: multiplies scroll axis 1 by `-1`.
- `invertHorizontalScroll`: multiplies scroll axis 2 by `-1`.
- `scrollMultiplier`: scales both scroll axes.
- `scrollAcceleration`: optional nonlinear acceleration. `1.0` is neutral.
- `ratchetStepMultiplier`: extra multiplier for clicky ratchet wheel steps. `1.0` is neutral.
- `smoothScroll`: enables the configured smoothing mode after inversion and scaling. The default is enabled but conservative.
- `smoothScrollMode`: `"ema"`, `"dampenSpikes"`, or `"inertia"`.
- `smoothScrollFactor`: for `"ema"`, how much previous scroll state is retained. `0.35` reduces jitter without adding a long tail.
- `scrollDeadzone`: drops tiny transformed deltas at or below this value. `0` disables the deadzone.
- `maxScrollStep`: clamps final transformed steps. `8` is a conservative cap for free-spin bursts.
- `freeSpinDamping`: in `"dampenSpikes"` mode, scales clamped spike bursts. `0.75` keeps bursts shorter.

When `scrollTransformMode` is `"mxMasterOnly"`, inversion and smoothing are applied only to events classified as MX Master scroll events. MacBook trackpad events should pass through unchanged. In `"global"` fallback mode, scroll transform settings apply to every non-gesture scroll event.

`mx3-lite --debug-scroll` prints each stage:

- raw delta
- after inversion
- after multiplier / acceleration
- after smoothing
- after max step clamp

Recommended presets:

```json
{
  "smoothScroll" : true,
  "smoothScrollMode" : "ema",
  "smoothScrollFactor" : 0.35,
  "maxScrollStep" : 8
}
```

Use this as the default starting point. It reduces jitter while keeping wheel response close to immediate.

```json
{
  "smoothScroll" : true,
  "smoothScrollMode" : "dampenSpikes",
  "maxScrollStep" : 8,
  "freeSpinDamping" : 0.75
}
```

Use this if free-spin mode sends occasional large bursts.

```json
{
  "smoothScroll" : false,
  "scrollMultiplier" : 1,
  "maxScrollStep" : 100
}
```

Use this to keep inversion/device filtering with no smoothing and a very loose safety clamp.

`"inertia"` is experimental and optional. It uses lightweight fractional carry on incoming scroll events rather than a background timer by default, because timer-based synthetic scroll can feel laggy and is more CPU-sensitive.

Config validation is conservative. Unknown `actionBackend` values fall back to `"systemEvents"`, unknown `scrollTransformMode` values fall back to `"mxMasterOnly"`, `smoothScrollFactor` is clamped to `0...0.95`, `scrollMultiplier` is clamped to `0.1...5`, and `maxScrollStep` is clamped to `1...100`. `mxmaster config` prints warnings when a value was clamped or replaced.

CGEvent scroll events do not expose a reliable vendor/product device identity. `mxMasterOnly` uses IOHIDManager to detect MX Master devices and recent MX Master wheel input, plus CGEvent continuity fields to avoid transforming trackpad scrolling. If that is not sufficient on a specific macOS setup, use `mx3-lite --debug-scroll` to inspect the event fields, or set `"scrollTransformMode" : "global"` as a fallback.

If vertical gestures are reversed on your machine, set:

```json
"invertY" : true
```

Set `"downAction" : "disabled"` if you do not want slide down to send `Ctrl + Down Arrow`.

## Run

Start manually:

```sh
mxmaster on
```

Stop completely:

```sh
mxmaster off
```

Check state:

```sh
mxmaster status
```

Toggle:

```sh
mxmaster toggle
```

Wrapper commands:

```sh
mxmaster on
mxmaster off
mxmaster toggle
mxmaster status
mxmaster debug
mxmaster scroll-debug
mxmaster config
mxmaster doctor
mxmaster test-left
mxmaster test-right
mxmaster test-up
```

Direct `mx3-lite` subcommands also work:

```sh
mx3-lite on
mx3-lite off
mx3-lite status
mx3-lite toggle
mx3-lite init-config
mx3-lite --run-foreground --debug
mx3-lite --print-config
mx3-lite doctor
mx3-lite --test-left
mx3-lite --test-right
mx3-lite --test-up
mx3-lite --debug-scroll
```

When `mxmaster off` succeeds, the worker process is terminated and no `mx3-lite` worker remains running.

Lifecycle commands are serialized with a local file lock to prevent duplicate workers. The PID metadata also records the worker executable path and process start time; `status` and `off` revalidate that identity so stale or reused PIDs are never signaled as mx3-lite workers. Legacy numeric PID files are migrated only when the live process matches the installed mx3-lite executable.

## Mappings

Each mapping is inactive if its required button ID is `null` or missing from `config.json`.

Configured behavior:

- Back side button -> `Cmd + [`
- Forward side button -> `Cmd + ]`
- Hold gesture button and slide left -> `Ctrl + Left Arrow`
- Hold gesture button and slide right -> `Ctrl + Right Arrow`
- Hold gesture button and slide up -> `Ctrl + Up Arrow`
- Hold gesture button and slide down -> `Ctrl + Down Arrow`, unless disabled

After one gesture action triggers, further movement is ignored until the gesture button is released.

## Debugging

Normal background operation is silent.

Debug logging is only enabled when requested:

```sh
mxmaster on --debug
```

For live gesture debugging in the foreground:

```sh
mxmaster debug
```

This prints relevant event types, button numbers, location, movement deltas, scroll axes, and gesture state while the process runs in the terminal. Stop any background worker first with `mxmaster off`.

For deterministic action backend tests:

```sh
mxmaster test-left
mxmaster test-right
mxmaster test-up
```

These commands do not use mouse gestures. They directly post Ctrl+Left, Ctrl+Right, or Ctrl+Up using the parsed `actionBackend`.

For exact config provenance:

```sh
mxmaster config
```

This prints the config path, whether the file existed or was created, the parsed values, and whether each value came from `config.json` or defaults.

For installation and permission diagnostics:

```sh
mxmaster doctor
mxmaster doctor --verbose
```

Doctor checks the wrapper target, executable, config parsing and sources, PID state, Accessibility, Input Monitoring, connected MX Master devices, and active behavior modes. It is read-only: it does not start or stop the worker, create or edit config, request permissions, post keys, transform scrolling, write logs, or access the network. The verbose form shows additional local paths and details.

For scroll transform debugging:

```sh
mxmaster scroll-debug
```

This foreground mode prints every scroll event with raw axes, transformed axes, source fields, connected MX Master devices, MX Master classification, scroll flags, and whether the event was returned modified or passed through unchanged.

Debug log:

```text
~/Library/Logs/mx3-lite.log
```

Foreground inspection always prints events because that is its purpose.
