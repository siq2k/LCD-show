#!/bin/bash
set -e

TARGET_USER="${TARGET_USER:-$USER}"

echo "=== Step 1: Fix display rotation and SPI speed ==="
sudo sed -i 's/dtoverlay=tft35a:rotate=90/dtoverlay=tft35a:rotate=270,speed=42000000/' /boot/firmware/config.txt

echo "=== Step 2: Fix duplicate hdmi_mode ==="
sudo sed -i '/^hdmi_mode=1$/d' /boot/firmware/config.txt

echo "=== Step 3: Disable vc4-kms-v3d ==="
sudo sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/' /boot/firmware/config.txt

echo "=== Step 4: Set graphical boot target ==="
sudo systemctl set-default graphical.target

echo "=== Step 5: Override lightdm service ==="
sudo tee /etc/systemd/system/lightdm.service << 'UNIT'
[Unit]
Description=Light Display Manager
Documentation=man:lightdm(1)
After=systemd-user-sessions.service
Conflicts=plymouth-quit.service
After=plymouth-quit.service
OnFailure=plymouth-quit.service

[Service]
ExecStartPre=/bin/chmod 620 /dev/tty0
ExecStart=/usr/sbin/lightdm
Restart=always
BusName=org.freedesktop.DisplayManager

[Install]
Alias=display-manager.service
UNIT

echo "=== Step 6: Fix lightdm config ==="
sudo sed -i 's/^#logind-check-graphical=true/logind-check-graphical=false/' /etc/lightdm/lightdm.conf
sudo sed -i 's|#xserver-command=X|xserver-command=X -core|' /etc/lightdm/lightdm.conf

echo "=== Step 7: Fix xorg config ==="
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-fbdev.conf << 'XORG'
Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier "FB Device"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier "FB Screen"
    Device "FB Device"
EndSection
XORG

echo "=== Step 7b: Disable touchscreen input ==="
sudo tee /etc/X11/xorg.conf.d/99-disable-touch.conf << 'TOUCH'
Section "InputClass"
    Identifier "ADS7846 Touchscreen"
    MatchProduct "ADS7846 Touchscreen"
    Option "Ignore" "true"
EndSection
TOUCH

echo "=== Step 8: Mask glamor-test and rp1-test ==="
sudo systemctl disable glamor-test 2>/dev/null || true
sudo systemctl mask glamor-test
sudo systemctl disable rp1-test 2>/dev/null || true
sudo systemctl mask rp1-test
sudo rm -f /etc/X11/xorg.conf.d/99-v3d.conf

echo "=== Step 9: Disable SysV lightdm init script ==="
sudo rm -f /etc/init.d/lightdm
sudo rm -f /etc/rc2.d/S01lightdm
sudo rm -f /etc/rc3.d/S01lightdm
sudo rm -f /etc/rc4.d/S01lightdm
sudo rm -f /etc/rc5.d/S01lightdm

echo "=== Step 10: Fix polkit duplicate agents ==="
sudo tee /etc/xdg/autostart/lxpolkit.desktop > /dev/null << 'POLKIT'
[Desktop Entry]
Type=Application
Name=LXPolKit
Exec=lxpolkit
NotShowIn=GNOME;KDE;MATE;LXQt;XFCE;Unity;X-Cinnamon;rpd-wayland;rpd-x;
NoDisplay=true
Hidden=true
POLKIT

sudo tee /etc/xdg/autostart/polkit-mate-authentication-agent-1.desktop > /dev/null << 'POLKIT2'
[Desktop Entry]
Type=Application
Name=Polkit MATE Agent
Exec=/usr/libexec/polkit-mate-authentication-agent-1
NotShowIn=GNOME;KDE;MATE;LXQt;XFCE;Unity;X-Cinnamon;rpd-wayland;rpd-x;
NoDisplay=true
Hidden=true
POLKIT2

echo "=== Step 11: Build and install C fbcp service ==="
sudo apt install -y gcc

sudo tee /tmp/fbcp_src.c << 'FBCPCSRC'
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <time.h>
#include <sys/mman.h>

#define WIDTH 480
#define HEIGHT 320
#define FB0_SIZE (WIDTH * HEIGHT * 4)
#define FB1_SIZE (WIDTH * HEIGHT * 2)

int main() {
    int fb0 = open("/dev/fb0", O_RDONLY);
    int fb1 = open("/dev/fb1", O_RDWR);
    if (fb0 < 0 || fb1 < 0) { perror("open"); return 1; }

    uint8_t *src = mmap(NULL, FB0_SIZE, PROT_READ, MAP_SHARED, fb0, 0);
    uint16_t *dst = mmap(NULL, FB1_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fb1, 0);
    if (src == MAP_FAILED || dst == MAP_FAILED) { perror("mmap"); return 1; }

    struct timespec ts = {0, 33000000};

    while (1) {
        const uint8_t *s = src;
        uint16_t *d = dst;
        int n = WIDTH * HEIGHT;
        while (n--) {
            uint8_t b = *s++;
            uint8_t g = *s++;
            uint8_t r = *s++;
            s++;
            *d++ = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
        }
        nanosleep(&ts, NULL);
    }
    return 0;
}
FBCPCSRC

gcc -O3 -mcpu=cortex-a53 -o /tmp/fbcp_src.c /tmp/fbcp_src.c
sudo install /tmp/fbcp_src.c /usr/local/bin/fbcp-c

sudo tee /etc/systemd/system/fbcp.service << 'FBCPSVC'
[Unit]
Description=Framebuffer copy fb0 to SPI display fb1
After=multi-user.target

[Service]
ExecStart=/usr/local/bin/fbcp-c
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
FBCPSVC
sudo systemctl enable fbcp

echo "=== Step 12: Install fb-clear shutdown service ==="
sudo tee /usr/local/bin/fb-clear.py << 'FBCLEAR'
#!/usr/bin/env python3
FB1 = '/dev/fb1'
WIDTH = 480
HEIGHT = 320

with open(FB1, 'wb') as f1:
    f1.write(bytes(WIDTH * HEIGHT * 2))
FBCLEAR
sudo chmod +x /usr/local/bin/fb-clear.py

sudo tee /etc/systemd/system/fb-clear.service << 'FBCLEARSVC'
[Unit]
Description=Clear SPI framebuffer on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
RequiresMountsFor=/usr/local/bin

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/bin/fb-clear.py
RemainAfterExit=yes

[Install]
WantedBy=halt.target reboot.target shutdown.target
FBCLEARSVC
sudo systemctl enable fb-clear

echo "=== Step 13: Fix .bash_profile ==="
sudo chattr -i "/home/${TARGET_USER}/.bash_profile" 2>/dev/null || true
sudo chown "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/.bash_profile" 2>/dev/null || true
tee "/home/${TARGET_USER}/.bash_profile" << 'BASHPROFILE'
export FRAMEBUFFER=/dev/fb1

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
BASHPROFILE

echo "=== Step 14: Reload systemd and reboot ==="
sudo systemctl daemon-reload
sudo reboot
