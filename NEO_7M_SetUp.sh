#!/bin/bash
# ==============================================================================
# NEO-7M Stratum-1 Setup & Automated Diagnostic Suite (v2.0)
# Includes Kernel UART Bypasses and u-blox Autobaud Fixes
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Error: Please run this script as root using sudo."
  exit 1
fi

clear
echo -e "========================================================================="
echo -e " PHASE 1: HARDWARE INTEGRATION CHECK"
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
    read -p "Type 'next' when wired correctly to begin OS configuration: " USER_INPUT
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

echo "[+] Configuring Chrony Shared Memory Hooks..."
CHRONY_CONF="/etc/chrony/chrony.conf"
grep -qxF 'refclock SHM 0 offset 0.1 delay 0.2 refid NMEA' $CHRONY_CONF || echo 'refclock SHM 0 offset 0.1 delay 0.2 refid NMEA' >> $CHRONY_CONF
grep -qxF 'refclock PPS /dev/pps0 refid PPS lock NMEA' $CHRONY_CONF || echo 'refclock PPS /dev/pps0 refid PPS lock NMEA' >> $CHRONY_CONF

echo -e "\n========================================================================="
echo " SETUP COMPLETE. KERNEL MODIFICATIONS REQUIRE A REBOOT."
echo "========================================================================="
echo "Run 'sudo reboot' to apply."
echo "After rebooting, wait 3 minutes and check 'cgps -s' for your 3D Fix."
echo "========================================================================="
