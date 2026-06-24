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
# ------------------------------------------------------------------------------
# PRIORITY 1: Network / 4G Modem (The Primary Master)
# ------------------------------------------------------------------------------
# The 'prefer trust' tags force Chrony to select these sources over the GPS
# as long as an internet connection is actively detected.
pool 2.debian.pool.ntp.org iburst prefer trust
pool time.nist.gov iburst prefer trust

# ------------------------------------------------------------------------------
# PRIORITY 2: Hardware Backup (NEO-7M GPS)
# ------------------------------------------------------------------------------
# The 'prefer' tag is removed here so it acts strictly as an offline fallback.
refclock SHM 0 offset 0.1 delay 0.2 refid NMEA
refclock PPS /dev/pps0 refid PPS lock NMEA

# ------------------------------------------------------------------------------
# PRIORITY 3: Hardware Failsafe (DS3231 RTC)
# ------------------------------------------------------------------------------
# Stratum 10 ensures this is only claimed if both Modem and GPS are offline.
refclock RTC /dev/rtc0 stratum 10 refid RTC

# ------------------------------------------------------------------------------
# System Directives
# ------------------------------------------------------------------------------
makestep 1 -1
driftfile /var/lib/chrony/chrony.drift

rtcsync

allow 127/8
bindcmdaddress 127.0.0.1
bindcmdaddress ::1

logdir /var/log/chrony
log statistics sourcestats tracking
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