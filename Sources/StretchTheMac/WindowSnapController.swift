// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Represents a single logical monitor for window management.
/// On a ViewXpand `3840x1080` (32:9) hardware-split display, macOS sees one wide `NSScreen`,
/// which we partition at `midX` into two virtual `1920x1080` `SubMonitor` instances
/// (`Monitor 1` on the left and `Monitor 2` on the right) so windows never straddle the physical bezel.
struct SubMonitor: Equatable, Identifiable {
	let id: String
	let screen: NSScreen
	/// 1 = Left (or sole monitor), 2 = Right (on ViewXpand split screen).
	let subIndex: Int
	let isViewXpandHalf: Bool
	/// Full hardware frame in AppKit coordinates (origin at bottom-left of primary screen).
	let fullFrame: CGRect
	/// Usable frame excluding Menu Bar and Dock in AppKit coordinates.
	let visibleFrame: CGRect

	var title: String {
		if isViewXpandHalf {
			return "Monitor \(subIndex) (\(subIndex == 1 ? "Left" : "Right") \(Int(fullFrame.width))×\(Int(fullFrame.height)))"
		}
		return "\(screen.localizedName) (\(Int(fullFrame.width))×\(Int(fullFrame.height)))"
	}

	var shortTitle: String {
		isViewXpandHalf ? "Monitor \(subIndex)" : screen.localizedName
	}
}

/// Snap zones supported on each physical monitor (plus explicit full-ultrawide span).
enum SnapZone: String, CaseIterable, Equatable {
	case leftHalf
	case rightHalf
	case maximize
	case topHalf
	case bottomHalf
	case topLeftQuarter
	case topRightQuarter
	case bottomLeftQuarter
	case bottomRightQuarter
	case centerRestore
	case ultrawideSpan

	var label: String {
		switch self {
		case .leftHalf: "Left Half"
		case .rightHalf: "Right Half"
		case .maximize: "Maximize"
		case .topHalf: "Top Half"
		case .bottomHalf: "Bottom Half"
		case .topLeftQuarter: "Top-Left Quarter"
		case .topRightQuarter: "Top-Right Quarter"
		case .bottomLeftQuarter: "Bottom-Left Quarter"
		case .bottomRightQuarter: "Bottom-Right Quarter"
		case .centerRestore: "Center"
		case .ultrawideSpan: "Ultrawide Span (Both Monitors)"
		}
	}

	/// Computes the target window rect in AppKit screen coordinates (`bottom-left` origin).
	func targetFrame(in sub: SubMonitor, parentVisibleFrame: CGRect? = nil) -> CGRect {
		let vf = sub.visibleFrame
		let halfW = floor(vf.width / 2.0)
		let halfH = floor(vf.height / 2.0)

		switch self {
		case .leftHalf:
			return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: vf.height)
		case .rightHalf:
			return CGRect(x: vf.minX + halfW, y: vf.minY, width: vf.width - halfW, height: vf.height)
		case .maximize:
			return vf
		case .topHalf:
			return CGRect(x: vf.minX, y: vf.minY + halfH, width: vf.width, height: vf.height - halfH)
		case .bottomHalf:
			return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: halfH)
		case .topLeftQuarter:
			return CGRect(x: vf.minX, y: vf.minY + halfH, width: halfW, height: vf.height - halfH)
		case .topRightQuarter:
			return CGRect(x: vf.minX + halfW, y: vf.minY + halfH, width: vf.width - halfW, height: vf.height - halfH)
		case .bottomLeftQuarter:
			return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: halfH)
		case .bottomRightQuarter:
			return CGRect(x: vf.minX + halfW, y: vf.minY, width: vf.width - halfW, height: halfH)
		case .centerRestore:
			let w = min(vf.width * 0.72, 1360)
			let h = min(vf.height * 0.78, 860)
			return CGRect(
				x: round(vf.midX - w / 2.0),
				y: round(vf.midY - h / 2.0),
				width: round(w),
				height: round(h)
			)
		case .ultrawideSpan:
			return parentVisibleFrame ?? sub.screen.visibleFrame
		}
	}
}

/// Resolved snap destination combining a `SubMonitor`, `SnapZone`, and calculated AppKit `CGRect`.
struct SnapTarget: Equatable {
	let subMonitor: SubMonitor
	let zone: SnapZone
	let frame: CGRect

	var description: String {
		if zone == .ultrawideSpan {
			return "\(zone.label) · \(Int(frame.width))×\(Int(frame.height))"
		}
		return "\(subMonitor.shortTitle) · \(zone.label) (\(Int(frame.width))×\(Int(frame.height)))"
	}
}

/// Bezel-aware Window Snapping Engine modeled on Rectangle & Loop.
/// Splits `3840x1080` ViewXpand displays into two virtual `1920x1080` sub-monitors separated
/// at `midX = screen.frame.midX` (1920), providing drag-to-snap at all 4 physical monitor edges
/// (including both sides of the center bezel seam), translucent glass footprint preview,
/// global keyboard shortcuts, and menu bar quick-snap actions.
@MainActor
final class WindowSnapController: NSObject, ObservableObject {
	@Published var enabled: Bool = true {
		didSet {
			UserDefaults.standard.set(enabled, forKey: "snapEnabled")
			if enabled {
				startMonitoring()
			} else {
				stopMonitoring()
			}
		}
	}

	@Published private(set) var axTrusted: Bool = AXIsProcessTrusted()
	@Published private(set) var lastSnapDescription: String?
	@Published private(set) var activeSubMonitors: [SubMonitor] = []

	// Edge hit-test thresholds (in points)
	private let outerEdgeMargin: CGFloat = 18
	private let centerSeamMargin: CGFloat = 28
	private let topEdgeMargin: CGFloat = 24
	private let cornerHeight: CGFloat = 160
	private let topCenterSpanHalfWidth: CGFloat = 8

	// Event monitors
	private var globalMouseMonitor: Any?
	private var localMouseMonitor: Any?
	private var globalKeyMonitor: Any?
	private var localKeyMonitor: Any?
	private var trustTimer: Timer?
	private var workspaceObserver: Any?
	private var screenObserver: Any?

	// Drag state
	private var draggedWindow: AXUIElement?
	private var draggedWindowPID: pid_t = 0
	private var draggedWindowID: CGWindowID = 0
	private var initialWindowAXFrame: CGRect = .null
	private var initialCursorAppKit: CGPoint = .zero
	private var isWindowActuallyMoving = false
	private var dragCancelledByEscape = false
	private var currentTarget: SnapTarget?

	// Tracks the most recent non-StretchTheMac frontmost application so Menu Bar
	// quick-snap buttons snap the user's active window even when StretchTheMac is clicked.
	private var lastExternalAppPID: pid_t = 0

	private lazy var previewWindow = SnapPreviewWindow()

	override init() {
		if UserDefaults.standard.object(forKey: "snapEnabled") != nil {
			self.enabled = UserDefaults.standard.bool(forKey: "snapEnabled")
		} else {
			self.enabled = true
		}
		super.init()
		refreshSubMonitors()
		trackFrontmostApp()
		observeScreens()
		startTrustPolling()
		if enabled {
			startMonitoring()
		}
	}

	// MARK: - Accessibility Permission

	func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
		let key = "AXTrustedCheckOptionPrompt" as CFString
		let opts = [key: prompt as CFBoolean] as CFDictionary
		let trusted = AXIsProcessTrustedWithOptions(opts)
		axTrusted = trusted
		if trusted && enabled {
			startMonitoring()
		}
		return trusted
	}

	private func startTrustPolling() {
		trustTimer?.invalidate()
		let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				let nowTrusted = AXIsProcessTrusted()
				if nowTrusted != self.axTrusted {
					self.axTrusted = nowTrusted
					Log.write("snap: AXIsProcessTrusted changed to \(nowTrusted)")
					if nowTrusted && self.enabled {
						self.startMonitoring()
					}
				}
			}
		}
		RunLoop.main.add(t, forMode: .common)
		trustTimer = t
	}

	// MARK: - Sub-Monitor Geometry Decomposition

	/// True when `screen` has a side-by-side ViewXpand aspect ratio (> 2.5:1, e.g. 3840x1080).
	static func isViewXpandWide(_ screen: NSScreen) -> Bool {
		let f = screen.frame
		return f.height > 0 && (f.width / f.height) > 2.5
	}

	/// Decomposes all connected `NSScreen`s into logical `SubMonitor`s.
	/// Any `3840x1080` ViewXpand screen is split at `midX` into Monitor 1 (`0..<1920`) and Monitor 2 (`1920..<3840`).
	static func subMonitors(for screen: NSScreen) -> [SubMonitor] {
		let f = screen.frame
		let vf = screen.visibleFrame
		let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
		if isViewXpandWide(screen) {
			let halfW = floor(f.width / 2.0)
			let leftFull = CGRect(x: f.minX, y: f.minY, width: halfW, height: f.height)
			let rightFull = CGRect(x: f.minX + halfW, y: f.minY, width: f.width - halfW, height: f.height)
			let leftVis = vf.intersection(leftFull)
			let rightVis = vf.intersection(rightFull)
			return [
				SubMonitor(
					id: "\(screenID)-1",
					screen: screen,
					subIndex: 1,
					isViewXpandHalf: true,
					fullFrame: leftFull,
					visibleFrame: leftVis.isNull ? leftFull : leftVis
				),
				SubMonitor(
					id: "\(screenID)-2",
					screen: screen,
					subIndex: 2,
					isViewXpandHalf: true,
					fullFrame: rightFull,
					visibleFrame: rightVis.isNull ? rightFull : rightVis
				),
			]
		} else {
			return [
				SubMonitor(
					id: "\(screenID)-1",
					screen: screen,
					subIndex: 1,
					isViewXpandHalf: false,
					fullFrame: f,
					visibleFrame: vf
				),
			]
		}
	}

	func refreshSubMonitors() {
		activeSubMonitors = NSScreen.screens.flatMap { Self.subMonitors(for: $0) }
	}

	/// Returns the `SubMonitor` containing an AppKit point (or the closest one).
	func subMonitor(at appKitPoint: CGPoint) -> SubMonitor? {
		refreshSubMonitors()
		if let match = activeSubMonitors.first(where: { $0.fullFrame.contains(appKitPoint) }) {
			return match
		}
		return activeSubMonitors.min { a, b in
			hypot(a.fullFrame.midX - appKitPoint.x, a.fullFrame.midY - appKitPoint.y) <
				hypot(b.fullFrame.midX - appKitPoint.x, b.fullFrame.midY - appKitPoint.y)
		}
	}

	/// Returns the `SubMonitor` that holds the largest intersection with `appKitRect`.
	func subMonitor(forWindowRect appKitRect: CGRect) -> SubMonitor? {
		refreshSubMonitors()
		let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
		if let byCenter = activeSubMonitors.first(where: { $0.fullFrame.contains(center) }) {
			return byCenter
		}
		return activeSubMonitors.max { a, b in
			let ia = a.fullFrame.intersection(appKitRect)
			let ib = b.fullFrame.intersection(appKitRect)
			let areaA = ia.isNull ? 0 : ia.width * ia.height
			let areaB = ib.isNull ? 0 : ib.width * ib.height
			return areaA < areaB
		} ?? activeSubMonitors.first
	}

	// MARK: - Bezel-Aware Drag-to-Snap Hit Testing

	/// Determines whether `cursor` (in AppKit bottom-left coordinates) is inside a snap zone,
	/// including the virtual center bezel seam (`x ≈ midX`) on a `3840x1080` ViewXpand screen.
	func detectSnapTarget(at cursor: CGPoint) -> SnapTarget? {
		guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else {
			return nil
		}
		let subs = Self.subMonitors(for: screen)
		let f = screen.frame

		if subs.count == 2 {
			let mon1 = subs[0]
			let mon2 = subs[1]
			let midX = mon2.fullFrame.minX
			let nearTop = cursor.y >= f.maxY - topEdgeMargin
			let inTopCorner = cursor.y >= f.maxY - cornerHeight
			let inBottomCorner = cursor.y <= f.minY + cornerHeight

			// 1. Dead-Center Top Seam (abs(x - midX) <= 8 at top menu bar) -> Full 3840x1080 Ultrawide Span
			if cursor.y >= f.maxY - 16 && abs(cursor.x - midX) <= topCenterSpanHalfWidth {
				let frame = SnapZone.ultrawideSpan.targetFrame(in: mon1, parentVisibleFrame: screen.visibleFrame)
				return SnapTarget(subMonitor: mon1, zone: .ultrawideSpan, frame: frame)
			}

			// 2. Outer Left Edge of Monitor 1 (x <= minX + 18)
			if cursor.x <= f.minX + outerEdgeMargin {
				let zone: SnapZone = inTopCorner ? .topLeftQuarter : (inBottomCorner ? .bottomLeftQuarter : .leftHalf)
				return SnapTarget(subMonitor: mon1, zone: zone, frame: zone.targetFrame(in: mon1))
			}

			// 3. Center Bezel Seam — Approaching from Monitor 1 (midX - 28 <= x < midX)
			if cursor.x >= midX - centerSeamMargin && cursor.x < midX {
				let zone: SnapZone = inTopCorner ? .topRightQuarter : (inBottomCorner ? .bottomRightQuarter : .rightHalf)
				return SnapTarget(subMonitor: mon1, zone: zone, frame: zone.targetFrame(in: mon1))
			}

			// 4. Center Bezel Seam — Approaching from Monitor 2 (midX <= x <= midX + 28)
			if cursor.x >= midX && cursor.x <= midX + centerSeamMargin {
				let zone: SnapZone = inTopCorner ? .topLeftQuarter : (inBottomCorner ? .bottomLeftQuarter : .leftHalf)
				return SnapTarget(subMonitor: mon2, zone: zone, frame: zone.targetFrame(in: mon2))
			}

			// 5. Outer Right Edge of Monitor 2 (x >= maxX - 18)
			if cursor.x >= f.maxX - outerEdgeMargin {
				let zone: SnapZone = inTopCorner ? .topRightQuarter : (inBottomCorner ? .bottomRightQuarter : .rightHalf)
				return SnapTarget(subMonitor: mon2, zone: zone, frame: zone.targetFrame(in: mon2))
			}

			// 6. Top Edge of Monitor 1 -> Maximize strictly within Monitor 1 (1920x1080)
			if nearTop && cursor.x < midX - centerSeamMargin {
				return SnapTarget(subMonitor: mon1, zone: .maximize, frame: SnapZone.maximize.targetFrame(in: mon1))
			}

			// 7. Top Edge of Monitor 2 -> Maximize strictly within Monitor 2 (1920x1080)
			if nearTop && cursor.x > midX + centerSeamMargin {
				return SnapTarget(subMonitor: mon2, zone: .maximize, frame: SnapZone.maximize.targetFrame(in: mon2))
			}

			return nil
		} else if let mon = subs.first {
			let nearTop = cursor.y >= f.maxY - topEdgeMargin
			let inTopCorner = cursor.y >= f.maxY - cornerHeight
			let inBottomCorner = cursor.y <= f.minY + cornerHeight

			if cursor.x <= f.minX + outerEdgeMargin {
				let zone: SnapZone = inTopCorner ? .topLeftQuarter : (inBottomCorner ? .bottomLeftQuarter : .leftHalf)
				return SnapTarget(subMonitor: mon, zone: zone, frame: zone.targetFrame(in: mon))
			}
			if cursor.x >= f.maxX - outerEdgeMargin {
				let zone: SnapZone = inTopCorner ? .topRightQuarter : (inBottomCorner ? .bottomRightQuarter : .rightHalf)
				return SnapTarget(subMonitor: mon, zone: zone, frame: zone.targetFrame(in: mon))
			}
			if nearTop {
				return SnapTarget(subMonitor: mon, zone: .maximize, frame: SnapZone.maximize.targetFrame(in: mon))
			}
			return nil
		}
		return nil
	}

	// MARK: - Event Monitoring (Mouse Drag + Global Keyboard Shortcuts)

	private func trackFrontmostApp() {
		if let front = NSWorkspace.shared.frontmostApplication,
		   front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
			lastExternalAppPID = front.processIdentifier
		}
		workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didActivateApplicationNotification,
			object: nil,
			queue: .main
		) { [weak self] note in
			guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
			let pid = app.processIdentifier
			guard pid != ProcessInfo.processInfo.processIdentifier else { return }
			MainActor.assumeIsolated {
				self?.lastExternalAppPID = pid
			}
		}
	}

	private func observeScreens() {
		screenObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.refreshSubMonitors()
			}
		}
	}

	func startMonitoring() {
		guard globalMouseMonitor == nil else { return }
		let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
		globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
			MainActor.assumeIsolated {
				self?.handleMouseEvent(event)
			}
		}
		localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
			MainActor.assumeIsolated {
				self?.handleMouseEvent(event)
			}
			return event
		}

		let keyMask: NSEvent.EventTypeMask = [.keyDown]
		globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
			MainActor.assumeIsolated {
				_ = self?.handleKeyEvent(event)
			}
		}
		localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
			var consumed = false
			MainActor.assumeIsolated {
				consumed = self?.handleKeyEvent(event) ?? false
			}
			return consumed ? nil : event
		}
		Log.write("snap: monitoring started (AX trusted=\(axTrusted))")
	}

	func stopMonitoring() {
		if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
		if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
		if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
		if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
		previewWindow.hide()
		resetDragState()
		Log.write("snap: monitoring stopped")
	}

	private func handleMouseEvent(_ event: NSEvent) {
		guard enabled else { return }
		let cursorAppKit = NSEvent.mouseLocation

		switch event.type {
		case .leftMouseDown:
			resetDragState()
			initialCursorAppKit = cursorAppKit
			guard axTrusted else { return }
			let quartzPt = Self.appKitToQuartz(cursorAppKit)
			if let (win, pid, wid) = Self.windowElement(atQuartzPoint: quartzPt) {
				draggedWindow = win
				draggedWindowPID = pid
				draggedWindowID = wid
				initialWindowAXFrame = Self.axFrame(of: win)
			}

		case .leftMouseDragged:
			guard axTrusted, !dragCancelledByEscape else { return }
			if draggedWindow == nil {
				let quartzPt = Self.appKitToQuartz(initialCursorAppKit)
				if let (win, pid, wid) = Self.windowElement(atQuartzPoint: quartzPt) {
					draggedWindow = win
					draggedWindowPID = pid
					draggedWindowID = wid
					initialWindowAXFrame = Self.axFrame(of: win)
				}
			}
			guard let win = draggedWindow, !initialWindowAXFrame.isNull else { return }

			// Confirm the window's AX origin is actually translating without being resized
			if !isWindowActuallyMoving {
				let curFrame = Self.axFrame(of: win)
				guard !curFrame.isNull else { return }
				let dx = abs(curFrame.origin.x - initialWindowAXFrame.origin.x)
				let dy = abs(curFrame.origin.y - initialWindowAXFrame.origin.y)
				let dw = abs(curFrame.size.width - initialWindowAXFrame.size.width)
				let dh = abs(curFrame.size.height - initialWindowAXFrame.size.height)
				if (dx > 2.5 || dy > 2.5) && dw < 2.0 && dh < 2.0 {
					isWindowActuallyMoving = true
				} else {
					return
				}
			}

			if let target = detectSnapTarget(at: cursorAppKit) {
				if currentTarget != target {
					currentTarget = target
					previewWindow.show(target: target)
				}
			} else if currentTarget != nil {
				currentTarget = nil
				previewWindow.hide()
			}

		case .leftMouseUp:
			defer { resetDragState() }
			guard axTrusted, !dragCancelledByEscape, isWindowActuallyMoving, let win = draggedWindow else {
				previewWindow.hide()
				return
			}
			let releaseTarget = detectSnapTarget(at: cursorAppKit) ?? currentTarget
			previewWindow.hide()
			if let target = releaseTarget {
				Self.applyAppKitFrame(target.frame, to: win, pid: draggedWindowPID)
				lastSnapDescription = target.description
				Log.write("snap: drag-snapped window (\(draggedWindowID)) to \(target.description)")
			}

		default:
			break
		}
	}

	/// Handles Escape during drag and global `Ctrl+Option` keyboard shortcuts.
	@discardableResult
	private func handleKeyEvent(_ event: NSEvent) -> Bool {
		guard enabled else { return false }

		// Escape cancels active drag-to-snap preview
		if event.keyCode == UInt16(kVK_Escape), isWindowActuallyMoving {
			dragCancelledByEscape = true
			currentTarget = nil
			previewWindow.hide()
			return false
		}

		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		let ctrlOpt: NSEvent.ModifierFlags = [.control, .option]
		let ctrlOptCmd: NSEvent.ModifierFlags = [.control, .option, .command]

		if flags == ctrlOpt {
			switch Int(event.keyCode) {
			case kVK_LeftArrow:
				snapFocusedWindow(to: .leftHalf)
				return true
			case kVK_RightArrow:
				snapFocusedWindow(to: .rightHalf)
				return true
			case kVK_Return, kVK_UpArrow:
				snapFocusedWindow(to: .maximize)
				return true
			case kVK_DownArrow:
				snapFocusedWindow(to: .centerRestore)
				return true
			case kVK_ANSI_U:
				snapFocusedWindow(to: .topLeftQuarter)
				return true
			case kVK_ANSI_I:
				snapFocusedWindow(to: .topRightQuarter)
				return true
			case kVK_ANSI_J:
				snapFocusedWindow(to: .bottomLeftQuarter)
				return true
			case kVK_ANSI_K:
				snapFocusedWindow(to: .bottomRightQuarter)
				return true
			default:
				return false
			}
		} else if flags == ctrlOptCmd {
			switch Int(event.keyCode) {
			case kVK_LeftArrow:
				throwFocusedWindowToSubMonitor(index: 1)
				return true
			case kVK_RightArrow:
				throwFocusedWindowToSubMonitor(index: 2)
				return true
			case kVK_Return:
				snapFocusedWindow(to: .ultrawideSpan)
				return true
			default:
				return false
			}
		}
		return false
	}

	private func resetDragState() {
		draggedWindow = nil
		draggedWindowPID = 0
		draggedWindowID = 0
		initialWindowAXFrame = .null
		isWindowActuallyMoving = false
		dragCancelledByEscape = false
		currentTarget = nil
	}

	// MARK: - Programmatic & Hotkey Window Snapping Actions

	/// Snaps the active window to `zone` within its current physical `SubMonitor`
	/// (or within a specific `subMonitorIndex` 1 or 2 when requested from the Menu Bar).
	func snapFocusedWindow(to zone: SnapZone, onSubMonitorIndex targetSubIndex: Int? = nil) {
		guard checkAccessibilityPermission(prompt: true) else { return }
		guard let (win, pid) = targetWindowForCommand() else {
			Log.write("snap: no target window found for \(zone.rawValue)")
			return
		}
		let axRect = Self.axFrame(of: win)
		let appKitRect = axRect.isNull ? CGRect(x: 100, y: 100, width: 800, height: 600) : Self.quartzToAppKit(axRect)

		refreshSubMonitors()
		let sub: SubMonitor?
		if let idx = targetSubIndex {
			sub = activeSubMonitors.first(where: { $0.isViewXpandHalf && $0.subIndex == idx })
				?? activeSubMonitors.first(where: { $0.subIndex == idx })
				?? subMonitor(forWindowRect: appKitRect)
		} else {
			sub = subMonitor(forWindowRect: appKitRect)
		}
		guard let targetSub = sub else { return }

		let frame = zone.targetFrame(in: targetSub, parentVisibleFrame: targetSub.screen.visibleFrame)
		Self.applyAppKitFrame(frame, to: win, pid: pid)
		let target = SnapTarget(subMonitor: targetSub, zone: zone, frame: frame)
		lastSnapDescription = target.description
		Log.write("snap: command-snapped window (pid=\(pid)) to \(target.description)")
	}

	/// Moves the active window to the other physical `1920x1080` monitor (or a specific sub-monitor index),
	/// preserving its relative position and size proportions.
	func throwFocusedWindowToOtherMonitor() {
		guard checkAccessibilityPermission(prompt: true) else { return }
		guard let (win, pid) = targetWindowForCommand() else { return }
		let axRect = Self.axFrame(of: win)
		guard !axRect.isNull else { return }
		let appKitRect = Self.quartzToAppKit(axRect)
		guard let curSub = subMonitor(forWindowRect: appKitRect) else { return }

		let otherIndex = curSub.subIndex == 1 ? 2 : 1
		throwWindow(win, pid: pid, currentAppKitRect: appKitRect, from: curSub, toSubMonitorIndex: otherIndex)
	}

	func throwFocusedWindowToSubMonitor(index targetIndex: Int) {
		guard checkAccessibilityPermission(prompt: true) else { return }
		guard let (win, pid) = targetWindowForCommand() else { return }
		let axRect = Self.axFrame(of: win)
		guard !axRect.isNull else { return }
		let appKitRect = Self.quartzToAppKit(axRect)
		guard let curSub = subMonitor(forWindowRect: appKitRect) else { return }
		throwWindow(win, pid: pid, currentAppKitRect: appKitRect, from: curSub, toSubMonitorIndex: targetIndex)
	}

	private func throwWindow(_ win: AXUIElement, pid: pid_t, currentAppKitRect: CGRect, from src: SubMonitor, toSubMonitorIndex dstIndex: Int) {
		refreshSubMonitors()
		guard let dst = activeSubMonitors.first(where: { $0.isViewXpandHalf && $0.subIndex == dstIndex })
			?? activeSubMonitors.first(where: { $0.id != src.id }) else { return }

		let srcVF = src.visibleFrame
		let dstVF = dst.visibleFrame
		let relX = max(0, min(1, (currentAppKitRect.minX - srcVF.minX) / max(srcVF.width, 1)))
		let relY = max(0, min(1, (currentAppKitRect.minY - srcVF.minY) / max(srcVF.height, 1)))
		let relW = max(0.2, min(1, currentAppKitRect.width / max(srcVF.width, 1)))
		let relH = max(0.2, min(1, currentAppKitRect.height / max(srcVF.height, 1)))

		let newW = round(dstVF.width * relW)
		let newH = round(dstVF.height * relH)
		let newX = round(min(max(dstVF.minX + dstVF.width * relX, dstVF.minX), dstVF.maxX - newW))
		let newY = round(min(max(dstVF.minY + dstVF.height * relY, dstVF.minY), dstVF.maxY - newH))

		let targetRect = CGRect(x: newX, y: newY, width: newW, height: newH)
		Self.applyAppKitFrame(targetRect, to: win, pid: pid)
		lastSnapDescription = "Moved to \(dst.shortTitle) (\(Int(newW))×\(Int(newH)))"
		Log.write("snap: threw window (pid=\(pid)) to \(dst.shortTitle) frame=\(targetRect)")
	}

	// MARK: - Low-Level Accessibility (`AXUIElement`) Helpers (Rectangle Patterns)

	/// Resolves the focused window of the frontmost app (or the last active external app when clicked from StretchTheMac UI).
	private func targetWindowForCommand() -> (AXUIElement, pid_t)? {
		let myPID = ProcessInfo.processInfo.processIdentifier
		var candidatePIDs: [pid_t] = []
		if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != myPID {
			candidatePIDs.append(front)
		}
		if lastExternalAppPID > 0 && !candidatePIDs.contains(lastExternalAppPID) {
			candidatePIDs.append(lastExternalAppPID)
		}

		for pid in candidatePIDs {
			let appEl = AXUIElementCreateApplication(pid)
			AXUIElementSetMessagingTimeout(appEl, 0.25)
			var winRef: CFTypeRef?
			if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
			   let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
				let win = (winRef as! AXUIElement)
				return (win, pid)
			}
			if AXUIElementCopyAttributeValue(appEl, kAXMainWindowAttribute as CFString, &winRef) == .success,
			   let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
				let win = (winRef as! AXUIElement)
				return (win, pid)
			}
		}
		return nil
	}

	/// Resolves the `AXUIElement` window under `quartzPt` (top-left origin).
	private static func windowElement(atQuartzPoint quartzPt: CGPoint) -> (AXUIElement, pid_t, CGWindowID)? {
		let sys = AXUIElementCreateSystemWide()
		AXUIElementSetMessagingTimeout(sys, 0.25)
		var hitRef: AXUIElement?
		guard AXUIElementCopyElementAtPosition(sys, Float(quartzPt.x), Float(quartzPt.y), &hitRef) == .success,
		      let hit = hitRef else {
			return nil
		}

		var pid: pid_t = 0
		AXUIElementGetPid(hit, &pid)
		guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

		var roleRef: CFTypeRef?
		if AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &roleRef) == .success,
		   (roleRef as? String) == (kAXWindowRole as String) {
			var wid: CGWindowID = 0
			_ = _AXUIElementGetWindow(hit, &wid)
			return (hit, pid, wid)
		}

		var winRef: CFTypeRef?
		if AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &winRef) == .success,
		   let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
			let win = (winRef as! AXUIElement)
			AXUIElementSetMessagingTimeout(win, 0.25)
			var wid: CGWindowID = 0
			_ = _AXUIElementGetWindow(win, &wid)
			return (win, pid, wid)
		}
		return nil
	}

	/// Reads a window's frame in Quartz/AX coordinates (`top-left` of primary screen).
	private static func axFrame(of window: AXUIElement) -> CGRect {
		AXUIElementSetMessagingTimeout(window, 0.25)
		var posRef: CFTypeRef?
		var sizeRef: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
		      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
		      let posRef, let sizeRef,
		      CFGetTypeID(posRef) == AXValueGetTypeID(),
		      CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
			return .null
		}
		var pt = CGPoint.zero
		var sz = CGSize.zero
		guard AXValueGetValue((posRef as! AXValue), .cgPoint, &pt),
		      AXValueGetValue((sizeRef as! AXValue), .cgSize, &sz) else {
			return .null
		}
		return CGRect(origin: pt, size: sz)
	}

	/// Applies an AppKit frame (`bottom-left` origin) to an `AXUIElement` window using
	/// Rectangle's 3-step `size -> position -> size` dance and `AXEnhancedUserInterface` workaround.
	private static func applyAppKitFrame(_ appKitRect: CGRect, to window: AXUIElement, pid: pid_t) {
		let axRect = appKitToQuartz(appKitRect)
		AXUIElementSetMessagingTimeout(window, 0.25)

		let appEl = AXUIElementCreateApplication(pid)
		AXUIElementSetMessagingTimeout(appEl, 0.25)
		let enhancedKey = "AXEnhancedUserInterface" as CFString
		var enhancedRef: CFTypeRef?
		let hadEnhancedUI = (AXUIElementCopyAttributeValue(appEl, enhancedKey, &enhancedRef) == .success)
			&& ((enhancedRef as? Bool) == true)

		if hadEnhancedUI {
			AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanFalse)
		}

		var targetSize = axRect.size
		var targetOrigin = axRect.origin
		if let sizeVal = AXValueCreate(.cgSize, &targetSize),
		   let posVal = AXValueCreate(.cgPoint, &targetOrigin) {
			// Step 1: Propose target size
			AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
			// Step 2: Move to target origin
			AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
			// Step 3: Re-apply target size after crossing monitor/sub-monitor boundary
			AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
		}

		if hadEnhancedUI && (NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled) {
			AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanTrue)
		}
	}

	// MARK: - Coordinate Space Conversion (AppKit bottom-left <-> Quartz/AX top-left)

	private static var primaryScreenMaxY: CGFloat {
		NSScreen.screens.first?.frame.maxY ?? 1080
	}

	static func appKitToQuartz(_ pt: CGPoint) -> CGPoint {
		CGPoint(x: pt.x, y: primaryScreenMaxY - pt.y)
	}

	static func appKitToQuartz(_ rect: CGRect) -> CGRect {
		CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
	}

	static func quartzToAppKit(_ rect: CGRect) -> CGRect {
		CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
	}

	// MARK: - Self-Test Verification

	func runSelfTest() {
		refreshSubMonitors()
		print("=== Stretch the Mac WindowSnapController Self-Test ===")
		print("AXIsProcessTrusted: \(axTrusted)")
		print("Connected NSScreens: \(NSScreen.screens.count), SubMonitors: \(activeSubMonitors.count)")
		for s in activeSubMonitors {
			print("  - [\(s.id)] \(s.title): full=\(s.fullFrame) visible=\(s.visibleFrame) isViewXpandHalf=\(s.isViewXpandHalf)")
		}
		if let wideScreen = NSScreen.screens.first(where: { Self.isViewXpandWide($0) }) {
			let f = wideScreen.frame
			let midX = f.midX
			let midY = f.midY
			let topY = f.maxY - 6
			let botY = f.minY + 20
			let probes: [(String, CGPoint)] = [
				("Monitor 1 Left Half", CGPoint(x: f.minX + 4, y: midY)),
				("Monitor 1 Top-Left Quarter", CGPoint(x: f.minX + 4, y: topY)),
				("Monitor 1 Bottom-Left Quarter", CGPoint(x: f.minX + 4, y: botY)),
				("Center Seam -> Monitor 1 Right Half", CGPoint(x: midX - 10, y: midY)),
				("Center Seam -> Monitor 1 Top-Right Quarter", CGPoint(x: midX - 10, y: topY)),
				("Center Seam -> Monitor 1 Bottom-Right Quarter", CGPoint(x: midX - 10, y: botY)),
				("Center Seam -> Monitor 2 Left Half", CGPoint(x: midX + 10, y: midY)),
				("Center Seam -> Monitor 2 Top-Left Quarter", CGPoint(x: midX + 10, y: topY)),
				("Center Seam -> Monitor 2 Bottom-Left Quarter", CGPoint(x: midX + 10, y: botY)),
				("Monitor 2 Right Half", CGPoint(x: f.maxX - 4, y: midY)),
				("Monitor 2 Top-Right Quarter", CGPoint(x: f.maxX - 4, y: topY)),
				("Monitor 2 Bottom-Right Quarter", CGPoint(x: f.maxX - 4, y: botY)),
				("Monitor 1 Top Edge Maximize", CGPoint(x: f.minX + 500, y: topY)),
				("Monitor 2 Top Edge Maximize", CGPoint(x: midX + 500, y: topY)),
				("Top Center Seam Ultrawide Span", CGPoint(x: midX, y: topY)),
			]
			print("Probing 15 snap zones on ViewXpand screen \(f):")
			for (label, pt) in probes {
				if let t = detectSnapTarget(at: pt) {
					print("  [PASS] \(label) @ (\(Int(pt.x)),\(Int(pt.y))) -> \(t.description) frame=\(t.frame)")
				} else {
					print("  [FAIL] \(label) @ (\(Int(pt.x)),\(Int(pt.y))) -> nil")
				}
			}
		}
	}
}

// MARK: - Animated Glass Snap Footprint Preview Window

@MainActor
private final class SnapPreviewWindow: NSWindow {
	private let effectView = NSVisualEffectView()
	private let borderLayer = CAShapeLayer()
	private let labelPill = NSTextField(labelWithString: "")
	private let pillContainer = NSVisualEffectView()
	private var isShowing = false

	init() {
		super.init(
			contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		level = .statusBar
		ignoresMouseEvents = true
		isReleasedWhenClosed = false
		collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

		let root = NSView(frame: .zero)
		root.wantsLayer = true

		effectView.wantsLayer = true
		effectView.material = .hudWindow
		effectView.blendingMode = .behindWindow
		effectView.state = .active
		effectView.layer?.cornerRadius = 14
		effectView.layer?.masksToBounds = true
		root.addSubview(effectView)

		borderLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
		borderLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
		borderLayer.lineWidth = 2.5
		effectView.layer?.addSublayer(borderLayer)

		pillContainer.wantsLayer = true
		pillContainer.material = .popover
		pillContainer.blendingMode = .withinWindow
		pillContainer.state = .active
		pillContainer.layer?.cornerRadius = 10
		pillContainer.layer?.masksToBounds = true

		labelPill.font = .systemFont(ofSize: 13, weight: .semibold)
		labelPill.textColor = .labelColor
		labelPill.alignment = .center
		pillContainer.addSubview(labelPill)
		effectView.addSubview(pillContainer)

		contentView = root
	}

	override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
		frameRect
	}

	func show(target: SnapTarget) {
		let insetFrame = target.frame.insetBy(dx: 6, dy: 6)
		labelPill.stringValue = target.description
		labelPill.sizeToFit()

		if !isShowing {
			setFrame(insetFrame, display: true)
			layoutSublayers(for: insetFrame.size)
			alphaValue = 0
			orderFrontRegardless()
			isShowing = true
			NSAnimationContext.runAnimationGroup { ctx in
				ctx.duration = 0.12
				ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
				self.animator().alphaValue = 1.0
			}
		} else {
			NSAnimationContext.runAnimationGroup { ctx in
				ctx.duration = 0.11
				ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
				self.animator().setFrame(insetFrame, display: true)
			}
			layoutSublayers(for: insetFrame.size)
		}
	}

	func hide() {
		guard isShowing else { return }
		isShowing = false
		orderOut(nil)
	}

	private func layoutSublayers(for size: CGSize) {
		let bounds = CGRect(origin: .zero, size: size)
		effectView.frame = bounds
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		borderLayer.frame = bounds
		borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 14, cornerHeight: 14, transform: nil)
		CATransaction.commit()

		let lSize = labelPill.frame.size
		let pw = lSize.width + 24
		let ph = lSize.height + 12
		pillContainer.frame = CGRect(
			x: round((size.width - pw) / 2.0),
			y: round((size.height - ph) / 2.0),
			width: pw,
			height: ph
		)
		labelPill.frame = CGRect(x: 12, y: 6, width: lSize.width, height: lSize.height)
	}
}
