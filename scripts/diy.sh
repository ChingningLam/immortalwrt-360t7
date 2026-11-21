#!/bin/sh
# Build-time customisation applied inside the OpenWrt source tree.
# Runs after the build config is copied and before "make defconfig".
set -eu

# Default LAN management address.
sed -i 's/192\.168\.1\.1/192.168.5.1/g' package/base-files/files/bin/config_generate

# Sanity check: the replacement must have happened.
grep -q '192.168.5.1' package/base-files/files/bin/config_generate
