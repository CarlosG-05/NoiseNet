#!/bin/bash

# ==============================================================================
# NEO-7M Stratum-1 Setup & Automated Diagnostic Suite
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Error: Please run this script as root using sudo."
  exit 1
fi

# ------------------------------------------------------------------------------
# PHASE 1: HARDWARE WIRING GATEWAY
# ------------------------------------------------------------------------------
clear
echo -e "========================================================================="
echo -e " PHASE 1: HARDWARE INTEGRATION CHECK"
echo -e "========================================================================="
echo -e "[!] WARNING: Ensure the Raspberry Pi is POWERED OFF before wiring."
echo -e ""
echo -e " Please verify the following connections:"
echo -e ""
echo -e " NEO-7M Pin   |  Raspberry Pi 4 Pin      |  Function"
echo -e " -------------|--------------------------|-------------------------------"
echo -e " VCC          |  Pin 2 (5V)              |  5V Power"
echo -e " GND          |  Pin 6 (Ground)          |  Common Ground"
echo -e " TX           |  Pin 10 (GPIO 15 / RXD)  |  Serial NMEA Data"
echo -e " RX           |  Pin 8 (GPIO 14 / TXD)   |  (Optional) Config Data"
echo -e " PPS          |  Pin 12 (GPIO 18)        |  1Hz Hardware Pulse"
echo -e "=========================================================================\n"

# The Interactive Prompt Loop
while true; do
    read -p "Type 'next' when wired correctly to begin OS configuration (or 'exit' to quit): " USER_INPUT
    
    # Convert input to lowercase for easier matching
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

# ------------------------------------------------------------------------------
# PHASE 2: OS Preparation
# ------------------------------------------------------------------------------
echo "[+] Disabling default system time sync..."
systemctl stop systemd-timesyncd 2>/dev/null
systemctl disable systemd-timesyncd 2>/dev/null

echo "[+] Verifying Kernel Overlays (UART & PPS)..."
CONFIG="/boot/firmware/config.txt"
if [ ! -f "$CONFIG" ]; then
    CONFIG="/boot/config.txt"
fi

grep -qxF 'dtoverlay=pps-gpio,gpiopin=18' $CONFIG || echo 'dtoverlay=pps-gpio,gpiopin=18' >> $CONFIG
grep -qxF 'enable_uart=1' $CONFIG || echo 'enable_uart=1' >> $CONFIG
grep -qxF 'dtoverlay=disable-bt' $CONFIG || echo 'dtoverlay=disable-bt' >> $CONFIG

# ------------------------------------------------------------------------------
# PHASE 3: Software Configuration
# ------------------------------------------------------------------------------
echo "[+] Ensuring required packages are installed..."
apt update -y --quiet
apt install -y chrony gpsd gpsd-clients pps-tools --quiet

echo "[+] Configuring gpsd..."
cat <<EOF > /etc/default/gpsd
START_DAEMON="true"
USBAUTO="false"
DEVICES="/dev/serial0 /dev/pps0"
GPSD_OPTIONS="-n"
EOF

echo "[+] Configuring Chrony..."
CHRONY_CONF="/etc/chrony/chrony.conf"
grep -qxF 'refclock SHM 0 offset 0.1 delay 0.2 refid NMEA' $CHRONY_CONF || echo 'refclock SHM 0 offset 0.1 delay 0.2 refid NMEA' >> $CHRONY_CONF
grep -qxF 'refclock PPS /dev/pps0 refid PPS lock NMEA' $CHRONY_CONF || echo 'refclock PPS /dev/pps0 refid PPS lock NMEA' >> $CHRONY_CONF

systemctl restart gpsd chronyd

# ==============================================================================
# PHASE 4: AUTOMATED DIAGNOSTICS & ERROR HANDLING
# ==============================================================================
echo -e "\n========================================================================="
echo " RUNNING AUTOMATED HARDWARE DIAGNOSTICS"
echo "========================================================================="

# ERROR 2 CHECK: Verify Bluetooth disable and Serial Mapping
echo -n "[Check 1] Serial Port Mapping: "
if ls -l /dev/serial0 | grep -q "ttyAMA0"; then
    echo "PASS (/dev/serial0 -> ttyAMA0)"
else
    echo "FAIL"
    echo "  [!] DIAGNOSIS: /dev/serial0 is completely blank or pointing to the wrong hardware."
    echo "  [!] FIX: The Bluetooth overlay requires a reboot to take effect. If you have already rebooted, verify TX/RX wiring."
fi

# ERROR 3 CHECK: The Socket Trap / Resource Busy
echo -n "[Check 2] Port Access (Resource Busy Trap): "
if systemctl is-active --quiet gpsd.socket; then
    echo "LOCKED BY DAEMON"
    echo "  [!] DIAGNOSIS: gpsd.socket is actively holding the serial port."
    echo "  [!] AUTOMATED ACTION: Temporarily freeing port for raw data test..."
    
    systemctl stop gpsd.socket gpsd
    
    if timeout 2 cat /dev/serial0 | grep -q "GP"; then
        echo "  [+] SUCCESS: Raw NMEA data successfully read! Wires are crossed correctly."
    else
        echo "  [-] WARNING: Port freed, but no readable NMEA data found. Check Baud Rate or TX/RX pins."
    fi
    
    systemctl start gpsd.socket gpsd
else
    echo "FREE"
fi

# ERROR 1 & 4 CHECK: PPS Timeout and SNR Signal Drop
echo -n "[Check 3] PPS Electrical Interrupt: "
if timeout 3 ppstest /dev/pps0 2>&1 | grep -q "assert"; then
    echo "PASS (Pulse Detected)"
else
    echo "FAIL (Connection Timed Out)"
    echo "  [!] DIAGNOSIS: The Pi is listening, but the NEO-7M is not firing the electrical pulse."
    echo "  [!] FIX: Module lacks a 3D satellite lock. Move the antenna to an unobstructed sky view and wait for the LED to blink."
fi

echo -e "\n========================================================================="
echo " SETUP & DIAGNOSTICS COMPLETE."
echo " If any 'FAIL' states occurred due to kernel changes, reboot to resolve."
echo "========================================================================="