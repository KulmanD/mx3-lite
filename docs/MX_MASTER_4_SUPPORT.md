# MX Master 4 support roadmap

Research date: 2026-11-04. Status: planned; MX Master 4 compatibility has not
been validated by this project. This document records research and remaining
work; it does not implement device support or new settings.

## Goal

Support the MX Master 4 while preserving the small, event-driven worker that
makes mx3-lite useful. First qualify the existing gestures, side buttons, and
scrolling on the new hardware. Offer additional features through independent,
optional layers, with resource warnings only when measurements show a
substantial impact. Owning an MX Master 4 must not automatically enable extras.

## MX Master 3, 3S, and 4: relevant differences

The original MX Master 3 and the MX Master 3S are different baselines. The 3S
already has an 8K sensor and Quiet Clicks, so neither is an MX4-only addition.

| Area | MX Master 3 | MX Master 3S | MX Master 4 | Implication for mx3-lite |
| --- | --- | --- | --- | --- |
| Sensor maximum | 4,000 DPI | 8,000 DPI | 8,000 DPI | Validate gesture thresholds at different pointer speeds; DPI configuration is separate work. |
| Controls | Seven buttons, including a gesture button | Seven buttons, including a gesture button | Eight buttons, including a gesture button and Haptic Sense Panel / Actions Ring control | Discover actual macOS events; do not copy button IDs or treat the panel as the gesture button. |
| Haptic feedback | No MX4-style haptic system | No MX4-style haptic system | Configurable tactile feedback | Optional hardware/protocol investigation; basic support must work without it. |
| Scrolling | MagSpeed ratchet/free-spin and thumb wheel | MagSpeed ratchet/free-spin and thumb wheel | MagSpeed ratchet/free-spin and thumb wheel | Reuse the scroll path where verified; test event fields and burst handling. |
| Wireless | Bluetooth; original consumer model uses Unifying, Business variant uses Bolt | Bluetooth and Logi Bolt | Bluetooth and Logi Bolt; current Business package includes a USB-C receiver | Validate each transport separately and record the exact edition/receiver. |
| Clicks | Earlier click mechanism | Quiet Clicks | Quiet Clicks retained | No additional worker subsystem is needed for quieter hardware. |
| Body | About 141 g | About 141 g | About 150 g; revised shape and stain-resistant materials | Physical changes do not require resident software. |

Sources: Logitech's [MX Master 3 setup guide][mx3-setup] and
[Business specifications][mx3-spec], [MX Master 3S datasheet][mx3s-spec],
[MX Master 4 datasheet][mx4-spec], and [MX Master 4 setup guide][mx4-setup].
Business specifications describe that edition; they are not proof that every
consumer or Mac package has identical contents or requirements.

Two distinctions affect scope:

- **Panel input, haptic output, and Actions Ring are separate capabilities.**
  Logitech lists both a gesture button and the Haptic Sense Panel. Its Actions
  Ring is a software menu that requires Options+; receiving a panel event would
  not itself provide that menu. An independent radial menu would need its own
  implementation. See the [setup guide][mx4-setup].
- **Mouse battery use and Mac resource use need separate evidence.** Logitech
  documents a battery-saving option for haptics, but that does not establish a
  large CPU or RAM cost on the Mac. Windows 11 native haptics also do not establish
  an equivalent macOS API. See the [haptic feedback guide][mx4-haptics] and
  [product page][mx4-product].

No benchmark in this research establishes that an MX4-specific feature is
resource-heavy. Cost assessments below are design expectations to test.

## What the current code already provides

The starting point is the current implementation, not a new driver:

- [`MXMasterDeviceRegistry.swift`](../Sources/MX3Lite/MXMasterDeviceRegistry.swift)
  matches Logitech vendor `0x046D` and a product name containing `MX Master`.
  It does not restrict detection to a list of MX3 product IDs. An MX4 exposing
  those properties may already be detected; receiver exposure still needs
  physical verification. A device name match is not a compatibility test.
- [`GestureMapper.swift`](../Sources/MX3Lite/GestureMapper.swift) and
  [`MouseEventTap.swift`](../Sources/MX3Lite/MouseEventTap.swift) handle configured
  CGEvent button IDs and gestures. The existing defaults are gesture `5`, back
  `3`, forward `4`; these are not confirmed MX4 mappings.
- [`ScrollHandling.swift`](../Sources/MX3Lite/ScrollHandling.swift) transforms
  scroll events with bounded state. Even experimental inertia currently runs
  on incoming events; its name is not evidence of a background animation loop.
- [`HIDInspector.swift`](../Sources/MX3Lite/HIDInspector.swift) reports Button
  and Generic Desktop input values. It does not decode vendor-specific input
  reports or send hardware commands. A missing panel event in this inspector
  does not prove that the hardware cannot expose it.
- The [app architecture](APP_ARCHITECTURE.md) separates the temporary settings
  app from the worker. Settings load at startup; saved changes require a worker
  restart. No HID++ command layer, haptic controller, radial menu, or app profile
  engine is implemented.

`mxMasterOnly` is also a heuristic: CGEvent has no reliable per-device
vendor/product identity here. The registry excludes continuous scrolling, but
can classify another mouse's non-continuous scrolling while an MX Master is
connected. MX4 work must test mixed-device setups and must not claim perfect
device isolation from the current code.

## Layered feature selection

Use a lightweight default and independent feature switches. These are proposed
capability groups, not implemented UI, paid tiers, or a requirement to enable
every earlier optional group. Unsupported controls should explain the missing
capability rather than pretending to work.

| Layer | Proposed features | Default policy | Expected resource behavior and validation |
| --- | --- | --- | --- |
| Core compatibility | Existing gestures, back/forward, scroll direction/speed/smoothing | Preserve existing user choices; default for new installations after qualification | Reuse event callbacks and fixed-size state. No systematic idle regression. |
| Optional device controls | Panel-to-shortcut mapping, DPI, SmartShift, wheel settings, on-demand battery information | Off until explicitly selected; enable only verified capabilities | Prefer one-time configuration and device notifications. Protocol support and persistence remain unverified; do not add routine polling. |
| Optional haptics | Feedback for a mapped action, supported intensity/settings | Off | Send bounded output only when needed. Measure command cost and mouse battery effects separately; no assumption that haptics need a large resident service. |
| Optional interface | A local radial shortcut menu, app-specific mappings | Off; independently selectable from haptics | A menu may require a separate UI process; profiles may use app-activation notifications. Measure resident memory, active rendering, and observer overhead. Neither is automatically classified as heavy. |

Flow-style cross-computer networking, a plugin marketplace, arbitrary automation,
and firmware updates are outside the initial MX4 support scope. Reconsider them
only as separate proposals with an explicit benefit and resource budget.

### What disabled must mean

- Check feature settings before creating a subsystem. A disabled feature must
  have no feature-specific timers, observers, HID report subscriptions, output
  commands, UI process, or background tasks. Shared core subscriptions remain
  only where core behavior needs them.
- Keep optional UI frameworks and rendering out of the worker. If an interface
  needs a resident companion, launch it only when explicitly enabled and stop it
  when the feature is disabled and the change is applied.
- Preserve startup-only configuration initially. Make restart requirements
  clear and verify teardown after restart; do not introduce configuration polling
  just to support feature switches.
- Disabling an optional subsystem or losing its connection must leave core mouse
  controls usable. Do not silently enable a different feature as a fallback.
- Keep the normal worker free of periodic polling, runtime networking, normal
  logging, extra persistent threads, and automatic login startup. An optional
  feature does not waive the existing worker budget. Redesign or defer it if
  it cannot fit; measure any explicitly enabled companion separately.
- Runtime opt-out is not proof of zero download-size cost. Report changes in
  worker/app/archive size and consider separate optional components if a
  dependency would materially enlarge the lightweight distribution.

### Resource information and warnings

Show a warning before enabling a feature only after repeatable measurements
show a substantial cost. Small, bounded changes need no alarming prompt. An
unmeasured feature is **unmeasured**, not **heavy**; experimental status should
state that uncertainty without inventing CPU, memory, or battery figures.

Before shipping each optional feature, record:

1. Core-only, feature-disabled, and feature-enabled results on the same Mac,
   macOS version, build, transport, configuration, and fixed workload.
2. Total app-related memory and CPU, including companion processes, plus worker
   RSS and physical footprint separately. Also record idle wakeups, threads,
   active CPU, input latency, and distribution size. Measure visible-menu use
   separately from enabled-but-hidden idle.
3. An agreed numeric budget for that feature and what counts as substantial,
   expressed in absolute deltas as well as percentages. Set it before evaluating
   results; a percentage over a near-zero baseline is not enough.
4. Repeated results beyond measurement noise and a documented decision:
   acceptable without warning, acceptable only with opt-in and warning,
   redesign, or defer. Existing worker acceptance rules still apply.

If a warning is justified, name the affected resource, describe the measured
change and test context, explain any extra resident process, and offer
**Keep disabled** / **Enable feature**. Provide an easy way to disable it later.
Use real numbers from the published report, never placeholder estimates.

Follow the [performance experiment protocol](performance/README.md) and record
new evidence under `docs/performance/`. Keep the historical frozen-baseline
comparison required by that protocol and add a comparison against the current
release. The existing [final candidate report](performance/final-feature-candidate.md)
is historical MX3S evidence, not an MX4 benchmark or a promise for new layers.

## Remaining work

### 1. Establish hardware evidence

- [ ] Obtain an MX Master 4 test device and record edition, firmware, macOS,
  architecture, transport, receiver model, product name, vendor/product IDs,
  and exposed HID collections. Avoid publishing serial numbers.
- [ ] Run `mxmaster doctor --verbose` and foreground `mx3-lite --inspect` with
  competing mouse customization software stopped. Record press/release events
  for every control and both wheels over Bluetooth and Bolt independently.
- [ ] Distinguish gesture-button events from panel events. If ordinary input
  inspection is insufficient, add a development-only, bounded vendor-report
  inspector before deciding whether report decoding or button diversion is
  needed. Do not guess product IDs, control IDs, or command formats.
- [ ] Check behavior after a fresh pairing and after prior Options+/Tune
  configuration; identify firmware-persisted settings and hidden dependencies.

### 2. Qualify lightweight compatibility first

- [ ] Verify registry detection for each transport; change matching only where
  captured evidence requires it. Keep existing MX3/3S detection working.
- [ ] Add verified per-device mappings/capabilities only if existing configurable
  IDs are insufficient. Preserve current configuration files and defaults.
- [ ] Test one action per gesture hold, cancellation/recovery, back/forward,
  horizontal scrolling, ratchet/free-spin bursts, smoothing, and reversal.
- [ ] Test trackpad and second-mouse coexistence, disconnect/reconnect, mouse
  power cycle, sleep/wake, permission denial, and Start/Stop/duplicate-start.
- [ ] Run the idle and fixed active-input benchmarks for core-only MX4 use and
  repeat relevant MX3/3S regression checks. Record untested cases explicitly.
- [ ] Publish a model/transport validation matrix before claiming MX4 support.
  Confirm supported macOS versions from actual tests, not Options+ requirements.

### 3. Investigate optional capabilities independently

- [ ] Determine whether the panel can trigger a normal shortcut without a radial
  menu or haptic output. Offer that minimal mapping first if feasible.
- [ ] Establish which supported HID/HID++ features and report paths can configure
  DPI, SmartShift, haptic output, intensity, and battery notifications on macOS.
  The manufacturer pages cited here describe behavior, not an implementation API.
- [ ] Bound discovery, retries, and output rates; avoid blocking the event-tap
  callback. Define behavior on timeout, reconnect, unknown firmware, and an
  unsupported feature, including restoring temporary button diversion on exit.
- [ ] Determine which settings persist in the mouse, which require reapplication,
  and whether haptics can be controlled without Options+/Tune running.
- [ ] Prototype a radial menu and app profiles only if wanted after core support;
  measure each independently before choosing its process architecture.

### 4. Add selection and release gates

- [ ] Add explicit optional-feature settings to `config/defaults.json`, the worker
  configuration, and the native settings app; regenerate shared defaults and
  retain existing configuration compatibility.
- [ ] Add capability-aware UI and clear save/restart behavior. Keep core-only
  operation the default and explain unavailable device controls.
- [ ] Verify disabled subsystems create no background work; test enable/disable,
  reconnect, and optional-component failure without breaking core mappings.
- [ ] Set and measure per-feature budgets, then implement resource warnings only
  for features that demonstrably warrant them. Test combined enabled features
  for cumulative cost as well as each feature in isolation.
- [ ] Add meaningful configuration, mapping, protocol-fixture, and lifecycle tests
  with any implementation. Run `swift test`, debug/release builds, both architecture
  packaging checks, and the existing performance gates for runtime changes.
- [ ] Update compatibility claims and user documentation with measured results,
  limitations, and selected-layer behavior. Ship basic compatibility independently
  of unfinished optional features.

[mx3-setup]: https://support.logi.com/hc/hu/articles/360035271133-Getting-Started-MX-Master-3
[mx3-spec]: https://hub.sync.logitech.com/mx-master-3/post/specifications---mx-master-3-MD4Qfqsmr2wvjTX
[mx3s-spec]: https://www.logitech.com/content/dam/logitech/en/business/pdf/mx-master-3s-business-wireless-mouse.pdf
[mx4-spec]: https://www.logitech.com/content/dam/logitech/en/business/pdf/mx-master-4-business-datasheet.pdf
[mx4-setup]: https://hub.sync.logitech.com/mx-master-4/post/getting-started---mx-master-4-LSEt5tZXsbeMP3c
[mx4-haptics]: https://hub.sync.logitech.com/mx-master-4/post/haptic-feedback-guide-fgAEJmLZXL9iQXK
[mx4-product]: https://www.logi.com/en-us/shop/p/mx-master-4
