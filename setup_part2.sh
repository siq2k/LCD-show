#!/bin/bash
set -e

echo "=== Step 1: Fix display rotation ==="
sudo sed -i 's/dtoverlay=tft35a:rotate=90/dtoverlay=tft35a:rotate=270/' /boot/firmware/config.txt

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
    Option "AutoAddDevices" "false"
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

echo "=== Step 11: Install fbcp service ==="
sudo apt install -y python3-numpy

sudo tee /usr/local/bin/fbcp.py << 'FBCP'
#!/usr/bin/env python3
import time
import numpy as np

FB0 = '/dev/fb0'
FB1 = '/dev/fb1'
WIDTH = 480
HEIGHT = 320

with open(FB0, 'rb') as f0, open(FB1, 'wb') as f1:
    while True:
        try:
            f0.seek(0)
            data = np.frombuffer(f0.read(WIDTH * HEIGHT * 4), dtype=np.uint8).reshape((WIDTH * HEIGHT, 4))
            r = data[:, 2].astype(np.uint16)
            g = data[:, 1].astype(np.uint16)
            b = data[:, 0].astype(np.uint16)
            rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            f1.seek(0)
            f1.write(rgb565.astype(np.uint16).tobytes())
            f1.flush()
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(1)
        time.sleep(0.033)
FBCP
sudo chmod +x /usr/local/bin/fbcp.py

sudo tee /etc/systemd/system/fbcp.service << 'FBCPSVC'
[Unit]
Description=Framebuffer copy fb0 to SPI display fb1
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/fbcp.py
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
sudo chattr -i /home/naz/.bash_profile 2>/dev/null || true
sudo chown naz:naz /home/naz/.bash_profile 2>/dev/null || true
tee /home/naz/.bash_profile << 'BASHPROFILE'
export FRAMEBUFFER=/dev/fb1

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
BASHPROFILE

echo "=== Step 14: Reload systemd and reboot ==="
sudo systemctl daemon-reload
sudo reboot
