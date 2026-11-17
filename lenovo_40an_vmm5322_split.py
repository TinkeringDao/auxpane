#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
lenovo_40an_vmm5322_split.py — Clean-room Synaptics VMM5322 (Panamera, Board 0x0253)
ViewXpand (3840x1080 hardware horizontal split) & Mirror Mode Controller over macOS IODPDevice DPCD RC.

By default (`status`), this script is 100% READ-ONLY.
Subcommands:
  status        Read VMM5322 firmware, config block (0x1740), port widths (0x1821..0x1830), upstream EDID (0x1600), and SkyLight display mode
  split-edid    Write RAM 0x1740 = 0x02 (ViewXpand aggregate mode) and push event 0xC2 into VMM5322 queue (0x0368/0x04A1)
                so the VMM5322 rebuilds its upstream EDID at 0x1600 (adding 3840x1080@60 DTD at 0x166C) WITHOUT pulsing HPD
  split-apply   Write RAM 0x1740 = 0x02, push events 0xC2 + 0xC6 (zero-replug HPD pulse), and switch macOS to 3840x1080@60Hz via SkyLight
  mirror        Restore Lenovo default RAM 0x1740 = 0x03 (pass-through/mirror), push events 0xC2 + 0xC6, and switch to 1920x1080@60Hz
"""
import ctypes, sys, time, struct

iokit = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/IOKit.framework/IOKit")
cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
sl = ctypes.cdll.LoadLibrary("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")

iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
iokit.IOServiceMatching.restype = ctypes.c_void_p
iokit.IOServiceGetMatchingServices.argtypes = [ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint)]
iokit.IOServiceGetMatchingServices.restype = ctypes.c_int
iokit.IOIteratorNext.argtypes = [ctypes.c_uint]
iokit.IOIteratorNext.restype = ctypes.c_uint
iokit.IORegistryEntryGetRegistryEntryID.argtypes = [ctypes.c_uint, ctypes.POINTER(ctypes.c_uint64)]
iokit.IORegistryEntryGetRegistryEntryID.restype = ctypes.c_int
iokit.IODPDeviceCreateWithService.argtypes = [ctypes.c_void_p, ctypes.c_uint]
iokit.IODPDeviceCreateWithService.restype = ctypes.c_void_p
iokit.IODPDeviceReadDPCD.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
iokit.IODPDeviceReadDPCD.restype = ctypes.c_int
iokit.IODPDeviceWriteDPCD.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
iokit.IODPDeviceWriteDPCD.restype = ctypes.c_int

cg.CGGetOnlineDisplayList.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]
cg.CGGetOnlineDisplayList.restype = ctypes.c_int
cg.CGDisplayIsBuiltin.argtypes = [ctypes.c_uint32]
cg.CGDisplayIsBuiltin.restype = ctypes.c_int
cg.CGDisplayPixelsWide.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsWide.restype = ctypes.c_size_t
cg.CGDisplayPixelsHigh.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsHigh.restype = ctypes.c_size_t
cg.CGBeginDisplayConfiguration.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
cg.CGBeginDisplayConfiguration.restype = ctypes.c_int
cg.CGCompleteDisplayConfiguration.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
cg.CGCompleteDisplayConfiguration.restype = ctypes.c_int

sl.CGSGetNumberOfDisplayModes.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_int32)]
sl.CGSGetNumberOfDisplayModes.restype = ctypes.c_int32
sl.CGSGetDisplayModeDescriptionOfLength.argtypes = [ctypes.c_uint32, ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32]
sl.CGSGetDisplayModeDescriptionOfLength.restype = ctypes.c_int32
sl.CGSGetCurrentDisplayMode.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_int32)]
sl.CGSGetCurrentDisplayMode.restype = ctypes.c_int32
sl.CGSConfigureDisplayMode.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32]
sl.CGSConfigureDisplayMode.restype = ctypes.c_int32

def find_vmm5322():
    it = ctypes.c_uint(0)
    iokit.IOServiceGetMatchingServices(0, iokit.IOServiceMatching(b"DCPDPDeviceProxy"), ctypes.byref(it))
    while True:
        svc = iokit.IOIteratorNext(it.value)
        if not svc:
            break
        eid = ctypes.c_uint64(0)
        iokit.IORegistryEntryGetRegistryEntryID(svc, ctypes.byref(eid))
        dev = iokit.IODPDeviceCreateWithService(None, svc)
        if dev:
            buf = (ctypes.c_uint8 * 16)()
            if iokit.IODPDeviceReadDPCD(dev, 0x500, buf, 16) == 0:
                if bytes(buf[:3]) == b"\x90\xcc\x24":
                    return dev, eid.value, bytes(buf)
    raise RuntimeError("No Synaptics VMM5322 (OUI 90-CC-24) found on DCPDPDeviceProxy")

dp_dev = None
service_id = 0
dpcd_500 = b""

def dpcd_read(addr, size):
    buf = (ctypes.c_uint8 * size)()
    ret = iokit.IODPDeviceReadDPCD(dp_dev, addr, buf, size)
    if ret != 0:
        raise RuntimeError(f"DPCD read 0x{addr:x} failed: 0x{ret & 0xffffffff:08x}")
    return bytes(buf)

def dpcd_write(addr, data):
    buf = (ctypes.c_uint8 * len(data))(*data)
    ret = iokit.IODPDeviceWriteDPCD(dp_dev, addr, buf, len(data))
    if ret != 0:
        raise RuntimeError(f"DPCD write 0x{addr:x} failed: 0x{ret & 0xffffffff:08x}")

def rc_send_cmd(cmd):
    dpcd_write(0x4B2, bytes([cmd | 0x80]))
    for _ in range(50):
        st = dpcd_read(0x4B2, 2)
        if (st[0] & 0x80) == 0:
            if st[1] != 0:
                raise RuntimeError(f"RC cmd 0x{cmd:x} error code: {st[1]}")
            return
        time.sleep(0.005)
    raise RuntimeError(f"RC cmd 0x{cmd:x} timeout")

def rc_enable():
    try:
        rc_send_cmd(0x02)
    except Exception:
        pass
    sc = b"PRIUS"
    dpcd_write(0x4C0, sc)
    dpcd_write(0x4BC, struct.pack("<I", 0))
    dpcd_write(0x4B8, struct.pack("<I", len(sc)))
    rc_send_cmd(0x01)

def rc_disable():
    try:
        rc_send_cmd(0x02)
    except Exception:
        pass

def rc_read_mem(addr, length):
    out = bytearray()
    for off in range(0, length, 32):
        chunk = min(32, length - off)
        dpcd_write(0x4BC, struct.pack("<I", addr + off))
        dpcd_write(0x4B8, struct.pack("<I", chunk))
        rc_send_cmd(0x31) # ReadFromMemory
        out.extend(dpcd_read(0x4C0, chunk))
    return bytes(out)

def rc_write_mem(addr, data):
    # Allowlist strictly RAM 0x1740 (EDID mode) and RAM 0x0368..0x0387 / 0x04A1 (event queue)
    if addr != 0x1740 and not (0x0368 <= addr <= 0x0387) and addr != 0x04A1:
        raise ValueError(f"Refusing write to non-allowlisted RAM address 0x{addr:x}")
    dpcd_write(0x4C0, data)
    dpcd_write(0x4BC, struct.pack("<I", addr))
    dpcd_write(0x4B8, struct.pack("<I", len(data)))
    rc_send_cmd(0x21) # WriteToMemory

def push_firmware_event(evt_byte):
    w_idx = rc_read_mem(0x04A1, 1)[0] & 0x1F
    r_idx = rc_read_mem(0x0390, 1)[0] & 0x1F
    rc_write_mem(0x0368 + w_idx, bytes([evt_byte]))
    new_w_idx = (w_idx + 1) & 0x1F
    rc_write_mem(0x04A1, bytes([new_w_idx]))
    return r_idx, w_idx, new_w_idx

def parse_dtd(dtd):
    if len(dtd) < 18 or (dtd[0] == 0 and dtd[1] == 0):
        return None
    pclk_mhz = struct.unpack("<H", dtd[0:2])[0] * 10000 / 1e6
    h_active = dtd[2] | ((dtd[4] >> 4) << 8)
    h_blank  = dtd[3] | ((dtd[4] & 0x0F) << 8)
    v_active = dtd[5] | ((dtd[7] >> 4) << 8)
    v_blank  = dtd[6] | ((dtd[7] & 0x0F) << 8)
    return f"{h_active}x{v_active} (total {h_active+h_blank}x{v_active+v_blank}, {pclk_mhz:.2f} MHz)"

def find_external_display():
    ids = (ctypes.c_uint32 * 16)()
    n = ctypes.c_uint32(0)
    cg.CGGetOnlineDisplayList(16, ids, ctypes.byref(n))
    for i in range(n.value):
        if not cg.CGDisplayIsBuiltin(ids[i]):
            return ids[i]
    return None

def set_macos_resolution(target_w, target_h):
    ext_id = find_external_display()
    if ext_id is None:
        raise RuntimeError("No external display online in CoreGraphics")
    cnt = ctypes.c_int32(0)
    sl.CGSGetNumberOfDisplayModes(ext_id, ctypes.byref(cnt))
    buf = (ctypes.c_uint8 * 212)()
    best_idx = -1
    for idx in range(cnt.value):
        ctypes.memset(buf, 0, 212)
        sl.CGSGetDisplayModeDescriptionOfLength(ext_id, idx, buf, 212)
        raw = bytes(buf)
        mw = struct.unpack_from("<I", raw, 8)[0]
        mh = struct.unpack_from("<I", raw, 12)[0]
        ref = struct.unpack_from("<H", raw, 190)[0]
        dens = struct.unpack_from("<f", raw, 208)[0]
        if mw == target_w and mh == target_h and dens < 1.5 and ref == 60:
            best_idx = idx
            break
    if best_idx < 0:
        raise RuntimeError(f"Mode {target_w}x{target_h}@60Hz (1x) not found in SkyLight table for display 0x{ext_id:x}")
    cfg = ctypes.c_void_p()
    cg.CGBeginDisplayConfiguration(ctypes.byref(cfg))
    sl.CGSConfigureDisplayMode(cfg, ext_id, best_idx)
    res = cg.CGCompleteDisplayConfiguration(cfg, 1) # kCGConfigureForSession
    return ext_id, best_idx, res

def print_status():
    cfg_1700 = rc_read_mem(0x1700, 0x80)
    r1820 = rc_read_mem(0x1820, 18)
    edid = rc_read_mem(0x1600, 128)
    mode = cfg_1700[0x40] & 0x0F
    ports = r1820[1] & 0x0F
    w0 = struct.unpack(">H", r1820[2:4])[0]
    w1 = struct.unpack(">H", r1820[4:6])[0]
    w2 = struct.unpack(">H", r1820[10:12])[0]
    v_h = struct.unpack(">H", r1820[15:17])[0]
    print(f"Synaptics VMM5322 @ DCPDPDeviceProxy 0x{service_id:x}")
    print(f"  Chip ID: 0x{dpcd_500[7]:02x}{dpcd_500[8]:02x} (FW {dpcd_500[10]}.{dpcd_500[11]:02d}.{dpcd_500[12]:03d}, Board 0x{cfg_1700[0x0e]:02x}{cfg_1700[0x0f]:02x})")
    print(f"  RAM 0x1740 (EDID Mode): 0x{cfg_1700[0x40]:02x} -> mode={mode} ({'ViewXpand Split' if mode == 2 else 'Pass-Through / Mirror'})")
    print(f"  RAM 0x1821 (Monitors):  0x{r1820[1]:02x} -> {ports} monitors connected, active_timings=(upstream={w0}, TX0={w1}, TX2={w2} x {v_h})")
    for idx, off in enumerate(range(54, 126, 18), 1):
        desc = parse_dtd(edid[off:off+18])
        if desc:
            print(f"  Upstream EDID (0x{0x1600+off:04x}) DTD #{idx}: {desc}")
        else:
            tag = edid[off+3]
            if tag == 0xFF:
                text = "<REDACTED_SERIAL>"
            else:
                text = edid[off+5:off+18].decode("latin1", errors="replace").strip()
            print(f"  Upstream EDID (0x{0x1600+off:04x}) Desc #{idx} (tag 0x{tag:02x}): {text!r}")
    ext_id = find_external_display()
    if ext_id is not None:
        print(f"  macOS External Display: 0x{ext_id:x} -> {cg.CGDisplayPixelsWide(ext_id)}x{cg.CGDisplayPixelsHigh(ext_id)}")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    dp_dev, service_id, dpcd_500 = find_vmm5322()
    rc_enable()
    try:
        if cmd == "status":
            print_status()
        elif cmd == "split-edid":
            cur = rc_read_mem(0x1740, 1)[0]
            rc_write_mem(0x1740, bytes([(cur & 0xF0) | 0x02]))
            r_idx, w_idx, new_w = push_firmware_event(0xC2)
            print(f"Wrote RAM 0x1740 = 0x{(cur & 0xF0) | 0x02:02x} and pushed event 0xC2 (queue {w_idx} -> {new_w}, r={r_idx})")
            time.sleep(0.05)
            print_status()
        elif cmd == "split-apply":
            cur = rc_read_mem(0x1740, 1)[0]
            rc_write_mem(0x1740, bytes([(cur & 0xF0) | 0x02]))
            push_firmware_event(0xC2)
            time.sleep(0.05)
            ext_id = find_external_display()
            need_hpd = True
            if ext_id is not None:
                try:
                    set_macos_resolution(3840, 1080)
                    need_hpd = False
                except RuntimeError:
                    need_hpd = True
            if need_hpd:
                push_firmware_event(0xC6)
                rc_disable()
                time.sleep(3.5)
                dp_dev, service_id, dpcd_500 = find_vmm5322()
                rc_enable()
                set_macos_resolution(3840, 1080)
                time.sleep(1.5)
            print_status()
        elif cmd == "mirror":
            cur = rc_read_mem(0x1740, 1)[0]
            rc_write_mem(0x1740, bytes([(cur & 0xF0) | 0x03]))
            push_firmware_event(0xC2)
            time.sleep(0.05)
            set_macos_resolution(1920, 1080)
            time.sleep(1.0)
            print_status()
        else:
            print(f"Unknown command: {cmd}")
            sys.exit(2)
    finally:
        rc_disable()
