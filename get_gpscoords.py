import sys

# ---------------------------------------------------------
# Library Error Handling
# ---------------------------------------------------------
try:
    import gps
except ImportError:
    print("\n[!] ERROR: Missing Required Library")
    print("The 'gps' Python module is not installed on this system.")
    print("Please install it by running the following command:")
    print("    sudo apt install python3-gps\n")
    sys.exit(1)

# ---------------------------------------------------------
# Main Execution
# ---------------------------------------------------------
def get_single_coordinate():
    try:
        # Connect to the local gpsd socket on port 2947
        session = gps.gps("localhost", "2947")
        session.stream(gps.WATCH_ENABLE | gps.WATCH_NEWSTYLE)
        
        # Read the incoming data stream
        for report in session:
            # Look specifically for the Time-Position-Velocity packet
            if report['class'] == 'TPV':
                lat = getattr(report, 'lat', None)
                lon = getattr(report, 'lon', None)
                alt = getattr(report, 'alt', "N/A")
                
                # Verify we actually have a satellite lock with valid numbers
                if lat is not None and lon is not None:
                    print(f"Lat: {lat} | Lon: {lon} | Alt: {alt}m")
                    
                    # We got our single reading, so we break and exit instantly
                    break 

    except StopIteration:
        print("Error: GPSD stream terminated unexpectedly.")
    except Exception as e:
        print(f"Error connecting to gpsd: {e}")
        sys.exit(1)

if __name__ == '__main__':
    get_single_coordinate()