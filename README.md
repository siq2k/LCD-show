# LCD-show — Trixie 32-bit Desktop Setup for lcdwiki 3.5inch RPi Display

This fork adds support for running the [lcdwiki 3.5inch RPi Display (ILI9486)](http://www.lcdwiki.com/3.5inch_RPi_Display) on **Raspberry Pi OS Trixie 32-bit Desktop**. The stock goodtft LCD-show scripts do not work correctly on Trixie without additional fixes. This README documents all required changes and provides two setup scripts to automate the process.

## Hardware

- Raspberry Pi (tested on Pi Zero 2W and Pi 3B)
- lcdwiki 3.5inch RPi Display (480x320, ILI9486, SPI)
- Fresh Raspberry Pi OS Trixie 32-bit Desktop image

## Why stock LCD35-show doesn't work on Trixie

The stock `LCD35-show` script was written for older Raspbian releases. On Trixie the following issues occur:

1. **Wrong boot path** — the script targets `/boot/config.txt` but Trixie uses `/boot/firmware/config.txt`. This is handled by a symlink created in `system_config.sh` so it actually works, but is worth noting.
2. **Duplicate `hdmi_mode`** — the script writes `hdmi_mode=1` followed by `hdmi_mode=87`, causing the Pi to output the wrong resolution.
3. **`libraspberrypi-dev` missing** — the fbcp build fails silently because this package no longer exists on Trixie. The script installs no framebuffer copier.
4. **`vc4-kms-v3d` conflict** — if enabled, this overlay conflicts with the SPI display driver and breaks the framebuffer setup.
5. **`glamor-test.service`** — runs at boot and recreates `/etc/X11/xorg.conf.d/99-v3d.conf`, injecting a modesetting device that causes Xorg to fail with "Cannot run in framebuffer mode".
6. **`rp1-test.service`** — also runs at boot and recreates `99-v3d.conf` with a modesetting OutputClass, same result.
7. **SysV init script conflict** — `/etc/init.d/lightdm` is processed by `systemd-sysv-generator` and injects conditions into the lightdm unit that prevent it from starting at boot.
8. **`/dev/tty0` permissions** — Xorg requires group read access to `/dev/tty0` which Trixie does not grant by default. This must be chmod'd before lightdm starts.
9. **`graphical.target` not set as default** — Trixie may boot to `multi-user.target`, preventing the desktop from starting.
10. **Polkit duplicate agents** — `lxpolkit` and `polkit-mate-authentication-agent-1` both start alongside the RPD polkit agent, causing a GDBus error on desktop load.
11. **No framebuffer copier** — since fbcp-ili9341 and rpi-fbcp both require `bcm_host.h` (removed in Trixie), a Python/numpy based fb0→fb1 copier is used instead.
12. **Display rotation** — the stock script sets `rotate=90` but this display requires `rotate=270`.

## Setup Instructions

### Prerequisites

Flash a fresh **Raspberry Pi OS Trixie 32-bit Desktop** image using Raspberry Pi Imager. Enable SSH during flashing. Boot the Pi and connect via SSH.

### Step 1 — Copy setup scripts to the Pi

From your build machine:

```bash
scp setup_part1.sh <username>@<pi-ip>:~/
scp setup_part2.sh <username>@<pi-ip>:~/
chmod +x ~/setup_part1.sh ~/setup_part2.sh
```

Or download directly on the Pi:

```bash
curl -O https://raw.githubusercontent.com/siq2k/LCD-show/main/setup_part1.sh
curl -O https://raw.githubusercontent.com/siq2k/LCD-show/main/setup_part2.sh
chmod +x setup_part1.sh setup_part2.sh
```

### Step 2 — Run Part 1

```bash
bash ~/setup_part1.sh
```

This clones the goodtft LCD-show repo and runs `LCD35-show`, which installs the display overlay, configures `/boot/firmware/config.txt`, installs touch input support, and reboots automatically.

### Step 3 — Run Part 2 after reboot

SSH back in after the reboot and run:

```bash
bash ~/setup_part2.sh
```

This script applies all Trixie-specific fixes and reboots. After the final reboot the desktop will appear on the SPI display.

## What setup_part2.sh does

| Step | Action |
|------|--------|
| 1 | Fixes display rotation from 90° to 270° |
| 2 | Removes duplicate `hdmi_mode=1` left by LCD35-show |
| 3 | Disables `vc4-kms-v3d` overlay to prevent framebuffer conflict |
| 4 | Sets `graphical.target` as the default boot target |
| 5 | Replaces the lightdm systemd unit to remove DRI device dependencies and adds `chmod 620 /dev/tty0` pre-start |
| 6 | Sets `logind-check-graphical=false` and `xserver-command=X -core` in lightdm.conf |
| 7 | Creates `/etc/X11/xorg.conf.d/99-fbdev.conf` pointing Xorg at `/dev/fb0` with AutoAddDevices disabled |
| 8 | Masks `glamor-test` and `rp1-test` services and removes any existing `99-v3d.conf` |
| 9 | Removes the SysV lightdm init script that injects boot conditions |
| 10 | Disables duplicate polkit agents (lxpolkit and polkit-mate) for the rpd-x session |
| 11 | Installs a Python/numpy framebuffer copier service (fb0→fb1 at ~30fps) |
| 12 | Installs a shutdown service that clears the SPI display to black on poweroff |
| 13 | Fixes `.bash_profile` to source `.bashrc` on login |
| 14 | Reloads systemd and reboots |

## Notes

- `setup_part2.sh` targets the user running the script (`$USER`) by default. To override, run `TARGET_USER=<username> bash setup_part2.sh`.
- The framebuffer copier converts 32bpp (fb0) to 16bpp RGB565 (fb1) using numpy for performance.
- The display runs at approximately 30fps via the Python copier. This is adequate for desktop use on a Pi Zero 2W or Pi 3B.
- Touch calibration is handled by the stock LCD35-show script via `99-calibration.conf`.

---

# Original goodtft LCD-show README

# 2.8inch RPi LCD (A)

### Description:

This is a 2.8inch TFT LCD with resistive touch panel, has 320x240 resolution. It can support any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali.

### Website：

CN: http://www.waveshare.net/shop/2.8inch-RPi-LCD-A.htm

EN: https://www.waveshare.com/2.8inch-rpi-lcd-a.htm

### WIKI：

CN: http://www.waveshare.net/wiki/2.8inch_RPi_LCD_(A)

EN: https://www.waveshare.com/wiki/2.8inch_RPi_LCD_(A)

### Driver install：

sudo ./LCD28-show


# 3.2inch RPi LCD (B)

### Description:

This is a 3.2inch TFT LCD with resistive touch panel, has 320x240 resolution. Can support any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali. 

### Website：

CN: http://www.waveshare.net/shop/3.2inch-RPi-LCD-B.htm

EN: https://www.waveshare.com/3.2inch-rpi-lcd-b.htm

### WIKI：

CN: http://www.waveshare.net/wiki/3.2inch_RPi_LCD_(B)

EN: https://www.waveshare.com/wiki/3.2inch_RPi_LCD_(B)

### Driver install:

sudo ./LCD32-show

# 3.2inch RPi LCD (C)

### Description: 

This is a 3.2inch TFT LCD with resistive touch panel, has 320x240 hardware resolution.Support up to 125MHz high-speed SPI signal transmission provide you a clear and stable display effect.. Can directly plug to any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali and Retropie(Can only display when working with Retropie).

### Website:

CN: http://www.waveshare.net/shop/3.2inch-RPi-LCD-C.htm

EN: https://www.waveshare.com/3.2inch-rpi-lcd-c.htm

### WIKI:

CN: http://www.waveshare.net/wiki/3.2inch_RPi_LCD_(C)

EN: https://www.waveshare.com/wiki/3.2inch_RPi_LCD_(C)

### Driver install:

sudo ./LC32C-show

# 3.5inch RPi LCD (A)

### Description:

This is a 3.5inch TFT LCD with resistive touch panel, has 480x320 resolution. Can support any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali. 

### Website:

CN:http://www.waveshare.net/shop/3.5inch-RPi-LCD-A.htm

EN:https://www.waveshare.com/product/3.5inch-rpi-lcd-a.htm

### WIKI:

CN:http://www.waveshare.net/wiki/3.5inch_RPi_LCD_(A)

EN:https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)

### Driver install:

sudo ./LCD35-show

# 3.5inch RPi LCD (B)

### Description:

This is a 3.5inch TFT LCD with resistive touch panel, has 480x320 resolution. Can support any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali. And this is an IPS screen which has wider viewing angle.

### Website:

CN:http://www.waveshare.net/shop/3.5inch-RPi-LCD-B.htm

EN:https://www.waveshare.com/3.5inch-RPi-LCD-B.htm

### WIKI:

CN:http://www.waveshare.net/wiki/3.5inch_RPi_LCD_(B)

EN:https://www.waveshare.com/wiki/3.2inch_RPi_LCD_(B)

### Driver install:

sudo ./LCD35B-show V2

# 3.5inch RPi LCD (C)

### Description:

This is a 3.5inch TFT LCD with resistive touch panel, has 480x320 resolution. Support up to 125MHz high-speed SPI signal transmission provide you a clear and stable display effect.. Can directly plug to any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali and Retropie(Can only display when working with Retropie).

### Webiste：

CN:http://www.waveshare.net/shop/3.5inch-RPi-LCD-C.htm

EN:https://www.waveshare.com/3.5inch-rpi-lcd-c.htm

### WIKI：

CN:http://www.waveshare.net/wiki/3.5inch_RPi_LCD_(C)

EN:https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(C)

### Driver Install：

sudo ./LCD35C-show

# 3.5inch HDMI LCD

### Description:

This is a 3.5inch IPS screen with resistive touch panel, has 480x320 hardware resolution, use HDMI interface for displaying and GPIO for touching. Touch driver is provide for Raspbian, Ubuntu Mate,Kali and Retropie(Can only display when working with Retropie).

### Website:

CN: http://www.waveshare.net/shop/3.5inch-HDMI-LCD.htm

EN: https://www.waveshare.com/product/3.5inch-hdmi-lcd.htm

### WIKI:

CN: http://www.waveshare.net/wiki/3.5inch_HDMI_LCD

EN: https://www.waveshare.com/wiki/3.5inch_HDMI_LCD

### Display setting:

For properly display, you need to root directory of SD card (/boot/).

max_usb_current=1

hdmi_group=2

hdmi_mode=87

hdmi_cvt 800 480 60 6 0 0 0

hdmi_drive=2

### Driver install (touch):

sudo ./LCD35-HDMI-480x320-show

# 4inch RPi LCD (A)

### Description:

This is a 4inch resistive LCD, IPS screen, 480x320 resoltuion, designed for Raspberry Pi. Driver is required for Raspbian, Ubuntu Mate,Kali.

### Website:

CN: http://www.waveshare.net/shop/4inch-RPi-LCD-A.htm

EN: https://www.waveshare.com/4inch-RPi-LCD-A.htm

### Wiki:

CN: http://www.waveshare.net/wiki/4inch_RPi_LCD_(A)

EN: https://www.waveshare.com/wiki/4inch_RPi_LCD_(A)

### Driver install:

sudo ./LCD4-show

# 4inch RPi LCD (C)

### Description:

This is a 4inch TFT LCD with resistive touch panel, has 480x320 resolution. Support up to 125MHz high-speed SPI signal transmission provide you a clear and stable display effect. Can directly plug to any revision of Raspberry Pi. Driver is provided for Raspbian/Ubuntu Mate/kali and Retropie(Can only display when working with Retropie).

### Website:

CN: http://www.waveshare.net/shop/4inch-RPi-LCD-C.htm

EN: https://www.waveshare.com/4inch-rpi-lcd-c.htm

### WiKi:

CN: http://www.waveshare.net/wiki/4inch_RPi_LCD_(C)

EN: https://www.waveshare.com/wiki/4inch_RPi_LCD_(C)

### Driver install:

sudo ./LCD4C-show

# 4inch HDMI LCD 

### Description:

This is a 4inch IPS screens, 800x480 resolution, HDMI display. Designed for Raspberry Pi. Note that this screen is vertically display by default.

### Website:

CN: http://www.waveshare.net/shop/4inch-HDMI-LCD.htm 

EN: https://www.waveshare.com/4inch-hdmi-lcd.htm

### WiKi:

CN: http://www.waveshare.net/wiki/4inch_HDMI_LCD

EN: https://www.waveshare.com/wiki/4inch_HDMI_LCD

### Display Setting:

hdmi_group=2

hdmi_mode=87

hdmi_cvt 480 800 60 6 0 0 0

dtoverlay=ads7846,cs=1,penirq=25,penirq_pull=2,speed=50000,keep_vref_on=0,swapxy=0,pmax=255,xohms=150,xmin=200,xmax=3900,ymin=200,ymax=3900

display_rotate=3

### Driver Install:

sudo ./LCD4-800x480-show

# 4.3inch HDMI LCD 

### Description:

This is a 4.3inch IPS screens, 800x480 resolution, HDMI display. Designed for Raspberry Pi. Driver is required for touching. Note that this LCD can only support Raspberry Pi

### Website:

CN: http://www.waveshare.net/shop/4.3inch-HDMI-LCD.htm

EN: https://www.waveshare.com/wiki/4inch_HDMI_LCD

### WiKi:

CN: http://www.waveshare.net/wiki/4.3inch_HDMI_LCD

EN: https://www.waveshare.com/wiki/4.3inch_HDMI_LCD

### Display Setting:

display_rotate=2

max_usb_current=1

hdmi_group=2

hdmi_mode=87

hdmi_cvt 480 272 60 6 0 0 0

dtoverlay=ads7846,cs=1,penirq=25,penirq_pull=2,speed=50000,keep_vref_on=0,swapxy=0,pmax=255,xohms=150,xmin=200,xmax=3900,ymin=200,ymax=3900

hdmi_drive=1

hdmi_force_hotplug=1

### Driver Install:

sudo ./LCD43-show-V2

# 5inch HDMI LCD

### Description:

This is a 5inch Resistive Touch Screen LCD, 800x480 resolution, HDMI interface. Designed for Raspberry Pi. Note that this LCD can only support Raspberry Pi.

### Website:

CN: http://www.waveshare.net/shop/5inch-HDMI-LCD.htm

EN: https://www.waveshare.com/product/5inch-hdmi-lcd.htm

### WiKi:

CN: http://www.waveshare.net/wiki/5inch_HDMI_LCD

EN: https://www.waveshare.com/wiki/5inch_HDMI_LCD

### Display Setting:

max_usb_current=1

hdmi_group=2

hdmi_mode=87

hdmi_cvt 800 480 60 6 0 0 0

hdmi_drive=1

### Driver Install:

sudo ./LCD5-show

# 7inch HDMI LCD

### Description:

This is a 7inch resistive touch screen LCD, 1024x600 resolution, HDMI interface, designed for Raspberry Pi

### Website:

CN:http://www.waveshare.net/shop/7inch-HDMI-LCD.htm

EN:https://www.waveshare.com/product/7inch-hdmi-lcd.htm

### WiKi:

CN:http://www.waveshare.net/wiki/7inch_HDMI_LCD

EN:https://www.waveshare.com/wiki/7inch_HDMI_LCD

### Display Setting:

max_usb_current=1

hdmi_group=2

hdmi_mode=87

hdmi_cvt 1024 600 60 6 0 0 0

### Driver install:

sudo ./LCD7-1024x600-show

# 10.1inch HDMI LCD
### Description

This is a 10.1inch resistive touch screen LCD, 1024x600 resolution, HDMI interface, designed for Raspberry Pi

### Website:

CN:http://www.waveshare.net/shop/10.1inch-HDMI-LCD.htm

EN:https://www.waveshare.com/product/10.1inch-hdmi-lcd.htm

### WiKi:

CN:http://www.waveshare.net/wiki/10.1inch_HDMI_LCD

EN:https://www.waveshare.com/wiki/10.1inch_HDMI_LCD

### Display Setting:

max_usb_current=1

hdmi_group=2

hdmi_mode=87

hdmi_cvt 1024 600 60 6 0 0 0

### Driver install:

sudo ./LCD101-1024x600-show
