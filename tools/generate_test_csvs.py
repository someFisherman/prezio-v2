"""Generate realistic test CSV files that pass the Prezio validation.

Creates 3 files in pi_recorder/data/:
  - messung_8h_wasser.csv   (8h water test, PN25, ~37.5 bar)
  - messung_24h_wasser.csv  (24h water test, PN25, ~37.5 bar)
  - messung_15h48_luft.csv  (15h48min air test, PN25, ~27.5 bar)

All curves simulate a realistic pressure test:
  1. Quick ramp-up phase (~5 min)
  2. Long stable plateau with tiny natural drift
  3. Pressure stays well above required threshold
  4. Pressure drop within allowed limits
"""

import csv
import math
import random
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "pi_recorder" / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

random.seed(42)


def generate_csv(
    filename: str,
    name: str,
    pn: int,
    medium: str,
    duration_hours: float,
    target_pressure: float,
    interval_s: int = 60,
    base_temp: float = 22.0,
):
    start = datetime(2026, 3, 14, 8, 0, 0)
    start_utc = start - timedelta(hours=1)  # CET -> UTC

    total_seconds = int(duration_hours * 3600)
    num_samples = total_seconds // interval_s

    # Ramp-up: ~5 minutes from 0 to target
    ramp_samples = min(30, num_samples // 10)

    rows = []
    for i in range(num_samples):
        t = i * interval_s
        local_dt = start + timedelta(seconds=t)
        utc_dt = start_utc + timedelta(seconds=t)

        # Pressure curve
        if i < ramp_samples:
            frac = i / ramp_samples
            p = target_pressure * (frac ** 0.5)
        else:
            elapsed_plateau = (i - ramp_samples) * interval_s
            total_plateau = (num_samples - ramp_samples) * interval_s
            # Slow linear drift down (~0.05 bar over entire duration)
            drift = -0.05 * (elapsed_plateau / total_plateau)
            # Tiny random noise
            noise = random.gauss(0, 0.005)
            # Very slight sinusoidal variation (temperature effect)
            temp_effect = 0.01 * math.sin(2 * math.pi * elapsed_plateau / 3600)
            p = target_pressure + drift + noise + temp_effect

        # Temperature curve: slight daily variation
        hour_of_day = (8 + t / 3600) % 24
        temp_variation = 1.5 * math.sin(2 * math.pi * (hour_of_day - 6) / 24)
        temp = base_temp + temp_variation + random.gauss(0, 0.05)

        p_rounded = round(p, 2)
        temp_rounded = round(temp, 2)

        rows.append({
            "no": i + 1,
            "local_dt": local_dt,
            "utc_dt": utc_dt,
            "p": p,
            "temp": temp,
            "p_rounded": p_rounded,
            "temp_rounded": temp_rounded,
        })

    stopped = start + timedelta(seconds=total_seconds)

    filepath = DATA_DIR / filename
    with open(filepath, "w", newline="", encoding="utf-8") as f:
        f.write(f"# Name: {name}\n")
        f.write(f"# PN: {pn}\n")
        f.write(f"# Medium: {medium}\n")
        f.write(f"# Interval: {interval_s}\n")
        f.write(f"# Started: {start.isoformat()}\n")
        f.write(f"# Stopped: {stopped.isoformat()}\n")
        f.write(f"# Samples: {len(rows)}\n")
        f.write(f"# SerialNumber: 12345678\n")

        writer = csv.writer(f)
        writer.writerow([
            "No",
            "Datetime [local time]",
            "Datetime [UTC]",
            "P1 [bar]",
            "TOB1 [C]",
            "P1 rounded [bar]",
            "TOB1 rounded [C]",
        ])
        for r in rows:
            writer.writerow([
                r["no"],
                r["local_dt"].strftime("%d.%m.%Y %H:%M:%S"),
                r["utc_dt"].isoformat().replace("+00:00", "Z"),
                f"{r['p']:.9f}",
                f"{r['temp']:.8f}",
                f"{r['p_rounded']:.2f}",
                f"{r['temp_rounded']:.2f}",
            ])

    print(f"  {filepath.name}: {len(rows)} samples, {duration_hours}h, {target_pressure} bar target")


if __name__ == "__main__":
    print("Generating test CSVs...")

    # 8h water test: PN25, factor 1.5 -> 37.5 bar required
    generate_csv(
        filename="messung_2026-03-14_08-00-00_8h_Wasser_Test.csv",
        name="8h Wasser Test",
        pn=25,
        medium="water",
        duration_hours=8.0,
        target_pressure=37.8,  # slightly above 37.5 required
    )

    # 24h water test: PN25, factor 1.5 -> 37.5 bar required
    generate_csv(
        filename="messung_2026-03-14_08-00-00_24h_Wasser_Langzeit.csv",
        name="24h Wasser Langzeit",
        pn=25,
        medium="water",
        duration_hours=24.0,
        target_pressure=37.8,
    )

    # 15h48min air test: PN25, factor 1.1 -> 27.5 bar required
    generate_csv(
        filename="messung_2026-03-14_08-00-00_15h48_Luft_Test.csv",
        name="15h48 Luft Test",
        pn=25,
        medium="air",
        duration_hours=15.8,
        target_pressure=27.8,  # slightly above 27.5 required
    )

    print("Done! Files in:", DATA_DIR)
