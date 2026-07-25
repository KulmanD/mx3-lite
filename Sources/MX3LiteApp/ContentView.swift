import MX3AppSupport
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            TabView {
                overview
                    .tabItem { Label("General", systemImage: "switch.2") }
                gestures
                    .tabItem { Label("Gestures", systemImage: "arrow.up.left.and.arrow.down.right") }
                scrolling
                    .tabItem { Label("Scrolling", systemImage: "computermouse") }
                diagnostics
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
            Divider()
            actionBar
        }
        .onAppear { model.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.refresh() }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.workerState.title).font(.headline)
                if case .unavailable(let message) = model.workerState {
                    Text(message).font(.caption).foregroundColor(.secondary).lineLimit(1)
                } else {
                    Text("Manual worker control").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button {
                model.refresh(forceConfigReload: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
            .help("Refresh worker status and reload config")

            Button {
                model.toggleWorker()
            } label: {
                Label(
                    model.workerState.isRunning ? "Stop" : "Start",
                    systemImage: model.workerState.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.workerState == .loading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var overview: some View {
        Form {
            Section(header: Text("Worker")) {
                Toggle("Keep gesture control running", isOn: Binding(
                    get: { model.workerState.isRunning },
                    set: { _ in model.toggleWorker() }
                ))
                .disabled(model.isBusy || model.workerState == .loading)

                if model.restartRequired {
                    HStack {
                        Label("Saved changes require a worker restart.", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Restart now") { model.restartWorker() }
                            .disabled(model.isBusy)
                    }
                }
            }

            Section(header: Text("Keyboard actions")) {
                Picker("Action backend", selection: $model.settings.actionBackend) {
                    ForEach(AppActionBackend.allCases) { backend in
                        Text(backend.title).tag(backend)
                    }
                }
                Text("System Events remains the recommended backend for Spaces and Mission Control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Config")) {
                HStack {
                    Text(model.configURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder") { model.revealConfig() }
                }
            }
        }
        .padding(16)
    }

    private var gestures: some View {
        Form {
            Section(header: Text("Gesture button")) {
                Stepper(value: $model.settings.threshold, in: 20...1000, step: 10) {
                    valueRow("Movement threshold", value: String(Int(model.settings.threshold)))
                }
                Toggle("Reverse left and right desktop direction", isOn: $model.settings.invertDesktopGestureDirection)
                Toggle("Reverse vertical gesture direction", isOn: $model.settings.invertY)
                Picker("Down gesture", selection: $model.settings.downAction) {
                    ForEach(AppDownAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
            }

            Section(header: Text("Mouse button IDs")) {
                OptionalButtonField(title: "Gesture", value: $model.settings.buttons.gesture)
                OptionalButtonField(title: "Back", value: $model.settings.buttons.back)
                OptionalButtonField(title: "Forward", value: $model.settings.buttons.forward)
                Text("Leave a field empty to disable that mapping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    private var scrolling: some View {
        Form {
            Section(header: Text("Device filtering")) {
                Picker("Transform", selection: $model.settings.scrollTransformMode) {
                    ForEach(AppScrollTransformMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Reverse vertical wheel", isOn: $model.settings.invertVerticalScroll)
                    .disabled(model.settings.scrollTransformMode == .disabled)
                Toggle("Reverse horizontal wheel", isOn: $model.settings.invertHorizontalScroll)
                    .disabled(model.settings.scrollTransformMode == .disabled)
                if model.settings.scrollTransformMode == .global {
                    Label("Global mode also changes trackpad scrolling.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section(header: Text("Response")) {
                sliderRow("Multiplier", value: $model.settings.scrollMultiplier, range: 0.1...5, step: 0.1)
                sliderRow("Acceleration", value: $model.settings.scrollAcceleration, range: 0.1...3, step: 0.1)
                sliderRow("Ratchet multiplier", value: $model.settings.ratchetStepMultiplier, range: 0.1...5, step: 0.1)
                Stepper(value: $model.settings.maxScrollStep, in: 1...100, step: 1) {
                    valueRow("Maximum step", value: String(Int(model.settings.maxScrollStep)))
                }
            }

            Section(header: Text("Smoothing")) {
                Toggle("Smooth MX Master scrolling", isOn: $model.settings.smoothScroll)
                Picker("Mode", selection: $model.settings.smoothScrollMode) {
                    ForEach(AppSmoothScrollMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(!model.settings.smoothScroll)
                sliderRow("Factor", value: $model.settings.smoothScrollFactor, range: 0...0.95, step: 0.05)
                    .disabled(!model.settings.smoothScroll)
                sliderRow("Deadzone", value: $model.settings.scrollDeadzone, range: 0...20, step: 1)
                    .disabled(!model.settings.smoothScroll)
                sliderRow("Free-spin damping", value: $model.settings.freeSpinDamping, range: 0...1, step: 0.05)
                    .disabled(!model.settings.smoothScroll)
            }
        }
        .padding(16)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.runDoctor()
                } label: {
                    Label("Run diagnostics", systemImage: "stethoscope")
                }
                .disabled(model.isBusy)
                Button("Accessibility settings") { model.openAccessibilitySettings() }
                Button("Input Monitoring settings") { model.openInputMonitoringSettings() }
                Spacer()
            }

            ScrollView {
                Text(model.doctorOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
        .padding(16)
    }

    private var actionBar: some View {
        HStack {
            if !model.validationWarnings.isEmpty {
                Label(model.validationWarnings[0], systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } else if model.hasUnsavedChanges {
                Text("Unsaved changes").font(.caption).foregroundColor(.secondary)
            } else {
                Text("Config is saved").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Revert") { model.discardChanges() }
                .disabled(!model.hasUnsavedChanges || model.isBusy)
            Button("Save") { model.save() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasUnsavedChanges || !model.validationWarnings.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch model.workerState {
        case .running: return .green
        case .stopped: return .secondary
        case .loading: return .orange
        case .unavailable: return .red
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }
}

private struct OptionalButtonField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Disabled", text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { input in
                    let trimmed = input.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        value = nil
                    } else if let parsed = Int(trimmed), (0...31).contains(parsed) {
                        value = parsed
                    }
                }
            ))
            .frame(width: 84)
            .multilineTextAlignment(.trailing)
        }
    }
}
