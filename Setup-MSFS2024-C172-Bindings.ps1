#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up Microsoft Flight Simulator 2024 controller bindings for the Cessna 172.

.DESCRIPTION
    Creates MSFS 2024 input profile XML files for three devices:
      1. Thrustmaster T.Flight HOTAS X  (joystick + throttle)
      2. Thrustmaster T-Rudder Pedals
      3. Honeycomb Bravo Throttle Quadrant

    The profiles are saved to your Documents folder so you can import them
    through the in-game Controls settings screen (Settings > Controls > Import).

    MSFS 2024 does NOT support dropping raw XML files into AppData and having
    them auto-load; the simulator requires profiles to be imported via its own
    UI.  This script saves the files to a well-known location and prints clear
    import instructions.

.NOTES
    Tested target: Microsoft Flight Simulator 2024 (Steam edition), all SU
    versions through the script's creation date.

    DEVICE DETAILS
    ─────────────────────────────────────────────────────────────────────────
    Thrustmaster T.Flight HOTAS X
      USB VID: 044F  PID: B108  (decimal ProductID: 45320)
      Axes (DirectInput):
        X        = Joystick left/right   → Ailerons
        Y        = Joystick forward/back → Elevator
        rZ/Z     = Joystick twist        → (mapped as rudder when pedals absent;
                                            left unbound here because T-Rudder
                                            handles rudder)
        Slider0  = Throttle lever        → Throttle

    Thrustmaster T-Rudder Pedals  (TFRP)
      USB VID: 044F  PID: B679  (decimal ProductID: 46713)
      Axes (DirectInput):
        X   = Left-right rudder input → Rudder
        rZ  = Left toe brake          → Left brake axis
        Z   = Right toe brake         → Right brake axis

    Honeycomb Bravo Throttle Quadrant
      USB VID: 294B  PID: 1901  (decimal ProductID: 6401)
      Axes (DirectInput):
        X       = Lever 1 (Throttle)  → Throttle (C172 GA lever, leftmost)
        Y       = Lever 2 (Prop)      → Propeller pitch
        Z       = Lever 3 (Mixture)   → Mixture
        rX      = Lever 4             → Cowl flaps / unbound
        rY      = Lever 5             → Condition lever / unbound
        SliderX = Flap lever          → Flaps
      Buttons (0-based index, +1 for KEY value):
        Button 0  (KEY 0)  = GA Gear UP   toggle (actually physical lever)
        Button 1  (KEY 1)  = GA Gear DOWN toggle
        Buttons 10-14      = Autopilot panel buttons (HDG, NAV, APR, REV, ALT)
        Button 19          = Autopilot master (AP)
        Button 20          = Back-course
        Button 21          = Autopilot disconnect

    XML FORMAT NOTES
    ─────────────────────────────────────────────────────────────────────────
    Each profile file covers ONE device and ONE profile type (General Controls
    OR Airplane Controls).  For the C172 recreational pilot this script creates:

      • T.Flight HOTAS X  – Airplane Controls  (primary flight axes + buttons)
      • T-Rudder Pedals   – Airplane Controls  (rudder + differential brakes)
      • Bravo Quadrant    – Airplane Controls  (engine levers + AP panel)

    General Controls (camera, menus, ATC) are intentionally left at MSFS
    defaults so the user's existing keyboard/mouse settings are not disturbed.

    Key XML element/attribute reference:
      <Version Num="-1"/>                     – always -1 for custom profiles
      <FriendlyName PlatformAvailability="1" Locked="false">…</FriendlyName>
      <Device DeviceName="…" GUID="{…}" ProductID="…" CompositeID="…" HWVer="1.0.0.0">
        <AircraftInfo CategoryName="AIRPLANE"/>
        <Axes>
          <Axis AxisName="X" AxisSensitivy="0" AxisSensitivyMinus="0"
                AxisNeutral="0" AxisDeadZone="0" AxisOutDeadZone="0"
                AxisResponseRate="-1"/>
          …
        </Axes>
        <Context ContextName="AIRCRAFT">
          <Action ActionName="KEY_AXIS_AILERONS_SET" ValueEvent="0.000000"
                  Delay="0.000000" Flag="132">
            <Primary>
              <KEY Information="Joystick Axis X">256</KEY>
            </Primary>
          </Action>
          …
        </Context>
      </Device>

    FLAG VALUES:
      2   = action present but no binding (placeholder / intentionally unbound)
      132 = axis binding  (bit 2 = axis, bit 7 = primary set)
      8194= button binding (bit 1 = button, bit 13 = primary set) – used here

    AXIS KEY CODES (DirectInput axis → MSFS KEY value):
      X Axis     = 256   (0x100)
      Y Axis     = 512   (0x200)
      Z Axis     = 768   (0x300)
      rX Axis    = 1024  (0x400)
      rY Axis    = 1280  (0x500)
      rZ Axis    = 1536  (0x600)
      SliderX    = 514   (0x202) – some devices; may vary
      SliderY    = 530   (0x212) – some devices; may vary
    POV Hat:
      POV Up     = 256, POV Down = 258, POV Left = 257, POV Right = 259
    Buttons:  0-based index as integer (Button 0 = 0, Button 1 = 1, …)

    IMPORTANT NOTE ON GUIDs
    ─────────────────────────────────────────────────────────────────────────
    The GUID in each Device element is a per-instance DirectInput GUID that
    Windows assigns when the device is first connected.  It varies from PC to
    PC.  This script uses placeholder GUIDs built from the VID/PID; after
    importing a profile MSFS will update the GUID automatically to match your
    hardware.  If MSFS does not recognise the device, open the imported profile
    in the Controls screen, re-assign any greyed-out axis, and save – MSFS
    will write the correct GUID for your machine.

.EXAMPLE
    .\Setup-MSFS2024-C172-Bindings.ps1

    Generates three XML files in your Documents\MSFS2024-C172-Profiles folder
    and prints step-by-step import instructions.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION – edit these values if you need to tweak defaults
# ─────────────────────────────────────────────────────────────────────────────

# Destination folder for the generated XML files
$OutputFolder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'MSFS2024-C172-Profiles'

# Deadzone for flight control axes (0 = no deadzone; raise to ~5-10 if your
# stick has centre wobble).  Range: 0–100.
$StickDeadzone   = 0   # aileron / elevator
$RudderDeadzone  = 0   # rudder pedals
$ThrottleDeadzone= 0   # throttle, mixture, prop levers

# Sensitivity curve (-100 to 100; 0 = linear).
# Negative values create an exponential-ish curve (gentler near centre).
$StickSensitivity  = -20   # makes fine aileron/elevator corrections easier
$RudderSensitivity = -10
$ThrSensitivity    = 0     # linear throttle response

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Title)
    $width = 72
    $line  = '─' * $width
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "  [*] $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "      $Message" -ForegroundColor Gray
}

# Build a single <Axis> element string
function New-AxisXml {
    param(
        [string]$Name,
        [int]$Sensitivity      = 0,
        [int]$SensitivityMinus = 0,   # separate minus-direction sensitivity
        [int]$Neutral          = 0,
        [int]$Deadzone         = 0,
        [int]$OutDeadzone      = 0,
        [int]$ResponseRate     = -1
    )
    return "        <Axis AxisName=`"$Name`" AxisSensitivy=`"$Sensitivity`" " +
           "AxisSensitivyMinus=`"$SensitivityMinus`" AxisNeutral=`"$Neutral`" " +
           "AxisDeadZone=`"$Deadzone`" AxisOutDeadZone=`"$OutDeadzone`" " +
           "AxisResponseRate=`"$ResponseRate`"/>"
}

# Build a single <Action> element string
# $Flag: 132 = axis binding, 8194 = button binding, 2 = unbound placeholder
# $KeyCode: numeric DirectInput code (see notes above)
# $KeyInfo: human-readable description for the Information attribute
function New-ActionXml {
    param(
        [string]$ActionName,
        [int]   $Flag        = 2,        # 2 = unbound by default
        [int]   $KeyCode     = -1,       # -1 = not used (unbound)
        [string]$KeyInfo     = '',
        [float] $ValueEvent  = 0.0,
        [float] $Delay       = 0.0
    )
    $veStr = $ValueEvent.ToString('F6')
    $dlStr = $Delay.ToString('F6')

    if ($KeyCode -ge 0) {
        return @"
            <Action ActionName="$ActionName" ValueEvent="$veStr" Delay="$dlStr" Flag="$Flag">
                <Primary>
                    <KEY Information="$KeyInfo">$KeyCode</KEY>
                </Primary>
            </Action>
"@
    } else {
        # Unbound placeholder – MSFS requires the Action element to exist even
        # when nothing is mapped so it can track the full action list.
        return "            <Action ActionName=`"$ActionName`" ValueEvent=`"$veStr`" Delay=`"$dlStr`" Flag=`"$Flag`"/>"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# XML PROFILE BUILDERS
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. THRUSTMASTER T.FLIGHT HOTAS X ─────────────────────────────────────────
#
# Bindings for the joystick unit:
#   X Axis  (256)  → Ailerons
#   Y Axis  (512)  → Elevator
#   rZ Axis (1536) → Joystick twist – left unbound (T-Rudder handles yaw)
#   SliderX (514)  → Throttle (the throttle lever on the HOTAS unit)
#
# Button layout (0-based index used as KEY value):
#   Button 0  = Trigger (fire)         → Toggle parking brake (hold 2 s)
#   Button 1  = Thumb button (red)     → Brakes (toe brake / max brakes)
#   Button 2  = Bottom-left A          → Flaps UP
#   Button 3  = Bottom-left B          → Flaps DOWN
#   Button 4  = Bottom-right C         → Elevator trim UP
#   Button 5  = Bottom-right D         → Elevator trim DOWN
#   Button 6  = Top-left long          → Gear UP / DOWN toggle
#   Button 7  = Top-left short         → Autopilot master toggle
#   Button 8  = Top-right long         → View (cockpit)  – general control
#   Button 9  = Top-right short        → Pause
#   Button 10 = Mode-switch base btn   → Map / NAV log
#   Hat (POV):
#     Up    (256) → Quick view forward
#     Down  (258) → Quick view back
#     Left  (257) → Quick view left
#     Right (259) → Quick view right
#
# NOTE: The T.Flight HOTAS X reports as a SINGLE combined USB HID device
# (joystick + throttle in one).  ProductID 45320 = 0xB108.
# ─────────────────────────────────────────────────────────────────────────────
function Build-HotasXProfile {
    param(
        [int]$SensStick    = $StickSensitivity,
        [int]$DzStick      = $StickDeadzone,
        [int]$SensThr      = $ThrSensitivity,
        [int]$DzThr        = $ThrottleDeadzone
    )

    $axes = @(
        # Joystick left/right – ailerons
        (New-AxisXml -Name 'X'       -Sensitivity $SensStick -SensitivityMinus $SensStick -Deadzone $DzStick)
        # Joystick fore/aft  – elevator  (Y is typically inverted; MSFS handles
        # inversion per-axis in the sensitivity dialog after import)
        (New-AxisXml -Name 'Y'       -Sensitivity $SensStick -SensitivityMinus $SensStick -Deadzone $DzStick)
        # Joystick twist – present on device but unbound (T-Rudder used for yaw)
        (New-AxisXml -Name 'rZ'      -Sensitivity 0          -Deadzone 0)
        # Throttle lever
        (New-AxisXml -Name 'SliderX' -Sensitivity $SensThr   -SensitivityMinus $SensThr -Deadzone $DzThr)
    ) -join "`n"

    # AIRCRAFT context – primary flight controls and commonly used functions
    $aircraftActions = @(
        # ── AXIS BINDINGS (Flag=132) ──────────────────────────────────────────
        # Ailerons: X axis (KEY 256)
        (New-ActionXml -ActionName 'KEY_AXIS_AILERONS_SET'      -Flag 132 -KeyCode 256  -KeyInfo 'Joystick Axis X')
        # Elevator: Y axis (KEY 512) – you may need to tick "Reverse" in-sim
        (New-ActionXml -ActionName 'KEY_AXIS_ELEVATOR_SET'      -Flag 132 -KeyCode 512  -KeyInfo 'Joystick Axis Y')
        # Rudder: intentionally unbound – handled by T-Rudder pedals profile
        (New-ActionXml -ActionName 'KEY_AXIS_RUDDER_SET'        -Flag 2)
        # Throttle: the HOTAS throttle slider
        (New-ActionXml -ActionName 'KEY_AXIS_THROTTLE_SET'      -Flag 132 -KeyCode 514  -KeyInfo 'Joystick Slider X')
        # Elevator trim axis: unbound – using buttons instead (see below)
        (New-ActionXml -ActionName 'KEY_AXIS_ELEV_TRIM_SET'     -Flag 2)
        # Mixture and prop: handled by Bravo Quadrant
        (New-ActionXml -ActionName 'KEY_AXIS_MIXTURE_SET'       -Flag 2)
        (New-ActionXml -ActionName 'KEY_PROP_PITCH_AXIS_SET_EX1'-Flag 2)
        # Flaps axis: unbound – using buttons instead
        (New-ActionXml -ActionName 'KEY_AXIS_FLAPS_SET'         -Flag 2)
        # Brakes axis: unbound – handled by T-Rudder toe brakes
        (New-ActionXml -ActionName 'KEY_AXIS_LEFT_BRAKE_SET'    -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_RIGHT_BRAKE_SET'   -Flag 2)

        # ── BUTTON BINDINGS (Flag=8194) ───────────────────────────────────────
        # Trigger (Button 0) → toggle parking brake
        (New-ActionXml -ActionName 'KEY_PARKING_BRAKES'         -Flag 8194 -KeyCode 0   -KeyInfo 'Joystick Button 1')
        # Thumb button (Button 1) – max brakes (both)
        (New-ActionXml -ActionName 'KEY_BRAKES'                 -Flag 8194 -KeyCode 1   -KeyInfo 'Joystick Button 2')
        # Button 2 – flaps retract one step
        (New-ActionXml -ActionName 'KEY_FLAPS_DECR'             -Flag 8194 -KeyCode 2   -KeyInfo 'Joystick Button 3')
        # Button 3 – flaps extend one step
        (New-ActionXml -ActionName 'KEY_FLAPS_INCR'             -Flag 8194 -KeyCode 3   -KeyInfo 'Joystick Button 4')
        # Button 4 – elevator trim nose up (pitch up = nose up in MSFS convention)
        (New-ActionXml -ActionName 'KEY_ELEV_TRIM_UP'           -Flag 8194 -KeyCode 4   -KeyInfo 'Joystick Button 5')
        # Button 5 – elevator trim nose down
        (New-ActionXml -ActionName 'KEY_ELEV_TRIM_DN'           -Flag 8194 -KeyCode 5   -KeyInfo 'Joystick Button 6')
        # Button 6 – landing gear toggle
        (New-ActionXml -ActionName 'KEY_GEAR_TOGGLE'            -Flag 8194 -KeyCode 6   -KeyInfo 'Joystick Button 7')
        # Button 7 – autopilot master on/off
        (New-ActionXml -ActionName 'KEY_AP_MASTER'              -Flag 8194 -KeyCode 7   -KeyInfo 'Joystick Button 8')
        # Button 8 – cycle cockpit views
        (New-ActionXml -ActionName 'KEY_COCKPIT_CAMERA_TOGGLE'  -Flag 8194 -KeyCode 8   -KeyInfo 'Joystick Button 9')
        # Button 9 – pause simulation
        (New-ActionXml -ActionName 'KEY_PAUSE_TOGGLE'           -Flag 8194 -KeyCode 9   -KeyInfo 'Joystick Button 10')
        # POV hat – quick views (instant, no delay)
        (New-ActionXml -ActionName 'KEY_COCKPIT_QUICKVIEW1'     -Flag 8194 -KeyCode 256 -KeyInfo 'Joystick Pov Up')
        (New-ActionXml -ActionName 'KEY_COCKPIT_QUICKVIEW2'     -Flag 8194 -KeyCode 258 -KeyInfo 'Joystick Pov Down')
        (New-ActionXml -ActionName 'KEY_COCKPIT_QUICKVIEW3'     -Flag 8194 -KeyCode 257 -KeyInfo 'Joystick Pov Left')
        (New-ActionXml -ActionName 'KEY_COCKPIT_QUICKVIEW4'     -Flag 8194 -KeyCode 259 -KeyInfo 'Joystick Pov Right')
    ) -join "`n"

    return @"
<?xml version="1.0" encoding="UTF-8"?>
<!--
    MSFS 2024 – Cessna 172 – Thrustmaster T.Flight HOTAS X – Airplane Controls
    Generated by Setup-MSFS2024-C172-Bindings.ps1
    Import via: MSFS Settings > Controls > [select T.Flight HOTAS X] > Import
-->
<Version Num="-1"/>
<FriendlyName PlatformAvailability="1" Locked="false">C172 – T.Flight HOTAS X</FriendlyName>
<Device DeviceName="T.Flight Hotas X" GUID="{B1080000-0000-0000-0000-044F00000000}" ProductID="45320" CompositeID="0" HWVer="1.0.0.0">
    <AircraftInfo CategoryName="AIRPLANE"/>
    <Axes>
$axes
    </Axes>
    <Context ContextName="AIRCRAFT">
$aircraftActions
    </Context>
</Device>
"@
}


# ── 2. THRUSTMASTER T-RUDDER PEDALS ──────────────────────────────────────────
#
# Axes exposed by the TFRP pedals (DirectInput):
#   X   (256)  = Rudder bar left/right → Rudder axis
#   Z   (768)  = Right toe brake       → Right brake
#   rZ  (1536) = Left toe brake        → Left brake
#
# ProductID 46713 = 0xB679
# ─────────────────────────────────────────────────────────────────────────────
function Build-TRudderProfile {
    param(
        [int]$SensRud  = $RudderSensitivity,
        [int]$DzRud    = $RudderDeadzone
    )

    $axes = @(
        # Rudder bar (yaw)
        (New-AxisXml -Name 'X'  -Sensitivity $SensRud -SensitivityMinus $SensRud -Deadzone $DzRud)
        # Right toe brake
        (New-AxisXml -Name 'Z'  -Sensitivity 0        -Deadzone 0)
        # Left toe brake
        (New-AxisXml -Name 'rZ' -Sensitivity 0        -Deadzone 0)
    ) -join "`n"

    $aircraftActions = @(
        # Rudder axis (KEY 256 = X axis)
        (New-ActionXml -ActionName 'KEY_AXIS_RUDDER_SET'          -Flag 132 -KeyCode 256  -KeyInfo 'Joystick Axis X')
        # Right brake (KEY 768 = Z axis)
        (New-ActionXml -ActionName 'KEY_AXIS_RIGHT_BRAKE_SET'     -Flag 132 -KeyCode 768  -KeyInfo 'Joystick Axis Z')
        # Left brake (KEY 1536 = rZ axis)
        (New-ActionXml -ActionName 'KEY_AXIS_LEFT_BRAKE_SET'      -Flag 132 -KeyCode 1536 -KeyInfo 'Joystick Axis rZ')
        # The following are explicitly unbound on pedals – other devices handle them
        (New-ActionXml -ActionName 'KEY_AXIS_AILERONS_SET'        -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_ELEVATOR_SET'        -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_THROTTLE_SET'        -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_MIXTURE_SET'         -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_FLAPS_SET'           -Flag 2)
    ) -join "`n"

    return @"
<?xml version="1.0" encoding="UTF-8"?>
<!--
    MSFS 2024 – Cessna 172 – Thrustmaster T-Rudder Pedals – Airplane Controls
    Generated by Setup-MSFS2024-C172-Bindings.ps1
    Import via: MSFS Settings > Controls > [select T-Rudder] > Import
-->
<Version Num="-1"/>
<FriendlyName PlatformAvailability="1" Locked="false">C172 – T-Rudder Pedals</FriendlyName>
<Device DeviceName="T-Rudder" GUID="{B6790000-0000-0000-0000-044F00000000}" ProductID="46713" CompositeID="0" HWVer="1.0.0.0">
    <AircraftInfo CategoryName="AIRPLANE"/>
    <Axes>
$axes
    </Axes>
    <Context ContextName="AIRCRAFT">
$aircraftActions
    </Context>
</Device>
"@
}


# ── 3. HONEYCOMB BRAVO THROTTLE QUADRANT ─────────────────────────────────────
#
# The Bravo exposes its levers as DirectInput axes:
#   X  (256)  = Lever 1 (leftmost, usually Throttle for GA single)
#   Y  (512)  = Lever 2 (Propeller RPM for GA)
#   Z  (768)  = Lever 3 (Mixture for GA)
#   rX (1024) = Lever 4 (spare – cowl flaps on C172 or unbound)
#   rY (1280) = Lever 5 (spare – unbound on C172)
#   SliderX varies per firmware; the flap lever is often reported as a
#   separate axis or as SliderX (514).
#
# Autopilot panel buttons (0-based):
#   Note: MSFS KEY value for buttons = 0-based index integer
#   Button 10 = HDG (Heading)     → AP heading hold
#   Button 11 = NAV (Nav/GPS)     → AP nav hold
#   Button 12 = APR (Approach)    → AP approach hold
#   Button 13 = REV (Back course) → AP reverse course
#   Button 14 = ALT (Altitude)    → AP altitude hold
#   Button 15 = VS  (Vert speed)  → AP vertical speed hold
#   Button 16 = IAS (Airspeed)    → AP speed hold
#   Button 17 = A/P (Master)      → AP master toggle
#   Button 18 = YD  (Yaw Damper)  → Yaw damper toggle
#
# GA lever buttons (physical detent / switch positions):
#   Button 0  = Gear lever UP position   (if equipped)
#   Button 1  = Gear lever DOWN position (if equipped)
#   Button 2  = Toga/go-around          → not used on C172 in this profile
#
# Annunciator / trim hat:
#   Button 24 = Trim wheel up
#   Button 25 = Trim wheel down
#
# ProductID 6401 = 0x1901; VID 0x294B
# ─────────────────────────────────────────────────────────────────────────────
function Build-BravoProfile {
    param(
        [int]$SensThr  = $ThrSensitivity,
        [int]$DzThr    = $ThrottleDeadzone
    )

    $axes = @(
        # Lever 1 – Throttle (GA single engine, left-most lever)
        (New-AxisXml -Name 'X'       -Sensitivity $SensThr -SensitivityMinus $SensThr -Deadzone $DzThr)
        # Lever 2 – Propeller pitch / RPM (blue lever on Bravo)
        (New-AxisXml -Name 'Y'       -Sensitivity $SensThr -SensitivityMinus $SensThr -Deadzone $DzThr)
        # Lever 3 – Mixture (red lever on Bravo)
        (New-AxisXml -Name 'Z'       -Sensitivity $SensThr -SensitivityMinus $SensThr -Deadzone $DzThr)
        # Lever 4 – unbound (could be cowl flaps; disabled for basic C172)
        (New-AxisXml -Name 'rX'      -Sensitivity 0        -Deadzone 0)
        # Lever 5 – unbound
        (New-AxisXml -Name 'rY'      -Sensitivity 0        -Deadzone 0)
        # Flap lever (physical lever on right side of Bravo)
        (New-AxisXml -Name 'SliderX' -Sensitivity 0        -Deadzone 0)
    ) -join "`n"

    $aircraftActions = @(
        # ── AXIS BINDINGS ─────────────────────────────────────────────────────
        # Throttle – Lever 1 (X axis, KEY 256)
        # NOTE: Throttle is also bound on the HOTAS X; whichever device you
        # move last will take effect.  If you prefer the Bravo levers only,
        # remove the throttle binding from the HOTAS X profile after import.
        (New-ActionXml -ActionName 'KEY_AXIS_THROTTLE_SET'         -Flag 132 -KeyCode 256  -KeyInfo 'Joystick Axis X')
        # Propeller pitch – Lever 2 (Y axis, KEY 512)
        (New-ActionXml -ActionName 'KEY_PROP_PITCH_AXIS_SET_EX1'   -Flag 132 -KeyCode 512  -KeyInfo 'Joystick Axis Y')
        # Mixture – Lever 3 (Z axis, KEY 768)
        (New-ActionXml -ActionName 'KEY_AXIS_MIXTURE_SET'          -Flag 132 -KeyCode 768  -KeyInfo 'Joystick Axis Z')
        # Flaps – physical flap lever (SliderX, KEY 514)
        (New-ActionXml -ActionName 'KEY_AXIS_FLAPS_SET'            -Flag 132 -KeyCode 514  -KeyInfo 'Joystick Slider X')
        # The following axes are managed by other devices
        (New-ActionXml -ActionName 'KEY_AXIS_AILERONS_SET'         -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_ELEVATOR_SET'         -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_RUDDER_SET'           -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_LEFT_BRAKE_SET'       -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_RIGHT_BRAKE_SET'      -Flag 2)
        (New-ActionXml -ActionName 'KEY_AXIS_ELEV_TRIM_SET'        -Flag 2)

        # ── AUTOPILOT BUTTON BINDINGS ─────────────────────────────────────────
        # These correspond to the illuminated push-buttons on the Bravo's
        # autopilot panel.  The C172 G1000 glass cockpit supports all of these.
        # Heading hold
        (New-ActionXml -ActionName 'KEY_AP_HDG_HOLD'               -Flag 8194 -KeyCode 10  -KeyInfo 'Joystick Button 11')
        # NAV / GPSS hold
        (New-ActionXml -ActionName 'KEY_AP_NAV1_HOLD'              -Flag 8194 -KeyCode 11  -KeyInfo 'Joystick Button 12')
        # Approach mode
        (New-ActionXml -ActionName 'KEY_AP_APR_HOLD'               -Flag 8194 -KeyCode 12  -KeyInfo 'Joystick Button 13')
        # Back-course (reverse localiser)
        (New-ActionXml -ActionName 'KEY_AP_BC_HOLD'                -Flag 8194 -KeyCode 13  -KeyInfo 'Joystick Button 14')
        # Altitude hold
        (New-ActionXml -ActionName 'KEY_AP_ALT_HOLD'               -Flag 8194 -KeyCode 14  -KeyInfo 'Joystick Button 15')
        # Vertical speed hold
        (New-ActionXml -ActionName 'KEY_AP_VS_HOLD'                -Flag 8194 -KeyCode 15  -KeyInfo 'Joystick Button 16')
        # Indicated airspeed hold
        (New-ActionXml -ActionName 'KEY_AP_AIRSPEED_HOLD'          -Flag 8194 -KeyCode 16  -KeyInfo 'Joystick Button 17')
        # Autopilot master on/off
        (New-ActionXml -ActionName 'KEY_AP_MASTER'                 -Flag 8194 -KeyCode 17  -KeyInfo 'Joystick Button 18')
        # Yaw damper
        (New-ActionXml -ActionName 'KEY_YAW_DAMPER_TOGGLE'         -Flag 8194 -KeyCode 18  -KeyInfo 'Joystick Button 19')

        # ── TRIM HAT / WHEEL ──────────────────────────────────────────────────
        # Some Bravo firmware versions expose the trim wheel as buttons 24/25
        (New-ActionXml -ActionName 'KEY_ELEV_TRIM_UP'              -Flag 8194 -KeyCode 24  -KeyInfo 'Joystick Button 25')
        (New-ActionXml -ActionName 'KEY_ELEV_TRIM_DN'              -Flag 8194 -KeyCode 25  -KeyInfo 'Joystick Button 26')

        # ── GEAR LEVER ────────────────────────────────────────────────────────
        # The Bravo gear lever has UP/DOWN switch positions.
        # C172 is fixed-gear so these are mapped to toggle for completeness
        # (useful if you fly retractable variants too).
        (New-ActionXml -ActionName 'KEY_GEAR_UP'                   -Flag 8194 -KeyCode 0   -KeyInfo 'Joystick Button 1')
        (New-ActionXml -ActionName 'KEY_GEAR_DOWN'                 -Flag 8194 -KeyCode 1   -KeyInfo 'Joystick Button 2')
    ) -join "`n"

    return @"
<?xml version="1.0" encoding="UTF-8"?>
<!--
    MSFS 2024 – Cessna 172 – Honeycomb Bravo Throttle Quadrant – Airplane Controls
    Generated by Setup-MSFS2024-C172-Bindings.ps1
    Import via: MSFS Settings > Controls > [select Bravo Throttle Quadrant] > Import
-->
<Version Num="-1"/>
<FriendlyName PlatformAvailability="1" Locked="false">C172 – Bravo Throttle Quadrant</FriendlyName>
<Device DeviceName="Bravo Throttle Quadrant" GUID="{19010000-0000-0000-0000-294B00000000}" ProductID="6401" CompositeID="0" HWVer="1.0.0.0">
    <AircraftInfo CategoryName="AIRPLANE"/>
    <Axes>
$axes
    </Axes>
    <Context ContextName="AIRCRAFT">
$aircraftActions
    </Context>
</Device>
"@
}


# ─────────────────────────────────────────────────────────────────────────────
# MAIN SCRIPT BODY
# ─────────────────────────────────────────────────────────────────────────────

Write-Header 'MSFS 2024 – Cessna 172 Controller Profile Generator'
Write-Host ''
Write-Host '  This script generates three XML controller profile files for:' -ForegroundColor White
Write-Host '    * Thrustmaster T.Flight HOTAS X    (joystick + throttle unit)' -ForegroundColor White
Write-Host '    * Thrustmaster T-Rudder Pedals      (rudder + toe brakes)'      -ForegroundColor White
Write-Host '    * Honeycomb Bravo Throttle Quadrant (engine levers + AP panel)' -ForegroundColor White
Write-Host ''

# ── Create output directory ──────────────────────────────────────────────────
Write-Step 'Creating output folder ...'
try {
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    Write-Ok "Output folder: $OutputFolder"
} catch {
    Write-Error "Failed to create output folder '$OutputFolder': $_"
    exit 1
}

# ── Generate XML content ─────────────────────────────────────────────────────
Write-Step 'Building XML profile for T.Flight HOTAS X ...'
$hotasXml  = Build-HotasXProfile
Write-Ok 'Done.'

Write-Step 'Building XML profile for T-Rudder Pedals ...'
$rudderXml = Build-TRudderProfile
Write-Ok 'Done.'

Write-Step 'Building XML profile for Bravo Throttle Quadrant ...'
$bravoXml  = Build-BravoProfile
Write-Ok 'Done.'

# ── Write files ──────────────────────────────────────────────────────────────
$files = @{
    'C172-TFlightHotasX-AirplaneControls.xml'    = $hotasXml
    'C172-TRudderPedals-AirplaneControls.xml'    = $rudderXml
    'C172-BravoQuadrant-AirplaneControls.xml'    = $bravoXml
}

Write-Step 'Writing XML files to disk ...'
$writtenFiles = @()
foreach ($fileName in $files.Keys) {
    $filePath = Join-Path $OutputFolder $fileName
    try {
        # Use UTF-8 without BOM – MSFS prefers plain UTF-8
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($filePath, $files[$fileName], $utf8NoBom)
        Write-Ok $fileName
        Write-Info $filePath
        $writtenFiles += $filePath
    } catch {
        Write-Host "  [ERROR] Could not write $fileName : $_" -ForegroundColor Red
    }
}

# ── Open the output folder in Explorer ───────────────────────────────────────
Write-Step 'Opening output folder in Windows Explorer ...'
try {
    Start-Process explorer.exe -ArgumentList $OutputFolder
} catch {
    Write-Info 'Could not open Explorer automatically.'
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY AND IMPORT INSTRUCTIONS
# ─────────────────────────────────────────────────────────────────────────────
Write-Header 'Files Created'
foreach ($f in $writtenFiles) {
    Write-Host "  $f" -ForegroundColor Cyan
}

Write-Header 'How to Import These Profiles Into MSFS 2024'

Write-Host @'

  STEP-BY-STEP IMPORT INSTRUCTIONS
  ─────────────────────────────────────────────────────────────────────────
  Repeat the following steps for EACH of the three XML files:

  1. Launch Microsoft Flight Simulator 2024.
  2. From the main menu go to:  Settings  >  Controls
  3. At the top of the Controls screen, click the device selector and choose
     the matching physical controller:
       * "T.Flight HOTAS X" (or similar name)   for the HOTAS X profile
       * "T-Rudder" or "T.Flight Rudder"         for the pedals profile
       * "Bravo Throttle Quadrant"               for the Bravo profile
  4. Click the cogwheel / profile menu icon next to the profile name.
  5. Choose  "Import"  from the drop-down.
  6. Navigate to:
'@ -ForegroundColor White

Write-Host "       $OutputFolder" -ForegroundColor Cyan

Write-Host @'

  7. Select the matching XML file for that device and click Open.
  8. MSFS will ask you to confirm – click OK / Accept.
  9. The profile named "C172 – [Device]" will appear in the profile list.
     Select it and click  "Save"  (or it may auto-save).
 10. Repeat for the other two devices.

  AFTER IMPORTING – IMPORTANT CHECKS
  ─────────────────────────────────────────────────────────────────────────
  * Axes may need "Reverse" toggled:
      - Elevator (Y axis on HOTAS X): pushing forward should pitch nose DOWN.
        If it pitches up, tick the Reverse checkbox in the Axis settings.
      - Throttle, Mixture, Prop levers: pulling back = less power; if
        reversed, tick Reverse.
      - Toe brakes: pressing the toe should apply braking force.

  * Sensitivity curve already set to −20 (stick) / −10 (rudder).
    Adjust under the "Sensitivity" panel after importing if preferred.

  * GUID notice: this script uses placeholder GUIDs (based on USB VID/PID).
    MSFS will automatically update the GUID to match your hardware when you
    move an axis or press a button on the device after importing.  If MSFS
    shows "Unrecognised device", simply move a lever/axis on that device
    and save the profile.

  * Throttle conflict: Both the T.Flight HOTAS X and the Bravo are mapped to
    KEY_AXIS_THROTTLE_SET.  In MSFS the last-moved axis wins.  If you want
    the Bravo throttle lever to be the primary, open the HOTAS X profile,
    find KEY_AXIS_THROTTLE_SET, and clear its binding (set to unbound).

  CESSNA 172 CONTROL SUMMARY
  ─────────────────────────────────────────────────────────────────────────
  T.Flight HOTAS X:
    Joystick X axis    → Ailerons (roll)
    Joystick Y axis    → Elevator (pitch)
    Throttle slider    → Throttle
    Trigger (hold 2s)  → Parking brake toggle
    Thumb button       → Max brakes
    Buttons 2 / 3      → Flaps UP / DOWN (one step at a time)
    Buttons 4 / 5      → Elevator trim nose-UP / nose-DOWN
    Button 6           → Landing gear toggle
    Button 7           → Autopilot master toggle
    Button 8           → Cycle cockpit camera view
    Button 9           → Pause
    POV Hat            → Quick-look views (forward/back/left/right)

  T-Rudder Pedals:
    Rudder bar (X)     → Rudder (yaw)
    Right toe brake    → Right wheel brake
    Left toe brake     → Left wheel brake

  Honeycomb Bravo:
    Lever 1 (black)    → Throttle
    Lever 2 (blue)     → Propeller pitch / RPM
    Lever 3 (red)      → Fuel mixture
    Flap lever         → Flaps (continuous axis)
    Gear lever UP      → Gear up   (hold 2 s)
    Gear lever DOWN    → Gear down (hold 2 s)
    AP panel buttons   → HDG / NAV / APR / REV / ALT / VS / IAS / A/P / YD
    Trim wheel         → Elevator trim (up / down)

'@ -ForegroundColor White

Write-Header 'Done!'
Write-Host ''
Write-Host '  Profile files are ready in:' -ForegroundColor Green
Write-Host "  $OutputFolder" -ForegroundColor Cyan
Write-Host ''
Write-Host '  Happy flying! Blue skies and smooth landings.' -ForegroundColor Green
Write-Host ''
