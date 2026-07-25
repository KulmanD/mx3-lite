# Performance and stability report

Date: 2026-07-25

## Environment

- MacBook Pro `Mac16,8`
- Apple M4 Pro, 12 CPU cores, 24 GB RAM
- macOS 26.5.1 (25F80)
- Apple Swift 6.3.2, package language mode Swift 5.9
- Release build: `swift build -c release`
- Instruments was unavailable because this Mac has Command Line Tools rather than full Xcode. Equivalent command-line measurements used `proc_pid_rusage`, `sample`, `vmmap`, `lsof`, and `leaks`.

No profiling helper or measurement output is included in the installed application or sharing archive.

## Configuration

The worker used the current user configuration:

| Setting | Value |
| --- | --- |
| Gesture, back, forward buttons | `5`, `3`, `4` |
| Gesture threshold | `220` |
| Action backend | `systemEvents` |
| Desktop direction inversion | `true` |
| Scroll transform | `mxMasterOnly` |
| Vertical inversion | `true` |
| Smoothing | `ema`, factor `0.35` |
| Maximum scroll step | `5` |

## Results

### Extended worker run before optimization

The worker was sampled every 30 seconds for 20 minutes. The first 150 seconds were verified strict idle: CPU time, context switches, package-idle wakeups, and interrupt wakeups did not increase at all.

The rest of the run included ordinary pointer use and a controlled movement workload, so it is a mixed-activity measurement rather than an idle result.

| Measurement | Result |
| --- | --- |
| Duration | 1,201 seconds |
| Average CPU during mixed activity | 0.563% of one core |
| Threads | 2 throughout |
| Resident memory | 5.91-7.83 MiB |
| Physical footprint | 2.42-3.25 MiB |
| Package-idle wakeup growth | 0 |
| Interrupt-wakeup growth | 0 |
| Event-tap timeout recoveries observed | 0 |

`sample` showed the main thread blocked in `CFRunLoopRun`/`mach_msg` while idle. There was no polling loop or periodic timer. Memory reached a small plateau rather than growing with event count.

### Controlled pointer workload

A temporary external probe posted 12,000 `mouseMoved` events at 200 Hz over 60 seconds while the gesture button was not held. The same probe and release configuration were used before and after the change.

| Worker cost | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| CPU time | 1.495 s | 0.009 s | 99.4% |
| CPU per posted movement | 124.6 us | 0.8 us | 99.4% |
| Context switches | 14,510 | 148 | 99.0% |
| Mach system calls | 120,020 | 916 | 99.2% |

Before the change, normal mode subscribed to global `.mouseMoved` events continuously. The worker now uses two event taps:

- A primary button/scroll tap remains active because those events may be suppressed or modified.
- A movement tap is disabled while idle and enabled synchronously when gesture button 5 goes down. It is disabled again when button 5 goes up.
- Inspector and debug modes retain the complete event mask.

A separate probe held synthetic button 5, posted 200 below-threshold movement events, and released the button. The worker processed movement during the hold, stayed running, and did not cross the action threshold. This verifies the movement tap activation path without changing desktops.

### Post-change mixed input

A further five-minute sample contained active scrolling and pointer use, confirmed by an independent passive event counter, so it is not labeled idle. It averaged 0.279% of one core, remained at two threads, kept a 3.17-3.20 MiB physical footprint, and added no package-idle or interrupt wakeups. This provides a second bounded-memory check under real input after the optimization.

`leaks` reported 1,934 live allocations using 228 KiB and **0 leaks**. `lsof` showed no network sockets and no open log file; normal stdin, stdout, and stderr were attached to `/dev/null`.

### Lifecycle and recovery

Twenty-five automated `on`/duplicate `on`/`status`/`off` cycles completed with exactly one worker after each start, no worker after each stop, and no stale PID metadata. A foreground debug stress run handled more than 4,000 movement events plus concurrent scroll events without an event-tap timeout or recovery message. The stress log was written to `/tmp` and is not an application artifact.

## Safety checks

- Normal logging remains disabled; log messages use an autoclosure and are not formatted unless debugging is enabled.
- Scroll events are modified and returned in place. They are not reposted.
- EMA and spike damping retain only constant-size state. No history buffer grows with use.
- Inertia is optional and releases bounded carry only on later scroll input; it does not schedule a background timer.
- `systemEvents` launches only when an action fires, never for ordinary events.
- Event-tap timeout/user-input disable notifications re-enable only taps that are meant to be active. No timeout recovery or worker failure was observed; no persistent recovery counter is added to the release worker.
- The worker remains event-driven and reads configuration once at startup.

## Hardware-dependent checks

The one-shot device check did not detect a connected Logitech MX Master during this profiling session. The following scenarios therefore remain manual hardware checks and are not represented as measured here:

- MX Master ratchet scrolling
- MX Master free-spin scrolling
- Trackpad scrolling while an MX Master is simultaneously connected
- End-to-end physical gesture action latency
- A/B reliability and latency of `systemEvents` versus `cgEvent`

The user previously confirmed the current `systemEvents` path works. It remains the default because this session did not produce evidence that `cgEvent` is equally reliable for macOS Spaces and Mission Control.

## Conclusion

The architecture remains appropriate for a lightweight user-space tool. Strict idle cost was below the resolution of the process counters, memory and thread counts were stable, and the only measured hotspot was continuous global movement delivery. Gating that tap removes over 99% of the controlled inactive-movement cost without adding polling, timers, logging, or a persistent history buffer.

There is no measured reason to replace the event-tap implementation with DriverKit or another privileged architecture.
