#!/bin/bash
# ==============================================================================
# Stratum-1 Timing System: Automated Test Suite (v2)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Error: Please run this script as root using sudo."
  exit 1
fi

function show_menu() {
    clear
    echo "========================================================================="
    echo " ⏱️  GPS & RTC FAILOVER TEST SUITE"
    echo "========================================================================="
    echo " 1) Phase 1 & 2: Time Travel & GPS Recovery Test (Auto-Wait)"
    echo " 2) Phase 3: Kernel 11-Minute RTC Sync Logger"
    echo " 3) Phase 4: Ultimate Failsafe (Offline Boot) Instructions"
    echo " 4) Exit"
    echo "========================================================================="
    read -p "Select a test to run (1-4): " choice
    echo ""
}

function test_time_travel() {
    echo "[+] Disabling Wi-Fi to ensure a strictly offline environment..."
    rfkill block wifi 2>/dev/null || ip link set wlan0 down 2>/dev/null

    echo "[+] Stopping Chrony daemon..."
    systemctl stop chronyd

    echo "[+] Shifting system date AND time (14 days and 6 hours ago)..."
    date -s "14 days ago 6 hours ago"

    echo "[+] Wiping RTC memory (Setting to Jan 1, 2000, 12:30:00)..."
    hwclock --set --date="2000-01-01 12:30:00"

    echo ""
    echo "[!] ENVIRONMENT PREPARED. NO INTERNET. BAD TIME."
    echo "System Time is now: $(date)"
    echo "RTC Time is now:    $(hwclock -r)"
    echo ""
    read -p "Press [Enter] when GPS is connected and has a clear view of the sky..."

    echo "[+] Starting Chrony..."
    systemctl start chronyd
    
    echo "[+] Waiting for Chrony to select PPS..."
    echo "    (Polling every 5 seconds. This will wait until a 3D Fix is established)"
    
    # Loop continuously until Chrony marks the PPS source with a '*'
    while true; do
        # Aggressively tell Chrony to snap the time once the source becomes available
        chronyc makestep >/dev/null 2>&1
        
        # Check if a line starting with '*' and containing 'PPS' exists
        if chronyc sources | grep -q '^\*.*PPS'; then
            echo -e "\n\n[+] SUCCESS: PPS Lock Acquired!"
            break
        fi
        
        # Print a dot to indicate it is still searching
        echo -n "."
        sleep 5
    done
    
    echo -e "\n[+] Current Chrony Sources:"
    chronyc sources -v
    
    echo -e "\n[+] Verification:"
    echo "Corrected System Time: $(date)"
    
    echo -e "\n[+] Re-enabling Wi-Fi..."
    rfkill unblock wifi 2>/dev/null || ip link set wlan0 up 2>/dev/null
    
    echo -e "\n(Press Enter to return to menu)"
    read
}

function test_rtc_sync_logger() {
    echo "[+] Sabotaging RTC Time (Setting to May 5, 2010, 08:15:00)..."
    hwclock --set --date="2010-05-05 08:15:00"
    
    echo "[+] RTC Sabotaged. Initial Read: $(hwclock -r)"
    echo "[+] Starting Live Logger. Watch for the date to snap to the present."
    echo "[!] Press [Ctrl+C] to stop the logger and exit."
    echo "-------------------------------------------------------------------------"
    
    while true; do 
        echo "[$(date '+%H:%M:%S')] System: $(date '+%b %d %Y') | RTC Time: $(hwclock -r)"
        sleep 10
    done
}

function test_offline_boot() {
    echo "========================================================================="
    echo " ULTIMATE FAILSAFE TEST INSTRUCTIONS"
    echo "========================================================================="
    echo "This test requires physical intervention and cannot be fully scripted."
    echo ""
    echo "1. Type 'sudo poweroff' to safely shut down."
    echo "2. Unplug the Pi's power cable."
    echo "3. Disconnect your internet (Ethernet/Wi-Fi)."
    echo "4. Disconnect the GPS antenna or NEO-7M module."
    echo "5. Wait a few minutes."
    echo "6. Plug the Pi's power back in and boot up."
    echo "7. Run 'date' to verify the Pi pulled the correct time from the RTC."
    echo "========================================================================="
    echo -e "\n(Press Enter to return to menu)"
    read
}

# Main Loop
while true; do
    show_menu
    case $choice in
        1) test_time_travel ;;
        2) test_rtc_sync_logger ;;
        3) test_offline_boot ;;
        4) echo "Exiting suite."; exit 0 ;;
        *) echo "[!] Invalid option. Press Enter to try again."; read ;;
    esac
done
