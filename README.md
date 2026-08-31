# Precision GPS Timing & Hardware System

## 🏗️ System Architecture
This system utilizes a tiered failover hierarchy managed by the `chronyd` daemon to ensure constant, high-precision system time, even in completely offline environments.

1. **Priority 1 (Network NTP):** Synchronizes via 4G Modem when the internet is available.
2. **Priority 2 (GPS / Stratum 1):** Falls back to the u-blox NEO-7M PPS hardware interrupt for nanosecond precision if the network drops.
3. **Priority 3 (RTC / Failsafe):** Drops to the DS3231 battery-backed I2C hardware clock if both network and satellite locks are lost.

*(Note: The system utilizes the kernel's `rtcsync` directive to automatically correct RTC drift using the GPS/NTP master clock every 11 minutes).*

---

## 🔌 Hardware Wiring Guide

**WARNING:** Ensure the Raspberry Pi is powered off before adjusting GPIO pins.

### u-blox NEO-7M (Secondary Master Clock)
| Module Pin | Raspberry Pi Pin | Function |
| :--- | :--- | :--- |
| VCC | Pin 2 (5V) | Power |
| GND | Pin 6 (Ground) | Common Ground |
| TX | Pin 10 (GPIO 15) | Serial NMEA Data (`/dev/serial0`) |
| RX | Pin 8 (GPIO 14) | Receive Config |
| PPS | Pin 12 (GPIO 18) | 1Hz Hardware Interrupt (`/dev/pps0`) |

### DS3231 RTC (Hardware Failsafe)
| Module Pin | Raspberry Pi Pin | Function |
| :--- | :--- | :--- |
| VCC | Pin 1 (3.3V) | I2C Logic Power |
| GND | Pin 9 (Ground) | Common Ground |
| SDA | Pin 3 (GPIO 2) | I2C Data Line |
| SCL | Pin 5 (GPIO 3) | I2C Clock Line |

---

## 📜 File Manifest & Deployment

The deployment process is fully automated via a single, unified bash script featuring built-in hardware diagnostic suites and sequential configuration. 

### Unified Deployment (`GPS_Timing_Setup.sh`)
This script handles the entire configuration pipeline in one pass:
* **Phase 1 (GPS):** Frees the high-performance hardware UART, binds the PPS GPIO overlay, installs `gpsd`, and verifies NEO-7M wiring.
* **Phase 2 (RTC):** Enables the ARM I2C bus, mounts the `ds3231` kernel overlay, and tests the hardware hex address (0x68).
* **Phase 3 (Chrony):** Injects the prioritized Stratum failover logic (Modem -> GPS -> RTC) into the `chrony` daemon.

### 📊 Automated Benchmarking & Utilities

* **Jitter Showdown (`jitter_logger.py`)**
    * Used for Test 2.1.
    * Automatically polls `chronyc sourcestats` over a 1-hour period.
    * Compares the electrical variance (Std Dev) of the modern NEO-7M against the older NEO-6M.
    * Exports results to a CSV file.
    * **Usage:** `nohup python3 jitter_logger.py &` (Runs safely in the background).

* **Single-Shot Coordinates (`get_gpscoords.py`)**
    * A command-line utility that safely taps into the `gpsd` socket.
    * Bypasses the daemon handshake.
    * Pulls a single highly-accurate TPV (Time-Position-Velocity) coordinate and exits.
    * **Usage:** `python3 get_gpscoords.py`
    * **Dependencies:** `sudo apt install python3-gps`

---

### 🛠️ Common Diagnostics

If you experience timing or lock issues, run the following verification commands:

* **Check Satellite Lock:** `gpsmon` (Requires 3D Fix and SNR > 30)
* **Check PPS Electrical Pulse:** `sudo ppstest /dev/pps0`
* **Check Chrony Scoreboard:** `chronyc sources -v`
* **Check RTC Hex Address:** `sudo i2cdetect -y 1`
* **Stamp GPS Time to RTC:** `sudo hwclock -w`

---

### 🐙 Version Control (GitHub Deployment)

To safely package this suite and push it to a GitHub repository without including background logs or large ECE benchmark CSV files:

#### 1. Configure Git Ignore
Create a `.gitignore` file in your project directory:

```plaintext
# Python caches
__pycache__/
*.py[cod]

# Background process logs
nohup.out
*.log

# Data exports
*.csv
*.dat

# OS generated files
.DS_Store
```

#### 2. Initialize and Commit
Initialize the local repository and commit the scripts:

```bash
git init
git add .
git commit -m "Initial commit: Stratum-1 Time Server deployment and benchmark scripts"
git branch -M main
```

#### 3. Push to Remote Repository
Link to your empty GitHub repository and push the code:

```bash
git remote add origin https://github.com/YourUsername/your-repo-name.git
git push -u origin main
```
