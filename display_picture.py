#!/usr/bin/python3
import sys
import os
import glob
import random
import time
import argparse
import smbus
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------
# Setup paths
# --------------------------------------------------

os.chdir(os.path.dirname(os.path.abspath(__file__)))

libdir = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                      'RPi_Zero_PhotoPainter/7in3_e-Paper_E/python/lib')

if os.path.exists(libdir):
    sys.path.append(libdir)

from waveshare_epd import epd7in3e

# --------------------------------------------------
# Configuration
# --------------------------------------------------

STATE_FILE   = "/home/pi/photo_state.txt"
BATTERY_LOG  = "/home/pi/battery_log.csv"
IMAGE_FOLDER = "/home/pi/my_photos"

LOW_BATTERY_THRESHOLD    = 20    # percent — show warning overlay below this
CRITICAL_BATTERY_VOLTAGE = 3.45  # volts — skip display and shut down below this

WITTYPI_I2C_ADDR = 0x08

# WittyPi 4 register addresses
REG_VIN_INT  = 0x01  # Vin integer part
REG_VIN_DEC  = 0x02  # Vin decimal part (x100)
REG_VOUT_INT = 0x03  # Vout integer part
REG_VOUT_DEC = 0x04  # Vout decimal part (x100)
REG_IOUT_INT = 0x05  # Iout integer part
REG_IOUT_DEC = 0x06  # Iout decimal part (x100)

# --------------------------------------------------
# Utility
# --------------------------------------------------

def fatal(msg):
    print("FATAL:", msg)
    sys.exit(1)


def get_log_index():
    """Read the last index from the battery log and return next index.
    Returns 1 if log doesn't exist or is empty.
    """
    if not os.path.exists(BATTERY_LOG):
        return 1
    try:
        with open(BATTERY_LOG, 'r') as f:
            lines = [l.strip() for l in f if l.strip()]
        for line in reversed(lines):
            if line.startswith('time'):
                continue
            parts = line.split(',')
            if len(parts) >= 2:
                return int(parts[1]) + 1
    except Exception:
        pass
    return 1


def log_battery(vin, battery_pct, vout, iout, awake_sec, read_ok):
    try:
        log_index = get_log_index()
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%S")

        if not os.path.exists(BATTERY_LOG):
            with open(BATTERY_LOG, "w") as f:
                f.write("time,index,vin_V,battery_pct,vout_V,iout_A,awake_sec,read_ok\n")

        with open(BATTERY_LOG, "a") as f:
            f.write(
                f"{timestamp},"
                f"{log_index},"
                f"{vin  if vin  is not None else ''},"
                f"{battery_pct:.1f},"
                f"{vout if vout is not None else ''},"
                f"{iout if iout is not None else ''},"
                f"{awake_sec:.1f},"
                f"{read_ok}\n"
            )
    except Exception as e:
        print(f"Battery logging failed: {e}")

# --------------------------------------------------
# WittyPi Readings (Vin, Vout, Iout)
# --------------------------------------------------

def read_wittypi_readings():
    """Read Vin, Vout, and Iout from WittyPi 4 over I2C.
    Returns (vin, vout, iout) as floats, or None for any failed read.
    """
    try:
        bus = smbus.SMBus(1)

        vin  = bus.read_byte_data(WITTYPI_I2C_ADDR, REG_VIN_INT)  + bus.read_byte_data(WITTYPI_I2C_ADDR, REG_VIN_DEC)  / 100.0
        vout = bus.read_byte_data(WITTYPI_I2C_ADDR, REG_VOUT_INT) + bus.read_byte_data(WITTYPI_I2C_ADDR, REG_VOUT_DEC) / 100.0
        iout = bus.read_byte_data(WITTYPI_I2C_ADDR, REG_IOUT_INT) + bus.read_byte_data(WITTYPI_I2C_ADDR, REG_IOUT_DEC) / 100.0

        vin  = vin  if 2.5  <= vin  <= 5.0 else None
        vout = vout if 3.0  <= vout <= 6.0 else None
        iout = iout if 0.0  <= iout <= 3.0 else None

        return vin, vout, iout

    except Exception as e:
        print(f"WittyPi read error: {e}")
        return None, None, None


def voltage_to_percent(voltage):
    """Convert Li-ion battery voltage to approximate charge percentage.
    Calibrated against a real 4400mAh discharge run on this specific battery.
    Segments are derived from actual voltage percentile data, not generic curves.
    Empty (0%) is defined as 3.45V — below this the display stops updating,
    so the battery is considered dead for practical purposes.
    Full (100%) is defined as 4.20V (standard Li-ion charge ceiling).
    """
    if voltage is None:
        return -1

    if voltage >= 4.20:
        return 100
    if voltage <= 3.45:
        return 0

    # Piecewise linear segments calibrated from real discharge data
    # 0% anchored at 3.45V (critical shutdown threshold)
    # (v_low, v_high, pct_low, pct_high)
    segments = [
        (3.95, 4.20,  78, 100),  # top section
        (3.75, 3.95,  52,  78),  # upper middle
        (3.60, 3.75,  31,  52),  # middle plateau
        (3.45, 3.60,   0,  31),  # lower section — 0% at 3.45V
    ]

    for v_lo, v_hi, p_lo, p_hi in segments:
        if v_lo <= voltage <= v_hi:
            t = (voltage - v_lo) / (v_hi - v_lo)
            return round(p_lo + t * (p_hi - p_lo), 1)

    return -1

# --------------------------------------------------
# Parse Arguments
# --------------------------------------------------

parser = argparse.ArgumentParser(description='Display images on e-Paper display')
parser.add_argument('image', nargs='?', default=None,
                    help='Optional specific image to display')
args = parser.parse_args()

# --------------------------------------------------
# 1. Read WittyPi (average samples)
# --------------------------------------------------

AWAKE_START_TIME = time.time()

vin_samples  = []
vout_samples = []
iout_samples = []

time.sleep(2)  # let current settle after boot

for _ in range(5):
    vin, vout, iout = read_wittypi_readings()
    if vin  is not None: vin_samples.append(vin)
    if vout is not None: vout_samples.append(vout)
    if iout is not None: iout_samples.append(iout)
    time.sleep(0.2)

vin         = sum(vin_samples)  / len(vin_samples)  if vin_samples  else None
vout        = sum(vout_samples) / len(vout_samples) if vout_samples else None
iout        = sum(iout_samples) / len(iout_samples) if iout_samples else None
battery_pct = voltage_to_percent(vin)
read_ok     = vin is not None

print(f"Vin:  {vin:.3f} V  ({battery_pct:.1f}%)" if vin  else "Vin: read failed")
print(f"Vout: {vout:.3f} V"                       if vout else "Vout: read failed")
print(f"Iout: {iout:.3f} A"                       if iout else "Iout: read failed")

# --------------------------------------------------
# 2. Early exit if battery critically low
# --------------------------------------------------

if vin is not None and vin < CRITICAL_BATTERY_VOLTAGE:
    print(f"Battery critically low ({vin:.3f}V < {CRITICAL_BATTERY_VOLTAGE}V), skipping display.")
    log_battery(vin, battery_pct, vout, iout, time.time() - AWAKE_START_TIME, read_ok)
    sys.exit(0)

# --------------------------------------------------
# 3. Select Image
# --------------------------------------------------

if args.image:
    selected_image_path = args.image
    if not os.path.isabs(selected_image_path):
        selected_image_path = os.path.join(IMAGE_FOLDER, selected_image_path)

    if not os.path.exists(selected_image_path):
        fatal(f"Image not found: {selected_image_path}")

    update_state = False

else:
    images = glob.glob(os.path.join(IMAGE_FOLDER, "*.bmp"))
    if not images:
        fatal("No BMP images found")

    shown_images = set()

    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            shown_images = set(line.strip() for line in f)

    remaining_images = [img for img in images if img not in shown_images]

    if not remaining_images:
        print("All images shown. Starting new cycle.")
        remaining_images = images
        shown_images = set()

    selected_image_path = random.choice(remaining_images)
    update_state = True

print(f"{time.ctime()} - Displaying {os.path.basename(selected_image_path)}")

# --------------------------------------------------
# 4. Prepare Image
# --------------------------------------------------

epd = epd7in3e.EPD()
epd.init()

image = Image.open(selected_image_path)

# Draw battery warning if below threshold
if 0 <= battery_pct < LOW_BATTERY_THRESHOLD:
    img_width, img_height = image.size
    draw = ImageDraw.Draw(image)

    draw.rectangle([10, img_height - 40, 200, img_height - 10],
                   fill="white", outline="black", width=2)

    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
    except Exception:
        font = ImageFont.load_default()

    warning_text = f"LOW BATTERY: {int(battery_pct)}%"
    draw.text((20, img_height - 30), warning_text, fill="black", font=font)

# --------------------------------------------------
# 5. Display Image
# --------------------------------------------------

epd.display(epd.getbuffer(image))

# --------------------------------------------------
# 6. Sleep Display
# --------------------------------------------------

epd.sleep()

# --------------------------------------------------
# 7. Log Battery Data
# --------------------------------------------------

log_battery(vin, battery_pct, vout, iout, time.time() - AWAKE_START_TIME, read_ok)

# --------------------------------------------------
# 8. Update State
# --------------------------------------------------

if update_state:
    shown_images.add(selected_image_path)
    with open(STATE_FILE, 'w') as f:
        for img in shown_images:
            f.write(img + '\n')

print("Done.")
