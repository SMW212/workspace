# 3-Step Regulator Documentation

## Overview

The **ThreeStepRegulatorFB** is a Function Block that implements a 3-position controller with hysteresis for controlling physical values (temperature, pressure, level, etc.). It's ideal for systems that can:
- **Heat** (increase the value)
- **Cool/Lower** (decrease the value)  
- **Off** (maintain current state)

## How It Works

### State Machine
The regulator uses a 3-state machine with **hysteresis** (deadband) to prevent chatter and unstable control:

```
                    rDeviation > rHysteresisHigh
                            ↓
    ┌───────────────────────────────────────────┐
    │                                           ↓
 HEATING ←──────────────────────────────────── COOLING
    ↓                                           ↑
    └────────────→ OFF ←──────────────────────┘
                 (deadband)
         rDeviation < rHysteresisLow
```

### Hysteresis Example

For **temperature control** with a setpoint of 50°C:
- `rHysteresisHigh = +2.0` → Start cooling when value > 52°C
- `rHysteresisLow = -2.0` → Start heating when value < 48°C
- When heating: stop when value reaches ~51°C (OFF state)
- When cooling: stop when value reaches ~49°C (OFF state)

This prevents rapid on/off switching (chatter) near the setpoint.

## Function Block Interface

### Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `rSetpoint` | REAL | - | Target value (e.g., 85.0 for 85°C) |
| `rProcessValue` | REAL | - | Current measured value from sensor |
| `rHysteresisHigh` | REAL | 2.0 | Upper deadband threshold |
| `rHysteresisLow` | REAL | -2.0 | Lower deadband threshold |
| `bEnable` | BOOL | TRUE | Enable/disable the regulator |

### Outputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `bHeating` | BOOL | TRUE when actively heating/increasing |
| `bCooling` | BOOL | TRUE when actively cooling/decreasing |
| `bOff` | BOOL | TRUE when in neutral/off state (within deadband) |
| `eRegulatorState` | Enum | Current state: OFF, HEATING, or COOLING |
| `rDeviation` | REAL | Error value: `rProcessValue - rSetpoint` |
| `iCyclesSinceChange` | INT | Diagnostic counter for state duration |

## Usage Example

### Basic Temperature Control

```scl
// In main program VAR section
tempRegulator : "ThreeStepRegulatorFB";

// In main logic
tempRegulator(
    rSetpoint := 85.0,                    // Target: 85°C
    rProcessValue := currentTemp,          // Read from sensor
    rHysteresisHigh := 2.0,               // ±2°C deadband
    rHysteresisLow := -2.0,
    bEnable := TRUE
);

// Use outputs to control devices
IF tempRegulator.bHeating THEN
    recipe.outputData.bHeaterEnable := TRUE;
    recipe.outputData.bCoolerEnable := FALSE;
    
ELSIF tempRegulator.bCooling THEN
    recipe.outputData.bHeaterEnable := FALSE;
    recipe.outputData.bCoolerEnable := TRUE;
    
ELSE
    recipe.outputData.bHeaterEnable := FALSE;
    recipe.outputData.bCoolerEnable := FALSE;
END_IF;
```

### Pressure Control

```scl
pressureRegulator : "ThreeStepRegulatorFB";

pressureRegulator(
    rSetpoint := 5.5,                     // Target: 5.5 bar
    rProcessValue := currentPressure,
    rHysteresisHigh := 0.3,               // ±0.3 bar deadband
    rHysteresisLow := -0.3,
    bEnable := bProcessRunning
);

// Pump ON/OFF control
recipe.outputData.bPumpEnable := pressureRegulator.bHeating;
recipe.outputData.bReleaseValve := pressureRegulator.bCooling;
```

## Tuning Guidelines

### Hysteresis Selection

- **Too large**: Slow response, poor control accuracy
- **Too small**: Frequent switching, device wear, chatter
- **Rule of thumb**: 5-10% of the setpoint value

Examples:
- Temperature (0-100°C range): Hysteresis = ±2-5°C
- Pressure (0-10 bar range): Hysteresis = ±0.3-0.5 bar
- Level (0-100% range): Hysteresis = ±5-10%

### State Duration Monitoring

Use `iCyclesSinceChange` to detect stuck states:
```scl
IF tempRegulator.iCyclesSinceChange > 500 THEN  // ~50 seconds at 100ms cycle
    IF tempRegulator.eRegulatorState <> RegulatorStateEnum.OFF THEN
        // Device may be stuck (heater/cooler not working)
        bSystemError := TRUE;
    END_IF;
END_IF;
```

## Common Applications

- **Temperature control**: Ovens, reactors, chillers
- **Pressure control**: Compressors, vacuum systems, hydraulics
- **Level control**: Tanks, reservoirs (with pumps/drains)
- **Speed control**: Motor speed targets (ramping up/down)
- **Position control**: Valve positions, dampers

## Diagnostic Information

The regulator provides status for monitoring and debugging:

```scl
// Display current state
CASE tempRegulator.eRegulatorState OF
    RegulatorStateEnum.OFF:
        sStatus := 'In Setpoint';
    RegulatorStateEnum.HEATING:
        sStatus := 'Heating';
    RegulatorStateEnum.COOLING:
        sStatus := 'Cooling';
END_CASE;

// Log deviation for trend analysis
LogData(
    timestamp := CURRENT_TIME,
    setpoint := tempRegulator.rSetpoint,
    processValue := tempRegulator.rProcessValue,
    deviation := tempRegulator.rDeviation,
    state := tempRegulator.eRegulatorState
);
```

## Implementation Notes

- The regulator runs every PLC cycle (100ms default)
- No internal ramp-up/ramp-down (devices controlled directly: heater ON/OFF, cooler ON/OFF)
- For smooth ramps, apply to the heating/cooling device control, not this regulator
- All REAL arithmetic for precise decimal control
- State transitions logged in `iCyclesSinceChange` for diagnostics
