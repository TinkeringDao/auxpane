# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-11-17

### Added
- Native macOS `IODPDevice` DisplayPort AUX / DPCD Remote Control (`0x4B0..0x4FF`) backend (`DockCore` and `lenovo_40an_vmm5322_split.py`) for the Lenovo ThinkPad Thunderbolt 3 Dock Gen 2 (`Type 40AN`, Synaptics `VMM5322` `Panamera` MST hub `OUI 90-CC-24`, Board `0x0253`, FW `05.07.01`).
- Zero-replug software EDID rebuild (`0xC2`) and Hot-Plug Detect (`0xC6`) firmware event injection into `VMM5322` SRAM (`0x0368..0x0387`, write index `0x04A1`) when toggling `0x1740` between ViewXpand `3840×1080` split mode (`0x02`) and factory pass-through/mirror mode (`0x03`).
- Bezel-aware **ViewXpand Window Snapping Engine** (`WindowSnapController.swift`) partitioning the `3840×1080` (`32:9`) desktop at `x = 1920` into two independent `1920×1080` sub-monitors (`Monitor 1` and `Monitor 2`) with center-bezel seam drag detection, translucent glass footprint previews, 3-step `AXUIElement` resizing, global keyboard shortcuts, and `--selftest-snap` verification.
- Optional `CGVirtualDisplay` + `ScreenCaptureKit` two-display bridge (`TwoDisplayController.swift`).
