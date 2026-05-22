"""
Cessna 172 Controller Calibration Tool
Supports: T-Rudder, T.Flight Hotas X, Bravo Throttle Quadrant
Requires: pip install pygame
"""

import pygame
import sys
import json
import os
import time

# C172 axis mapping targets
C172_AXES = {
    "Aileron":    "T.Flight Hotas X  →  Axis 0 (stick left/right)",
    "Elevator":   "T.Flight Hotas X  →  Axis 1 (stick forward/back)",
    "Throttle":   "T.Flight Hotas X  →  Axis 2  OR  Bravo lever 1",
    "Rudder":     "T-Rudder          →  Axis 0 (left/right pedal)",
    "Mixture":    "Bravo Throttle    →  Lever 2",
    "Flaps":      "Bravo Throttle    →  Lever 3 or switch",
    "Brakes":     "T-Rudder          →  Axis 1/2 (toe brakes)",
}

CALIBRATION_FILE = "c172_calibration.json"

def clear():
    os.system("cls" if os.name == "nt" else "clear")

def header():
    print("=" * 60)
    print("   Cessna 172 Controller Calibration  —  MSFS 2024")
    print("=" * 60)

def detect_controllers(joysticks):
    print("\n  Detected controllers:")
    if not joysticks:
        print("  [!] No controllers found. Check USB connections.")
    for i, j in enumerate(joysticks):
        print(f"  [{i}] {j.get_name()}  —  {j.get_numaxes()} axes, "
              f"{j.get_numbuttons()} buttons, {j.get_numhats()} hats")
    print()

def live_monitor(joysticks):
    """Show all axis values in real time. Press Ctrl+C to exit."""
    print("\n  LIVE AXIS MONITOR  (Ctrl+C to return to menu)\n")
    try:
        while True:
            pygame.event.pump()
            clear()
            header()
            print("  LIVE AXIS MONITOR  (Ctrl+C to return to menu)\n")
            for j in joysticks:
                print(f"  [{j.get_name()}]")
                for a in range(j.get_numaxes()):
                    val = j.get_axis(a)
                    bar = make_bar(val)
                    print(f"    Axis {a}: {val:+.4f}  {bar}")
                for h in range(j.get_numhats()):
                    print(f"    Hat  {h}: {j.get_hat(h)}")
                print()
            time.sleep(0.05)
    except KeyboardInterrupt:
        pass

def make_bar(val, width=30):
    """ASCII bar graph for axis value -1.0 … +1.0."""
    mid = width // 2
    pos = int((val + 1.0) / 2.0 * width)
    pos = max(0, min(width - 1, pos))
    bar = ["-"] * width
    bar[mid] = "|"
    bar[pos] = "#"
    return "[" + "".join(bar) + "]"

def calibrate_axis(joysticks):
    """Walk through each C172 control, record min/max/center."""
    results = {}
    controls = [
        ("Aileron",  "Move stick fully LEFT then fully RIGHT, release center"),
        ("Elevator", "Push stick fully FORWARD then fully BACK, release center"),
        ("Rudder",   "Press LEFT pedal fully, then RIGHT pedal fully, center"),
        ("Throttle", "Move throttle to IDLE (min) then FULL POWER (max)"),
        ("Mixture",  "Move mixture to FULL LEAN then FULL RICH"),
        ("Flaps",    "Move flap lever full UP then full DOWN"),
        ("Toe Brake L", "Press LEFT toe brake fully, then release"),
        ("Toe Brake R", "Press RIGHT toe brake fully, then release"),
    ]

    print("\n  AXIS CALIBRATION\n")
    print("  For each control you will have 5 seconds to move the axis.")
    print("  The tool records the min, max, and resting (center) value.\n")

    for ctrl_name, instruction in controls:
        input(f"  [{ctrl_name}]  Press ENTER then: {instruction} ...")
        print("  Sampling for 5 seconds ...", end="", flush=True)

        samples = []
        deadline = time.time() + 5.0
        while time.time() < deadline:
            pygame.event.pump()
            for j in joysticks:
                for a in range(j.get_numaxes()):
                    samples.append((j.get_name(), a, j.get_axis(a)))
            time.sleep(0.02)

        # Find the axis that moved the most during sampling
        axis_range = {}
        for name, ax, val in samples:
            key = (name, ax)
            lo, hi = axis_range.get(key, (val, val))
            axis_range[key] = (min(lo, val), max(hi, val))

        best_key = max(axis_range, key=lambda k: axis_range[k][1] - axis_range[k][0])
        lo, hi = axis_range[best_key]

        # Center = last reading on that axis
        pygame.event.pump()
        for j in joysticks:
            if j.get_name() == best_key[0]:
                center = j.get_axis(best_key[1])

        results[ctrl_name] = {
            "controller": best_key[0],
            "axis": best_key[1],
            "min": round(lo, 4),
            "max": round(hi, 4),
            "center": round(center, 4),
            "range": round(hi - lo, 4),
        }
        print(f"\r  [{ctrl_name}]  controller='{best_key[0]}'  "
              f"axis={best_key[1]}  min={lo:+.3f}  max={hi:+.3f}  "
              f"center={center:+.3f}  range={hi-lo:.3f}")

    return results

def show_c172_mapping():
    print("\n  Cessna 172 recommended axis assignments for MSFS:\n")
    for ctrl, hint in C172_AXES.items():
        print(f"  {ctrl:<14} {hint}")
    print()
    input("  Press ENTER to continue ...")

def save_results(results):
    with open(CALIBRATION_FILE, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n  Saved to {CALIBRATION_FILE}")

def show_results(results):
    if not results:
        print("  No calibration data yet.")
        return
    print("\n  CALIBRATION RESULTS\n")
    print(f"  {'Control':<14} {'Controller':<28} {'Axis':>4}  "
          f"{'Min':>7}  {'Max':>7}  {'Center':>7}  {'Range':>6}")
    print("  " + "-" * 78)
    for ctrl, d in results.items():
        print(f"  {ctrl:<14} {d['controller']:<28} {d['axis']:>4}  "
              f"{d['min']:>+7.3f}  {d['max']:>+7.3f}  "
              f"{d['center']:>+7.3f}  {d['range']:>6.3f}")
    print()

def main():
    pygame.init()
    pygame.joystick.init()

    joysticks = [pygame.joystick.Joystick(i)
                 for i in range(pygame.joystick.get_count())]
    for j in joysticks:
        j.init()

    results = {}
    if os.path.exists(CALIBRATION_FILE):
        with open(CALIBRATION_FILE) as f:
            results = json.load(f)
        print(f"  Loaded previous calibration from {CALIBRATION_FILE}")

    while True:
        clear()
        header()
        detect_controllers(joysticks)
        print("  1. Live axis monitor")
        print("  2. Calibrate axes (C172 walkthrough)")
        print("  3. Show C172 axis mapping guide")
        print("  4. Show current calibration results")
        print("  5. Save calibration to file")
        print("  6. Re-scan controllers")
        print("  0. Exit\n")

        choice = input("  Choice: ").strip()

        if choice == "1":
            live_monitor(joysticks)
        elif choice == "2":
            new = calibrate_axis(joysticks)
            results.update(new)
            show_results(results)
            save_results(results)
            input("  Press ENTER to continue ...")
        elif choice == "3":
            show_c172_mapping()
        elif choice == "4":
            show_results(results)
            input("  Press ENTER to continue ...")
        elif choice == "5":
            save_results(results)
            input("  Press ENTER to continue ...")
        elif choice == "6":
            joysticks = [pygame.joystick.Joystick(i)
                         for i in range(pygame.joystick.get_count())]
            for j in joysticks:
                j.init()
        elif choice == "0":
            pygame.quit()
            sys.exit(0)

if __name__ == "__main__":
    main()
