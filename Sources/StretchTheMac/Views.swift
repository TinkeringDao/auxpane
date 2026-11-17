// SPDX-License-Identifier: MIT
import SwiftUI

struct MenuView: View {
	@EnvironmentObject var model: AppModel
	@EnvironmentObject var hub: HubController
	@EnvironmentObject var snap: WindowSnapController

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			header
			Divider()
			if hub.state.supported {
				layoutPicker
				if model.layout == .twoDisplays {
					TwoDisplayOptions(two: model.two)
				}
				status
			} else if hub.state.connected {
				Label(hub.state.unsupportedReason, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.secondary)
			}
			if let msg = model.message {
				Text(msg).font(.caption).foregroundStyle(.red)
			}
			Divider()
			WindowSnapSection(snap: snap)
			Divider()
			HStack {
				Button("Refresh") { hub.refresh() }.disabled(hub.busy)
				Button("Restore Lenovo defaults") { model.restoreDefaults() }
					.disabled(!hub.state.supported || hub.busy)
				Spacer()
				if hub.busy { ProgressView().controlSize(.small) }
			}
			HStack {
				SettingsLink { Text("Settings…") }
				Spacer()
				Button("Quit") { NSApp.terminate(nil) }
			}
		}
		.padding(14)
		.frame(width: 356)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(hub.state.connected ? "Lenovo \(hub.state.name)" : "No 40AN dock connected")
				.font(.headline)
			if hub.state.connected {
				Text("Board \(hub.state.serviceTag) · VMM5322 firmware \(hub.state.mstVersion)")
					.font(.caption).foregroundStyle(.secondary)
				Text("\(hub.state.monitors) monitor\(hub.state.monitors == 1 ? "" : "s") on the dock · \(model.displayDescription)")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
	}

	private var layoutPicker: some View {
		Picker("Layout", selection: Binding(get: { model.layout }, set: { model.choose($0) })) {
			ForEach(Layout.allCases) { l in
				Text(l.title).tag(l)
			}
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.disabled(hub.busy)
	}

	@ViewBuilder private var status: some View {
		let s = hub.state
		if s.needsReplug {
			Label("Unplug one monitor at the dock and plug it back in to finish switching.",
			      systemImage: "cable.connector")
				.font(.callout)
		} else if s.splitEnabled && s.monitors < 2 {
			Label("Split needs two monitors on the dock.", systemImage: "display.2")
				.font(.callout)
		} else if s.splitEnabled {
			Label("Dock is splitting one wide picture across both monitors.", systemImage: "checkmark.circle")
				.font(.callout)
		} else {
			Label("Dock is mirroring (Lenovo default).", systemImage: "rectangle.on.rectangle")
				.font(.callout)
		}
	}
}

/// Bezel-aware Window Snapping controls for ViewXpand 3840x1080 dual-monitor mode.
struct WindowSnapSection: View {
	@ObservedObject var snap: WindowSnapController

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Toggle("Bezel-aware window snapping", isOn: $snap.enabled)
					.font(.subheadline.weight(.medium))
				Spacer()
			}

			if !snap.axTrusted {
				HStack(spacing: 8) {
					Label("Accessibility required for drag & hotkey snap", systemImage: "lock.shield")
						.font(.caption)
						.foregroundStyle(.orange)
					Spacer()
					Button("Grant…") {
						_ = snap.checkAccessibilityPermission(prompt: true)
					}
					.controlSize(.small)
				}
			} else if snap.enabled {
				Label("Center bezel seam active at x = 1920 (Monitor 1 ∣ Monitor 2)", systemImage: "rectangle.split.2x1.fill")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			if snap.enabled {
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 6) {
						Text("Monitor 1")
							.font(.caption.weight(.semibold))
							.frame(width: 64, alignment: .leading)
						Button("Left") {
							snap.snapFocusedWindow(to: .leftHalf, onSubMonitorIndex: 1)
						}
						Button("Max") {
							snap.snapFocusedWindow(to: .maximize, onSubMonitorIndex: 1)
						}
						Button("Right") {
							snap.snapFocusedWindow(to: .rightHalf, onSubMonitorIndex: 1)
						}
					}
					.controlSize(.small)

					HStack(spacing: 6) {
						Text("Monitor 2")
							.font(.caption.weight(.semibold))
							.frame(width: 64, alignment: .leading)
						Button("Left") {
							snap.snapFocusedWindow(to: .leftHalf, onSubMonitorIndex: 2)
						}
						Button("Max") {
							snap.snapFocusedWindow(to: .maximize, onSubMonitorIndex: 2)
						}
						Button("Right") {
							snap.snapFocusedWindow(to: .rightHalf, onSubMonitorIndex: 2)
						}
					}
					.controlSize(.small)

					HStack(spacing: 6) {
						Button("Throw to Other Monitor") {
							snap.throwFocusedWindowToOtherMonitor()
						}
						Button("Span 3840×1080") {
							snap.snapFocusedWindow(to: .ultrawideSpan)
						}
					}
					.controlSize(.small)
				}

				if let last = snap.lastSnapDescription {
					Text("Last snap: \(last)")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}

				Text("Hotkeys: ⌃⌥←/→ Halves · ⌃⌥↩ Max 1920×1080 · ⌃⌥⌘←/→ Throw Monitor · ⌃⌥U/I/J/K Quarters")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/// Options shown while the "Two displays" layout is selected.
struct TwoDisplayOptions: View {
	@EnvironmentObject var model: AppModel
	@ObservedObject var two: TwoDisplayController

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Toggle("Swap sides", isOn: Binding(get: { model.swapSides }, set: { model.setSwapSides($0) }))
			if let s = two.status {
				Label(s, systemImage: "hourglass").font(.caption)
			} else if two.running {
				Text("macOS sees two separate monitors. Protected video (e.g. streaming services) shows black in this layout; use Ultrawide for it.")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
	}
}

struct SettingsView: View {
	@EnvironmentObject var model: AppModel
	@EnvironmentObject var snap: WindowSnapController

	var body: some View {
		Form {
			Section("Startup & Display Mode") {
				Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }))
				Toggle("Apply my layout when the dock connects", isOn: model.$applyOnConnect)
				Toggle("Use HiDPI (scaled 2×) for the ultrawide layout", isOn: model.$hiDPI)
			}
			Section("Bezel-Aware Window Snapping (ViewXpand 3840×1080)") {
				Toggle("Enable bezel-aware drag & keyboard window snapping", isOn: $snap.enabled)
				HStack {
					Text("Accessibility Permission:")
					Spacer()
					Text(snap.axTrusted ? "Granted" : "Not Granted")
						.foregroundStyle(snap.axTrusted ? .green : .orange)
					if !snap.axTrusted {
						Button("Grant Accessibility…") {
							_ = snap.checkAccessibilityPermission(prompt: true)
						}
					}
				}
				Text("Splits the 3840×1080 ViewXpand desktop at x = 1920 into two independent 1920×1080 sub-monitors so dragging to the top edge or center bezel snaps cleanly to Monitor 1 or Monitor 2 without spanning across the physical bezel.")
					.font(.caption).foregroundStyle(.secondary)
			}
			Section("About") {
				Text("The dock forgets split mode when its power is unplugged. With 'Apply my layout when the dock connects' enabled, Stretch the Mac sets ViewXpand mode and pulses HPD in software automatically.")
					.font(.caption).foregroundStyle(.secondary)
				Text("What this app changes: one volatile setting in VMM5322 RAM (0x1740), software HPD re-enumeration (0xC2/0xC6), and your Mac's resolution. It never writes the dock's flash firmware.")
					.font(.caption).foregroundStyle(.secondary)
			}
		}
		.formStyle(.grouped)
		.frame(width: 460)
		.padding()
	}
}
