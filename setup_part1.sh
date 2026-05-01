#!/bin/bash
set -e

echo "=== Part 1: Install LCD35 driver ==="
cd ~
git clone https://github.com/goodtft/LCD-show.git
cd LCD-show
sudo ./LCD35-show
