# Samsung Galaxy Tab A7 10.4 (2022) SM-T509 — kernel and boot image

This tree is the Samsung open-source kernel for the SM-T509 (gta4lve), prepared
for the HakiOS port. It is based on:

- Repository: `Mkolpo90/android_open_source_kernel_gta4lve`
- Branch: `T509XXS3AXJ2`
- Kernel: Linux 4.14.199 (Samsung/Unisoc vendor tree)
- Defconfig: `arch/arm64/configs/gta4lve_eur_open_defconfig`

The stock repository stores many DTS files in Git LFS. The real T509 DTS files
have been restored in this tree (not LFS pointers), and the build/pack scripts
are in `t509/`.

## Device (verified from the live unit)

| Item | Value |
| --- | --- |
| Model | SM-T509, board `P15945AA1` |
| SoC | Unisoc UMS512-AC / T618 (6x A55 + 2x A75) |
| GPU | Mali-G52 MP2 (`sprd,mali-gondul`) |
| RAM | 3 GB at `0x80000000` |
| Storage | 32 GB eMMC (`CONFIG_MMC_SPRD_SDHCR11=y`) |
| Display | 10.4" 2000x1200, `lcd_hx83102e_lide_al_hsd_video_fhdp`, 4-lane DSI |
| Touch | Himax HX83102E, active input device `himax-touchscreen` |
| PMIC / charger | SC2730, Feimaotui 7040 mAh battery |
| Wi-Fi / BT | Unisoc SC2355 (Marlin3) |
| USB | MUSB at `0x5fff0000`, Type-C SC27xx |
| Bootloader | `T509XXS3AXJ2`, unlocked (`flash.locked=0`) |
| Current system | TrebleDroid Android 13 GSI (for bring-up) |

The touch DTS node has both compatibles (`novatek,NVT-ts-spi` and
`himax,hxcommon`). On the live unit the Himax driver binds and reports
`himax-touchscreen`; the stock defconfig builds both the Himax HX83102E and
Novatek NT36523B drivers.

## Build

```bash
# default: GCC 10.3, with the -Werror removal already applied to Makefile
./t509/build-t509.sh

# exact vendor compiler: Clang r383902 + GCC 10.3 binutils
USE_CLANG=1 ./t509/build-t509.sh
```

The script expects the workspace tools at `../../tools/` (GCC 10.3, portable
host tools, OpenSSL headers). It writes `out/arch/arm64/boot/Image`.

The top-level `Makefile` has `-Werror` removed because the vendor tree produces
many format/prototype warnings with GCC 10.3. The original is saved as
`Makefile.orig`. The stock build used Clang r383902; `USE_CLANG=1` selects it.

## Pack and verify

```bash
./t509/pack-boot.sh
./t509/verify-boot.sh out/boot-t509.img
```

`pack-boot.sh` uses the stock ramdisk and stock DTB in `t509/boot/` and only
replaces the kernel `Image`. It reproduces the stock boot header:

- header v2, page size 2048
- kernel load `0x00008000`, ramdisk load `0x01000000`, tags `0x00000100`
- DTB load `0x0001f00000`
- board `SRPVF15B003`
- cmdline `console=ttyS1,115200n8`
- OS 11.0.0, patch 2024-10

After the Android boot image it appends `SEANDROIDENFORCE` and pads to the
64 MiB `boot` partition (`mmcblk0p40`). The stock boot image SHA-256 was:

```
8bd0bef0d209b6d4983317d6add5f49ac30e1b689148863a3161a358075c7806
```

`verify-boot.sh` compares the header fields to
`t509/boot/stock-header.bin`, checks that the ramdisk and DTB are byte-identical
to stock, checks the `ARMd` kernel magic, the marker, and the 64 MiB size.

## Flash and restore

The device must be rooted (`adb root`) and the bootloader unlocked. Only the
`boot` partition is touched.

```bash
adb push out/boot-t509.img /data/local/tmp/boot-t509.img
adb shell 'dd if=/data/local/tmp/boot-t509.img of=/dev/block/by-name/boot bs=1M conv=fsync'
adb shell 'sha256sum /dev/block/by-name/boot'   # must match the host SHA-256
adb reboot
```

Restore the previous boot image with the same command using
`device/dump/boot.img` (the workspace copy). The TWRP recovery partition was
verified byte-identical to `device/dump/recovery.img` (SHA-256
`33af5ab77f223716429cbba159f6ffa2e10aead8db7670cc6ebc3e93630bebb9`).

If the new kernel does not boot:

1. Hold **Vol Up + Power** to enter TWRP (or `adb reboot recovery` if Android
   still responds).
2. In TWRP, push `device/dump/boot.img` and write it to
   `/dev/block/by-name/boot` with `dd`.
3. If TWRP is unavailable, use Odin/download mode (Vol Down + Vol Up, connect
   USB) and flash the stock AP, or at least the stock `boot`/`recovery`/`dtbo`.

Never flash `uboot`, `uboot_bak`, `sml`, `sml_bak`, `trustos`, `trustos_bak`,
`tzar`, `vbmeta`, `vbmeta_bak`, `pm_sys`, `teecfg`, `teecfg_bak`, or `grd_fw`
during bring-up. A bad bootloader/trustzone image is a hard brick.

## Driver coverage in this tree

- Display: SPRD DRM/DPU/DSI, HX83102E panel, SPRD PWM backlight
- Touch: Himax HX83102E and Novatek NT36523B (SPI)
- Storage: SPRD SDHCR11 eMMC, MMC block, boot device
- USB: MUSB SPRD dual-role, SC27xx Type-C, USB gadget/MTP/adb
- Power: SC2730 PMIC/regulators, SC27xx charger, fuel gauge, ADC, efuse
- Wi-Fi/BT: SC2355/WCN boot and sleep, Marlin3 firmware loader
- Audio: SPRD VBC/AGDSP and SC2730 codec
- GPU: Mali-G52 (`sprd,mali-gondul`)
- Sensors: MMC5603 magnetometer, hall/grip, GPIO keys
- Debug: sysdump, ramdump, serial `ttyS1`, watchdog

The vendor tree contains the full Unisoc UMS512/Sharkl5Pro driver set; the
defconfig enables the T509 subset.

## Kernel version note

The stock running kernel is:

```
4.14.199-26336416-abT509XXS3AXJ2
```

A first test build from a dirty tree with an empty `CONFIG_LOCALVERSION`
reports `4.14.199+`. The six vendor modules in `/vendor/lib/modules`
(incrementalfs, kheaders, trace helpers) will reject that vermagic, but the
main display/touch/storage/USB/PMIC drivers are built into the Image. To match
the stock vermagic exactly, set:

```
CONFIG_LOCALVERSION="-26336416-abT509XXS3AXJ2"
```

and commit the tree so `scripts/setlocalversion` does not append `+`. The
stock localversion can also be passed on the make command line:

```bash
make O=out LOCALVERSION=-26336416-abT509XXS3AXJ2 Image
```

## Status

- Stock kernel source checked out and built with GCC 10.3.
- Kernel `Image` SHA-256: `8cd982dbc9ca1abd6b9b0c40acc0603fd59d62c077d57bb3a639a28ce96f810f`.
- Packed boot image SHA-256: `4894048e7c215b0606b4cdf9e42b049bb03f3eddfb2b0e47d0e8798e8b02f6b9`.
- Boot image header, ramdisk, and DTB verified against stock.
- First boot test: boot partition written and device rebooted; see the
  workspace `device/dump/` for the stock rollback image.
