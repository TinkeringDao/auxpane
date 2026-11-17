# Stretch the Mac

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

macOS DisplayPort AUX (`IODPDevice` DPCD Remote Control) ViewXpand controller and bezel-aware `3840x1080` window snapper for the Lenovo ThinkPad Thunderbolt 3 Dock Gen 2 (`Type 40AN`, Synaptics `VMM5322` MST hub).

## Problem & Hardware Mechanism

macOS does not implement DisplayPort Multi-Stream Transport (`DP MST`) for hub-routed video outputs. When two `1920x1080` monitors are plugged into the rear DisplayPort/HDMI ports of a Lenovo `40AN` dock, both sinks share a single DisplayPort tunnel into the dock's Synaptics `VMM5322` (`Panamera`, OUI `90-CC-24`, Board `0x0253`) MST hub, and macOS mirrors them at `1920x1080`.

The `VMM5322` silicon includes a hardware horizontal-split mode (`ViewXpand`, EDID mode `2`) that works without host MST support:

1. Opening the Synaptics DPCD Remote Control window (`0x4B0..0x4FF`, `"PRIUS"` enable sequence) via macOS `IOKit` (`DCPDPDeviceProxy` / `IODPDeviceReadDPCD` and `IODPDeviceWriteDPCD`) lets the host read and write volatile hub SRAM over the DisplayPort AUX channel.
2. Writing `0x02` to SRAM address `0x1740` switches the hub from factory pass-through (`0x03`) to ViewXpand mode, where the `VMM5322` synthesizes a `3840x1080 @ 60 Hz` (`277.25 MHz`) Detailed Timing Descriptor in its upstream EDID buffer (`0x1600`).
3. macOS drives a single native `3840x1080` (`32:9`) framebuffer over the DisplayPort link, and the `VMM5322` slices each scanline in hardware at `x = 1920`, sending `0..1919` to `TX0` (Monitor 1) and `1920..3839` to `TX2` (Monitor 2).
4. Pushing firmware events `0xC2` (EDID rebuild) and `0xC6` (software Hot-Plug Detect pulse) into the `VMM5322` event ring buffer (`0x0368..0x0387`, write index `0x04A1`) re-enumerates the display link in software without unplugging cables and without writing to SPI flash.

## Why Window Snapping Is Included

In native `3840x1080` ViewXpand mode, macOS sees one `32:9` `NSScreen`, so maximizing a window spans across the physical monitor bezel at `x = 1920`. `StretchTheMac.app` adds a lightweight menu bar helper (`WindowSnapController.swift`) that treats `[0..1920]` and `[1920..3840]` as two separate `1920x1080` monitors:

- Drag-to-snap zones on the outer screen edges AND along both sides of the `x = 1920` center bezel (`x ~ 1900` snaps to the right half of Monitor 1; `x ~ 1940` snaps to the left half of Monitor 2; top edge maximizes on a single `1920x1080` monitor).
- 3-step `size -> position -> size` `AXUIElement` resizing (`AXEnhancedUserInterface`-aware) and global keyboard shortcuts for halves, quarters, single-monitor maximize, cross-monitor throw, and full `3840x1080` span.
- Optional `CGVirtualDisplay` + `ScreenCaptureKit` two-display bridge (`TwoDisplayController.swift`) for workflows that need two distinct macOS spaces/fullscreen targets.

## Repository Layout

| Path | Description |
| :--- | :--- |
| [`Sources/DockCore/`](Sources/DockCore) | C library accessing `VMM5322` DPCD `0x4B0..0x4FF` over `IOKit`. Enforces a strict volatile-SRAM write allowlist (`0x1740` and event ring `0x0368..0x0387` / `0x04A1`); no SPI flash routines exist. |
| [`Sources/dockctl/`](Sources/dockctl) | CLI diagnostic and mode tool (`info`, `mst-status`, `mst-mem`, `mst-reg`, `mst-checksum`, `mst-poke`). |
| [`Sources/StretchTheMac/`](Sources/StretchTheMac) | SwiftUI menu bar app (`HubController.swift`, `DisplayModes.swift`, `WindowSnapController.swift`, `TwoDisplayController.swift`). |
| [`Sources/VirtualDisplay/`](Sources/VirtualDisplay) | Objective-C header bridge for `CGVirtualDisplay`. |
| [`lenovo_40an_vmm5322_split.py`](lenovo_40an_vmm5322_split.py) | Standalone zero-dependency Python 3 script (`ctypes` over `IOKit`) for `status`, `split-apply`, and `mirror`. |

## Build & Test

Requires macOS 14.0+ and Xcode Command Line Tools (`swift` 6.0+):

```bash
# Build ./dist/StretchTheMac.app and ./dist/dockctl
make

# Run shell/Python/plist checks and WindowSnapController geometry self-tests
make test
```

### Standalone Python CLI

```bash
# Read VMM5322 firmware revision, SRAM 0x1740 mode, TX ports, and upstream EDID
python3 lenovo_40an_vmm5322_split.py status

# Switch to 3840x1080 ViewXpand split mode with software HPD pulse
python3 lenovo_40an_vmm5322_split.py split-apply

# Return to 1920x1080 pass-through / mirror mode
python3 lenovo_40an_vmm5322_split.py mirror
```

### Menu Bar App & Shortcuts

Launch `open dist/StretchTheMac.app` and grant Accessibility permission (`System Settings -> Privacy & Security -> Accessibility`) for window snapping:

| Shortcut / Drag | Action |
| :--- | :--- |
| `Ctrl+Opt+Left` / `Ctrl+Opt+Right` | Left / right half of current `1920x1080` monitor |
| `Ctrl+Opt+Return` or `Ctrl+Opt+Up` | Maximize on current `1920x1080` monitor |
| `Ctrl+Opt+Down` | Center & restore on current `1920x1080` monitor |
| `Ctrl+Opt+Cmd+Left` / `Ctrl+Opt+Cmd+Right` | Move focused window between Monitor 1 and Monitor 2 |
| `Ctrl+Opt+Cmd+Return` | Span focused window across full `3840x1080` desktop |
| `Ctrl+Opt+U` / `I` / `J` / `K` | Top-left / top-right / bottom-left / bottom-right quarter |

## Known Limitations

- **Volatile SRAM only**: `0x1740` lives in volatile hub RAM by design (never touching SPI flash), so cold-power-cycling the Lenovo `40AN` dock resets the hub to `1920x1080` mirror mode until `StretchTheMac.app` (via USB `0x17ef:0x3082` hot-plug watch) or `split-apply` re-applies `0x02`.
- **Dual `1920x1080 @ 60 Hz` bandwidth envelope**: ViewXpand mode synthesizes `3840x1080 @ 60 Hz` (`277.25 MHz` pixel clock) for matched `1080p` pairs; mixed-DPI or dual `4K` panels are not split by `VMM5322` ViewXpand Mode 2.
- **Single macOS `NSScreen` in native mode**: Native macOS fullscreen (`Cmd+Ctrl+F`), Mission Control, and centered OS alerts still see one `3840x1080` screen unless the optional `CGVirtualDisplay` two-display bridge is active (which trades zero-copy scanout for `ScreenCaptureKit` frame forwarding).
- **Private macOS frameworks**: `IODPDevice` (`IOKit` `DCPDPDeviceProxy` on Apple Silicon), `SkyLight` mode switching, and `CGVirtualDisplay` rely on private macOS symbols and must run unsandboxed outside the Mac App Store; tested on macOS 14+ with `VMM5322` firmware `05.07.01`.

## Acknowledgments

- [`kksimp/wd19-split`](https://github.com/kksimp/wd19-split) (MIT): Initial Synaptics `VMM53xx` ViewXpand (`0x1740`) research on the Dell WD19 dock, `DockCore`/`dockctl` structure, `SkyLight` mode wrapper, and `CGVirtualDisplay` bridge, adapted here from Dell USB HID-to-I2C (`RTS5487`) to native macOS `IODPDevice` DisplayPort AUX (`0x4B0..0x4FF`) with software `0xC2`/`0xC6` HPD injection.
- [`rxhanson/Rectangle`](https://github.com/rxhanson/Rectangle) (MIT): Reference for the 3-step `size -> position -> size` `AXUIElement` resize sequence on macOS.
- [`fwupd`](https://github.com/fwupd/fwupd) (`synaptics-mst` plugin): Public documentation of the Synaptics DPCD Remote Control register layout.

## License & Legal

Released under the [MIT License](LICENSE).
Independent non-commercial hardware interoperability project; see [`LEGAL.md`](LEGAL.md) for trademark nominative fair use, clean-room safe harbor, and German statutory references.
