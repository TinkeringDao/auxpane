# Security Policy

## Supported Hardware & Firmware Versions

| Product | Synaptics Hub | OUI | Board ID | Firmware Version | Supported |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Lenovo ThinkPad Thunderbolt 3 Dock Gen 2 (`Type 40AN`) | `VMM5322` (`Panamera`) | `90-CC-24` | `0x0253` | `05.07.01` (`5.07.001`) | Yes |
| Synaptics `VMM53xx` Docks (Verified Config Signature) | `VMM5322` / `VMM5331` | `90-CC-24` | `0x0253` / `0x0244` | `05.06.03`, `05.07.01` | Yes |

## Hardware & Memory Safety Boundaries

`Stretch the Mac` (`StretchTheMac.app`, `dockctl`, `lenovo_40an_vmm5322_split.py`) operates strictly within volatile hub SRAM over macOS `IOKit` `DCPDPDeviceProxy` DisplayPort AUX (`DPCD 0x4B0..0x4FF`):
- **Never modifies SPI flash firmware**: Neither `DockCore` nor `lenovo_40an_vmm5322_split.py` implements SPI flash erase or write commands.
- **Strict RAM write allowlist**: Writes are restricted solely to volatile SRAM `0x1740` (EDID aggregation mode nibble `0..4`) and the firmware event ring buffer (`0x0368..0x0387`, write index `0x04A1`) after verifying the firmware version (`05.06.03` / `05.07.01`) and config block signature (`20 00 87 83` at `0x1700`).
- **Two-way reversible**: Every mode change can be reverted immediately via `python3 lenovo_40an_vmm5322_split.py mirror`, `./dist/dockctl mst-poke 0x1740 3`, clicking **Restore Lenovo defaults** in `StretchTheMac.app`, or power-cycling the dock.
- **Zero network telemetry**: Executes 100% offline with zero network sockets or external dependencies.

## Reporting a Vulnerability

If you discover a memory-bounds issue, DPCD command framing bug, or unexpected behavior on a specific dock firmware revision:
1. Open a private security advisory via [GitHub Security Advisories](https://github.com/TinkeringDao/stretch-the-mac/security/advisories/new).
2. Include your dock model, Synaptics firmware version (`./dist/dockctl info`), and macOS version.
