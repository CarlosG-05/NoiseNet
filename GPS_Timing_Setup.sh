#!/bin/bash
# ==============================================================================
# Combined Setup: NEO-7M -> DS3231 RTC -> Chrony Modem Priority
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Error: Please run this script as root using sudo."
  exit 1
fi

# ==============================================================================
# PHASE 1: NEO-7M Stratum-1 Setup
# ==============================================================================
clear
echo -e "========================================================================="
echo -e " PHASE 1: NEO-7M HARDWARE INTEGRATION CHECK"
echo -e "========================================================================="
echo -e "[!] WARNING: Ensure the Raspberry Pi is POWERED OFF before wiring."
echo -e ""
echo -e " NEO-7M Pin   |  Raspberry Pi 4 Pin      |  Function"
echo -e " -------------|--------------------------|-------------------------------"
echo -e " VCC          |  Pin 2 (5V)              |  5V Power"
echo -e " GND          |  Pin 6 (Ground)          |  Common Ground"
echo -e " TX           |  Pin 10 (GPIO 15 / RXD)  |  Serial NMEA Data"
echo -e " RX           |  Pin 8 (GPIO 14 / TXD)   |  (Optional) Config Data"
echo -e " PPS          |  Pin 12 (GPIO 18)        |  1Hz Hardware Pulse"
echo -e "=========================================================================\n"

while true; do
    read -p "Type 'next' when wired correctly to begin NEO-7M configuration: " USER_INPUT
    USER_INPUT=${USER_INPUT,,}
    if [[ "$USER_INPUT" == "next" ]]; then
        echo -e "\n[+] Hardware confirmed. Proceeding with OS configuration...\n"
        break
    fi
done

echo "[+] Disabling default system time sync..."
systemctl stop systemd-timesyncd 2>/dev/null
systemctl disable systemd-timesyncd 2>/dev/null

echo "[+] Stripping Login Consoles from Hardware UART..."
raspi-config nonint do_serial_cons 1
systemctl stop serial-getty@ttyS0.service 2>/dev/null
systemctl disable serial-getty@ttyS0.service 2>/dev/null

echo "[+] Gagging Kernel Boot Spammer (cmdline.txt)..."
CMDLINE="/boot/firmware/cmdline.txt"
if [ ! -f "$CMDLINE" ]; then CMDLINE="/boot/cmdline.txt"; fi
sed -i 's/console=serial0,115200 //g' $CMDLINE

echo "[+] Injecting Kernel Overlays (UART & PPS)..."
CONFIG="/boot/firmware/config.txt"
if [ ! -f "$CONFIG" ]; then CONFIG="/boot/config.txt"; fi
grep -qxF 'dtoverlay=pps-gpio,gpiopin=18' $CONFIG || echo 'dtoverlay=pps-gpio,gpiopin=18' >> $CONFIG
grep -qxF 'enable_uart=1' $CONFIG || echo 'enable_uart=1' >> $CONFIG
grep -qxF 'dtoverlay=disable-bt' $CONFIG || echo 'dtoverlay=disable-bt' >> $CONFIG

echo "[+] Installing Required Timing Packages..."
apt update -y --quiet
apt install -y chrony gpsd gpsd-clients pps-tools --quiet

echo "[+] Configuring gpsd (Anti-Autobaud & Read-Only Mode)..."
cat <<EOF > /etc/default/gpsd
START_DAEMON="true"
USBAUTO="false"
DEVICES="/dev/serial0 /dev/pps0"
GPSD_OPTIONS="-n -b -s 9600"
EOF

# ==============================================================================
# PHASE 2: DS3231 I2C RTC Setup
# ==============================================================================
echo -e "\n========================================================================="
echo -e " PHASE 2: RTC HARDWARE INTEGRATION CHECK"
echo -e "========================================================================="
echo -e " Please verify the following I2C connections for the RTC:"
echo -e ""
echo -e " RTC Module Pin |  Raspberry Pi 4 Pin      |  Function"
echo -e " ---------------|--------------------------|-------------------------------"
echo -e " VCC            |  Pin 1 (3.3V)            |  3.3V Logic Power"
echo -e " GND            |  Pin 9 (Ground)          |  Common Ground"
echo -e " SDA            |  Pin 3 (GPIO 2)          |  I2C Data Line"
echo -e " SCL            |  Pin 5 (GPIO 3)          |  I2C Clock Line"
echo -e "=========================================================================\n"

while true; do
    read -p "Type 'next' when wired correctly to begin RTC configuration (or 'exit' to quit): " USER_INPUT
    USER_INPUT=${USER_INPUT,,}
    if [[ "$USER_INPUT" == "next" ]]; then
        echo -e "\n[+] Hardware confirmed. Proceeding with OS configuration...\n"
        break
    elif [[ "$USER_INPUT" == "exit" ]]; then
        echo "Exiting script. Power down the Pi to adjust wiring safely."
        exit 0
    else
        echo "[!] Invalid input."
    fi
done

echo "[+] Enabling ARM I2C Interface..."
raspi-config nonint do_i2c 0

echo "[+] Installing required packages (i2c-tools, util-linux-extra)..."
apt install -y i2c-tools util-linux-extra --quiet

echo "[+] Verifying Kernel Overlays (I2C-RTC)..."
grep -qxF 'dtoverlay=i2c-rtc,ds3231' $CONFIG || echo 'dtoverlay=i2c-rtc,ds3231' >> $CONFIG

echo -e "\n========================================================================="
echo " RUNNING I2C HARDWARE DIAGNOSTICS"
echo "========================================================================="
echo -n "[Check 1] hwclock Utility Installation: "
if command -v hwclock >/dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    echo "  [!] DIAGNOSIS: hwclock command not found."
    echo "  [!] FIX: apt failed to install util-linux-extra. Check internet connection."
fi

echo -n "[Check 2] I2C Physical Wiring (Hex 68): "
if i2cdetect -y 1 | grep -q "68"; then
    echo "PASS (Hardware Detected)"
else
    echo "FAIL"
    echo "  [!] DIAGNOSIS: The Pi cannot see the RTC module on the I2C bus."
    echo "  [!] FIX: Verify SDA (Pin 3) and SCL (Pin 5) wiring. Ensure module has 3.3V power, not 5V."
fi

# ==============================================================================
# PHASE 3: Chrony Configuration (Modem Priority -> GPS -> RTC)
# ==============================================================================
echo -e "\n[+] Configuring Chrony for Modem-First Priority Failover..."

if [ ! -f /etc/chrony/chrony.conf.backup ]; then
    cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup
    echo "  -> Original chrony.conf backed up."
fi

cat << 'EOF' > /etc/chrony/chrony.conf
# /etc/chrony/chrony.conf
# Stratum-1 NTP Server Configuration (GPS + PPS + Network + RTC)

makestep 1 3
maxupdateskew 100.0
leapseclist /usr/share/zoneinfo/leap-seconds.list
confdir /etc/chrony/conf.d
allow 127/8
bindcmdaddress 127.0.0.1
bindcmdaddress ::1

# RTC Failsafe
rtcsync

# Master Hardware Clock (GPS NMEA + PPS)
refclock SHM 0 offset 0.1 delay 0.2 refid NMEA
refclock PPS /dev/pps0 refid PPS lock NMEA prefer trust

# Network Pools (Fallback)
pool 2.debian.pool.ntp.org iburst
pool time.nist.gov iburst

# Logging
logdir /var/log/chrony
log statistics tracking measurements
EOF

echo "[+] Configuration injected successfully."
echo "[+] Restarting Chrony daemon to apply the new hierarchy..."
systemctl restart chronyd

# ==============================================================================
# FINALE & REBOOT
# ==============================================================================
echo -e "\n========================================================================="
echo " SETUP COMPLETE. KERNEL MODIFICATIONS REQUIRE A REBOOT."
echo "========================================================================="
echo "Chrony is now optimized for Modem Priority."
echo "After rebooting, perform the following verifications:"
echo "  1. Wait 3 minutes and check 'cgps -s' for your 3D Fix."
echo "  2. Run 'sudo hwclock -w' to stamp the GPS system time onto the RTC."
echo "  3. Verify Chrony behavior by running: chronyc sources -v"
echo -e "=========================================================================\n"

read -p "Would you like to reboot now? (y/n): " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" == "y" || "$REBOOT_CHOICE" == "Y" ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please remember to reboot manually later to apply the overlays."
fi
