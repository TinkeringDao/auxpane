/*
 * SPDX-License-Identifier: MIT
 *
 * DockCore implementation for Lenovo ThinkPad Thunderbolt 3 Dock Gen 2 (40AN)
 * and Synaptics VMM5322 (Panamera, OUI 90-CC-24, Board 0x0253) over macOS
 * native IOKit IODPDevice DPCD Remote Control (0x4B0..0x4FF).
 */

#include "DockCore.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern void *IODPDeviceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IODPDeviceReadDPCD(void *device, uint32_t address, void *buffer, uint32_t size);
extern IOReturn IODPDeviceWriteDPCD(void *device, uint32_t address, const void *buffer, uint32_t size);

#define MST_CMD_ENABLE_RC    0x01
#define MST_CMD_DISABLE_RC   0x02
#define MST_CMD_CHECKSUM     0x11
#define MST_CMD_WRITE_MEMORY 0x21
#define MST_CMD_READ_FLASH   0x30
#define MST_CMD_READ_MEMORY  0x31
#define MST_CHUNK            32

struct dc_handle {
	void *dp_dev;
	uint8_t dpcd_500[16];
	int rc_enabled;
	char err[256];
};

static int
fail(dc_handle *h, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(h->err, sizeof(h->err), fmt, ap);
	va_end(ap);
	return -1;
}

const char *
dc_last_error(const dc_handle *h)
{
	return h ? h->err : "no handle";
}

static int
dpcd_read(dc_handle *h, uint32_t addr, uint32_t len, uint8_t *out)
{
	IOReturn kr = IODPDeviceReadDPCD(h->dp_dev, addr, out, len);
	if (kr != kIOReturnSuccess)
		return fail(h, "DPCD read 0x%x failed (0x%08x)", addr, kr);
	return 0;
}

static int
dpcd_write(dc_handle *h, uint32_t addr, const uint8_t *data, uint32_t len)
{
	IOReturn kr = IODPDeviceWriteDPCD(h->dp_dev, addr, data, len);
	if (kr != kIOReturnSuccess)
		return fail(h, "DPCD write 0x%x failed (0x%08x)", addr, kr);
	return 0;
}

static int
rc_send_cmd(dc_handle *h, uint8_t cmd)
{
	uint8_t c = cmd | 0x80;
	uint8_t st[2];
	if (dpcd_write(h, 0x4B2, &c, 1))
		return -1;
	for (int i = 0; i < 100; i++) {
		if (dpcd_read(h, 0x4B2, 2, st))
			return -1;
		if ((st[0] & 0x80) == 0) {
			if (st[1] != 0)
				return fail(h, "RC cmd 0x%02x error %u", cmd, st[1]);
			return 0;
		}
		usleep(3000);
	}
	return fail(h, "RC cmd 0x%02x timeout", cmd);
}

static int
mst_rc_command(dc_handle *h, uint8_t cmd, uint32_t length, uint32_t offset, const uint8_t *data)
{
	if (data != NULL && length > 32)
		return fail(h, "RC payload too long");
	if (data != NULL && length > 0) {
		if (dpcd_write(h, 0x4C0, data, length))
			return -1;
	}
	if (dpcd_write(h, 0x4BC, (const uint8_t *)&offset, 4))
		return -1;
	if (dpcd_write(h, 0x4B8, (const uint8_t *)&length, 4))
		return -1;
	return rc_send_cmd(h, cmd);
}

static int
mst_begin(dc_handle *h, int need_rc)
{
	if (!need_rc)
		return 0;
	if (mst_rc_command(h, MST_CMD_ENABLE_RC, 5, 0, (const uint8_t *)"PRIUS") != 0) {
		mst_rc_command(h, MST_CMD_DISABLE_RC, 0, 0, NULL);
		if (mst_rc_command(h, MST_CMD_ENABLE_RC, 5, 0, (const uint8_t *)"PRIUS") != 0)
			return fail(h, "could not enable Synaptics DPCD RC");
	}
	h->rc_enabled = 1;
	return 0;
}

static void
mst_end(dc_handle *h)
{
	if (h->rc_enabled) {
		mst_rc_command(h, MST_CMD_DISABLE_RC, 0, 0, NULL);
		h->rc_enabled = 0;
	}
}

static int
rc_read(dc_handle *h, uint8_t cmd, uint32_t addr, uint32_t len, uint8_t *out)
{
	if (mst_rc_command(h, cmd, len, addr, NULL))
		return -1;
	return dpcd_read(h, 0x4C0, len, out);
}

static int
push_firmware_event(dc_handle *h, uint8_t evt)
{
	uint8_t w_idx = 0, next_w = 0;
	if (rc_read(h, MST_CMD_READ_MEMORY, 0x04A1, 1, &w_idx))
		return -1;
	w_idx &= 0x1F;
	if (mst_rc_command(h, MST_CMD_WRITE_MEMORY, 1, 0x0368 + w_idx, &evt))
		return -1;
	next_w = (w_idx + 1) & 0x1F;
	return mst_rc_command(h, MST_CMD_WRITE_MEMORY, 1, 0x04A1, &next_w);
}

int
dc_open(dc_handle **out)
{
	io_iterator_t it = 0;
	io_service_t svc;
	dc_handle *h = calloc(1, sizeof(*h));

	*out = h;
	if (h == NULL)
		return -1;
	if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPDPDeviceProxy"), &it) != kIOReturnSuccess)
		return fail(h, "cannot iterate DCPDPDeviceProxy");
	while ((svc = IOIteratorNext(it)) != 0) {
		void *dev = IODPDeviceCreateWithService(kCFAllocatorDefault, svc);
		IOObjectRelease(svc);
		if (dev != NULL) {
			uint8_t b[16] = {0};
			if (IODPDeviceReadDPCD(dev, 0x500, b, 16) == kIOReturnSuccess &&
			    b[0] == 0x90 && b[1] == 0xCC && b[2] == 0x24) {
				h->dp_dev = dev;
				memcpy(h->dpcd_500, b, 16);
				break;
			}
			CFRelease(dev);
		}
	}
	IOObjectRelease(it);
	if (h->dp_dev == NULL)
		return fail(h, "no Synaptics VMM5322 MST hub found on DCPDPDeviceProxy");
	return 0;
}

void
dc_close(dc_handle *h)
{
	if (h == NULL)
		return;
	if (h->dp_dev) {
		mst_end(h);
		CFRelease(h->dp_dev);
	}
	free(h);
}

int
dc_dock_info_read(dc_handle *h, dc_dock_info *out)
{
	uint8_t cfg[16] = {0};
	memset(out, 0, sizeof(*out));
	if (dc_mst_read_memory(h, DC_RAM_CONFIG, 16, cfg))
		return -1;
	out->hub_major = h->dpcd_500[7];
	out->hub_minor = h->dpcd_500[8];
	out->base_type = 0x04;
	snprintf(out->marketing_name, sizeof(out->marketing_name), "ThinkPad TB3 Dock Gen 2 (40AN)");
	snprintf(out->service_tag, sizeof(out->service_tag), "0x%02X%02X", cfg[14], cfg[15]);
	out->module_type = ((uint16_t)h->dpcd_500[7] << 8) | h->dpcd_500[8];
	out->board_id = ((uint16_t)cfg[14] << 8) | cfg[15];
	out->power_supply_watts = 135;
	out->package_version = ((uint32_t)h->dpcd_500[13] << 8) | h->dpcd_500[14];
	out->mst_version[0] = h->dpcd_500[10];
	out->mst_version[1] = h->dpcd_500[11];
	out->mst_version[2] = h->dpcd_500[12];
	out->has_mst_version = 1;
	return 0;
}

int
dc_mst_status_read(dc_handle *h, dc_mst_status *out)
{
	memset(out, 0, sizeof(*out));
	out->active_bank = 0;
	out->running_firmware = 1;
	out->fw_version_reg[0] = h->dpcd_500[10];
	out->fw_version_reg[1] = h->dpcd_500[11];
	out->fw_version_reg[2] = h->dpcd_500[12];
	out->fw_version_reg[3] = h->dpcd_500[9];
	return 0;
}

int
dc_mst_read_memory(dc_handle *h, uint32_t addr, uint32_t len, uint8_t *out)
{
	int r = mst_begin(h, 1);
	for (uint32_t off = 0; r == 0 && off < len; off += MST_CHUNK) {
		uint32_t n = len - off < MST_CHUNK ? len - off : MST_CHUNK;
		r = rc_read(h, MST_CMD_READ_MEMORY, addr + off, n, out + off);
	}
	mst_end(h);
	return r;
}

int
dc_mst_read_flash(dc_handle *h, uint32_t offset, uint32_t len, uint8_t *out,
		  void (*progress)(uint32_t done, uint32_t total, void *ctx), void *ctx)
{
	int r = mst_begin(h, 1);
	for (uint32_t off = 0; r == 0 && off < len; off += MST_CHUNK) {
		uint32_t n = len - off < MST_CHUNK ? len - off : MST_CHUNK;
		r = rc_read(h, MST_CMD_READ_FLASH, offset + off, n, out + off);
		if (progress && (off & 0x3fff) == 0)
			progress(off, len, ctx);
	}
	if (r == 0 && progress)
		progress(len, len, ctx);
	mst_end(h);
	return r;
}

int
dc_mst_checksum(dc_handle *h, uint32_t start, uint32_t len, uint32_t *sum)
{
	uint8_t b[4];
	int r = mst_begin(h, 1);
	if (r == 0)
		r = mst_rc_command(h, MST_CMD_CHECKSUM, len, start, NULL);
	if (r == 0)
		r = dpcd_read(h, 0x4C0, 4, b);
	if (r == 0)
		memcpy(sum, b, 4);
	mst_end(h);
	return r;
}

int
dc_mst_read_register(dc_handle *h, uint32_t addr, uint32_t len, uint8_t *out)
{
	return dpcd_read(h, addr, len, out);
}

int
dc_mst_set_edid_mode(dc_handle *h, uint8_t mode, uint8_t before[4], uint8_t after[4])
{
	uint8_t cur[4], next[4], chk[4];
	int r;

	if (mode > 4)
		return fail(h, "EDID mode %u out of range (0-4)", mode);
	r = mst_begin(h, 1);
	if (r == 0)
		r = rc_read(h, MST_CMD_READ_MEMORY, DC_RAM_EDID_MODE, 4, cur);
	if (r == 0) {
		memcpy(next, cur, 4);
		next[0] = (uint8_t)((cur[0] & 0xf0) | mode);
		if (memcmp(next, cur, 4) != 0)
			r = mst_rc_command(h, MST_CMD_WRITE_MEMORY, 4, DC_RAM_EDID_MODE, next);
	}
	if (r == 0)
		r = rc_read(h, MST_CMD_READ_MEMORY, DC_RAM_EDID_MODE, 4, chk);
	if (r == 0 && memcmp(chk, next, 4) != 0)
		r = fail(h, "EDID mode read-back mismatch");
	if (r == 0) {
		/* Rebuild upstream EDID (0xC2) and pulse HPD / split pipes (0xC6) in software. */
		push_firmware_event(h, 0xC2);
		usleep(50000);
		push_firmware_event(h, 0xC6);
	}
	if (r == 0 && before)
		memcpy(before, cur, 4);
	if (r == 0 && after)
		memcpy(after, chk, 4);
	mst_end(h);
	return r;
}
