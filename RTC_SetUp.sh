#!/bin/bash

# ==============================================================================
# DS3231 I2C RTC Setup & Automated Diagnostic Suite
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
# PHASE 2: OS Preparation & I2C Enable
# ------------------------------------------------------------------------------
echo "[+] Enabling ARM I2C Interface..."
raspi-config nonint do_i2c 0

echo "[+] Installing required packages (i2c-tools, util-linux-extra)..."
apt update -y --quiet
apt install -y i2c-tools util-linux-extra --quiet

# ------------------------------------------------------------------------------
# PHASE 3: Kernel Configuration
# ------------------------------------------------------------------------------
echo "[+] Verifying Kernel Overlays (I2C-RTC)..."
CONFIG="/boot/firmware/config.txt"
if [ ! -f "$CONFIG" ]; then
    CONFIG="/boot/config.txt"
fi

grep -qxF 'dtoverlay=i2c-rtc,ds3231' $CONFIG || echo 'dtoverlay=i2c-rtc,ds3231' >> $CONFIG

# ==============================================================================
# PHASE 4: AUTOMATED DIAGNOSTICS & ERROR HANDLING
# ==============================================================================
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

echo -e "\n========================================================================="
echo " SETUP COMPLETE! A reboot is required to claim the I2C device."
echo "========================================================================="
echo "After rebooting, run these two commands to finalize synchronization:"
echo "  1. sudo hwclock -r    (To confirm read access)"
echo "  2. sudo hwclock -w    (To stamp the GPS system time onto the RTC)"
echo -e "=========================================================================\n"

read -p "Would you like to reboot now? (y/n): " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" == "y" || "$REBOOT_CHOICE" == "Y" ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Please remember to reboot manually later to apply the RTC overlay."
fi