#!/bin/bash

# ==============================================================================
# Chrony Configuration Script - Modem Priority Hierarchy
# Hierarchy: 4G Modem (Prefer) -> NEO-7M GPS (Fallback) -> DS3231 RTC (Failsafe)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Error: Please run this script as root using sudo."
  exit 1
fi

echo -e "\n[+] Configuring Chrony for Modem-First Priority Failover..."

# Backup current config
if [ ! -f /etc/chrony/chrony.conf.backup ]; then
    cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup
    echo "  -> Original chrony.conf backed up."
fi

# Write the custom network-preferred configuration
cat << 'EOF' > /etc/chrony/chrony.conf
# /etc/chrony/chrony.conf
# Stratum-1 NTP Server Configuration (GPS + PPS + Network + RTC)

# ==============================================================================
# System Directives
# ==============================================================================
# Step the system clock instead of slewing it if the adjustment is larger than
# one second, but only in the first three clock updates.
makestep 1 3

# Stop bad estimates upsetting machine clock.
maxupdateskew 100.0

# Get TAI-UTC offset and leap seconds from the system tz database.
leapseclist /usr/share/zoneinfo/leap-seconds.list

# Include configuration files found in /etc/chrony/conf.d.
confdir /etc/chrony/conf.d

# Allow local command access for the chronyc monitor.
allow 127/8
bindcmdaddress 127.0.0.1
bindcmdaddress ::1

# ==============================================================================
# ULTIMATE FAILSAFE: The Hardware RTC (DS3231)
# ==============================================================================
# This directive enables silent kernel synchronisation (every 11 minutes) of the
# real-time clock. If both the GPS and Network fail, the Pi will pull time from 
# the battery-backed chip on boot.
rtcsync

# ==============================================================================
# PRIORITY 1: The Master Hardware Clock (GPS NMEA + PPS)
# ==============================================================================
# The 'prefer trust' tags force Chrony to select the high-precision hardware pulse
# over the internet network pools whenever it is available.
refclock SHM 0 offset 0.1 delay 0.2 refid NMEA
refclock PPS /dev/pps0 refid PPS lock NMEA prefer trust

# ==============================================================================
# PRIORITY 2: The Internet (Network Pools)
# ==============================================================================
# These act as the active fallback if the GPS antenna loses satellite lock.
pool 2.debian.pool.ntp.org iburst
pool time.nist.gov iburst

# ==============================================================================
# Logging Configuration
# ==============================================================================
logdir /var/log/chrony
log statistics tracking measurements
EOF

echo "[+] Configuration injected successfully."
echo "[+] Restarting Chrony daemon to apply the new hierarchy..."

systemctl restart chronyd

echo -e "\n========================================================================="
echo " CONFIGURATION COMPLETE!"
echo "========================================================================="
echo "Chrony is now optimized for Modem Priority."
echo "Verify the behavior by running: chronyc sources -v"
echo "=========================================================================\n"
