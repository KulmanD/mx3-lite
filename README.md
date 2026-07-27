# mx3-lite

Lightweight gesture and scrolling control for Logitech MX Master 3 and MX Master 3S on macOS, without Logi Options+.

mx3-lite lets the thumb gesture button switch desktops and open Mission Control. It can also reverse and smooth the MX Master scroll wheel without changing MacBook trackpad scrolling.

## What it does

- Gesture button + move left: switch to the next desktop
- Gesture button + move right: switch to the previous desktop
- Gesture button + move up: open Mission Control
- Gesture button + move down: Control + Down, or disabled in Settings
- Back side button: Command + `[`
- Forward side button: Command + `]`
- Optional MX Master-only scroll reversal and smoothing

Only one action is sent each time the gesture button is held. The default movement threshold is deliberately conservative to prevent accidental desktop switching.

## Requirements

- macOS 12 Monterey or newer
- Logitech MX Master 3 or MX Master 3S
- Accessibility permission
- Input Monitoring permission may also be required

## Install the app

1. Open the [latest mx3-lite release](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/releases/latest).
2. Under **Assets**, download the app ZIP for your Mac:
   - Apple Silicon (M1, M2, M3, M4, or newer): file ending in `macos-arm64.zip`
   - Intel Mac: file ending in `macos-x86_64.zip`
   Do not download GitHub's automatic source ZIP unless you want to build the app yourself.
3. Open the downloaded ZIP.
4. Move **mx3-lite.app** into your **Applications** folder.
5. Control-click **mx3-lite.app**, choose **Open**, then confirm **Open**.

An official release should be Developer ID signed and notarized by Apple. If
you build the validation archive yourself, it is only ad-hoc signed and macOS
may require Control-click, **Open** on first launch. This approves that specific
app without disabling Gatekeeper for the rest of your Mac.

## Allow macOS permissions

1. Open **mx3-lite**.
2. Select the **Diagnostics** tab.
3. Click **Accessibility settings**.
4. Enable **mx3-lite**. If it is not listed, click `+` and select `mx3-lite.app` from Applications.
5. Return to mx3-lite and click **Input Monitoring settings**.
6. Enable **mx3-lite** there as well if macOS requires it.
7. Quit and reopen mx3-lite after changing permissions.

If macOS shows the bundled `mx3-lite` helper separately, enable that entry too. **Run diagnostics** reports which permission or device check still needs attention.

## Start and stop

Open mx3-lite and click **Start**. The status light turns green when gesture control is running.

You can then quit the settings app with `Command + Q`. The small worker continues running so the mouse controls keep working. Closing the red window may leave the settings app open, as with many Mac apps.

Nothing starts automatically after login:

- To start later, open mx3-lite and click **Start**.
- To stop completely, reopen mx3-lite and click **Stop**.
- When stopped, no mx3-lite worker remains running.

## Settings guide

After changing a setting, click **Save**. If the app shows **Saved changes require a worker restart**, click **Restart now**.

### General

**Keep gesture control running** starts or stops the worker.

**Action backend** controls how macOS keyboard shortcuts are sent. Keep **System Events** selected unless desktop switching does not work on your Mac. **CGEvent** is the alternative.

### Gestures

**Movement threshold** controls how far the mouse must move while the gesture button is held:

- Lower value: triggers sooner, but may cause accidental actions.
- Higher value: requires a larger movement.
- Recommended starting value: `220`.

**Reverse left and right desktop direction** changes which desktop is selected when moving left or right. It is enabled by default.

**Reverse vertical gesture direction** is useful if moving up behaves like moving down on your Mac.

**Down gesture** can send Control + Down or be disabled.

The default button IDs are Gesture `5`, Back `3`, and Forward `4`. Leave these unchanged for an MX Master 3/3S unless the buttons are not detected. An empty field disables that button mapping.

### Scrolling

**Transform** controls which devices receive the scroll settings:

- **MX Master only**: recommended; leaves the MacBook trackpad unchanged.
- **All pointing devices**: fallback only; also changes trackpad scrolling.
- **Disabled**: does not modify scrolling.

**Reverse vertical wheel** changes the main wheel direction. **Reverse horizontal wheel** does the same for horizontal scrolling.

**Multiplier** changes overall scroll speed. Start at `1.0`. **Acceleration** increases the response to faster wheel movement. **Ratchet multiplier** affects click-by-click wheel mode. **Maximum step** limits large free-spin bursts.

**Smooth MX Master scrolling** enables smoothing:

- **Balanced (EMA)**: recommended, responsive smoothing for normal use.
- **Dampen free-spin spikes**: useful when free-spin scrolling jumps too far.
- **Inertia (experimental)**: optional and may feel less immediate.

The recommended smoothing factor is `0.35`. Higher values feel smoother but can add more delay. Use **Free-spin damping** to shorten large free-spin bursts.

### Diagnostics

Click **Run diagnostics** when gestures or scrolling do not work. It checks the app installation, configuration, worker status, permissions, and whether an MX Master is detected. It does not change settings or send any mouse or keyboard actions.

## Common problems

### Gestures do nothing

1. Confirm the status says **Running**.
2. Run **Diagnostics** and grant any missing permission.
3. Click **Stop**, then **Start** after changing permissions.
4. Confirm the Gesture button ID is `5`.

### Desktop direction is wrong

Open **Gestures** and change **Reverse left and right desktop direction**, then Save and restart the worker.

### Gestures trigger too easily

Increase **Movement threshold** in steps of 20 until it feels comfortable.

### The trackpad scroll direction changed

Open **Scrolling** and set **Transform** to **MX Master only**. Do not use **All pointing devices** unless device-specific filtering does not work on your Mac.

### Scrolling feels delayed or too strong

Keep **Balanced (EMA)** selected and reduce the smoothing factor, or turn smoothing off. Return Multiplier and Acceleration to `1.0` if scrolling is too strong.

## Privacy and resource use

- No telemetry
- No network access
- No advertisements
- No automatic updates
- No login item or launch agent
- No background logging during normal use
- Event-driven worker with no polling or periodic status checks

The settings window does not need to remain open. Only the lightweight worker stays running after Start.

## Measured performance

The final candidate helper is `433,528 bytes`, an increase of `976 bytes`
(`0.226%`) over the frozen baseline. Its `__TEXT` segment is `212,992 bytes`,
equal to the baseline.

In one controlled 150.086-second idle run on an Apple Silicon Mac with macOS
26.5.1 and an MX Master 3S connected, the worker recorded zero CPU-time growth,
zero package-idle and interrupt wakeups, two stable threads, and flat memory.
RSS was approximately `10.1 MiB`; physical footprint was approximately
`3.22 MiB`, which is substantially lower than RSS. No network sockets or
normal-mode log files were open. These values describe this specific run, not
a guarantee for every Mac or workload.

See the [complete performance report](docs/performance/final-feature-candidate.md)
for the environment, exact measurements, interpretation, and remaining tests.
Maintainers can reproduce the same measurement shape with:

```bash
bash scripts/performance/measure-candidate.sh \
  --label final-feature-candidate-clean \
  --runs 1 \
  --duration 150 \
  --interval 30 \
  --warmup 10 \
  --skip-build
```

## Remove mx3-lite

1. Open mx3-lite and click **Stop**.
2. Quit the app.
3. Move `mx3-lite.app` from Applications to the Trash.

Your settings file is kept separately so an update or reinstall does not erase your preferences. It is stored at:

```text
~/Library/Application Support/mx3-lite/config.json
```

## For developers and terminal users

Source-build instructions, terminal commands, configuration details, inspector mode, and debug tools are in the [technical guide](config/README.md).

Maintainers preparing signed Apple Silicon and Intel downloads should follow
the [public release guide](docs/PUBLIC_RELEASE.md). Release credentials are
owner-controlled and are never stored in this repository.

The project is native Swift. It does not use Electron, Node.js, Python, a kernel extension, a launch agent, or an auto-updater.
