# TIA Portal 3-step regulator function
_Exported on 12/9/2025 at 20:36:16 GMT+1 from Cursor (2.1.50)_

---

**User**

Please generate a TIA Portal V19 Function for a 3-steep regulator which controls a valve for adding an ingredient to a medium

---

**Cursor**

Here’s a compact SCL (Structured Control Language) Function Block for TIA Portal V19 implementing a 3-step regulator (open/close pulses to a valve) suitable for dosing an ingredient into a medium. It includes anti-windup and deadband. Adjust constants to your process.

```scl
FUNCTION_BLOCK FB_ThreeStepRegulator
{ S7_Optimized_Access := 'TRUE' }
VAR_INPUT
    Setpoint      : REAL;     // Desired value
    ProcessValue  : REAL;     // Measured value
    Kp            : REAL := 0.5;   // Proportional gain
    Ki            : REAL := 0.05;  // Integral gain (per second)
    Deadband      : REAL := 0.2;   // No action range (engineering units)
    MaxPos        : REAL := 100.0; // Max open percent
    MinPos        : REAL := 0.0;   // Min close percent
    T_Impulse     : TIME := T#1S;  // Pulse width for open/close
    T_MinOff      : TIME := T#500MS; // Min off-time between pulses
    Enable        : BOOL := TRUE;
END_VAR
VAR_OUTPUT
    ValveOpenCmd  : BOOL;     // Pulse to open valve
    ValveCloseCmd : BOOL;     // Pulse to close valve
    PosEstimate   : REAL;     // Estimated valve position (0..100)
    Error         : REAL;     // Current control error
END_VAR
VAR
    integ         : REAL;
    lastCycleTime : TIME := T#0MS;
    tOpen         : TON;
    tClose        : TON;
    tGap          : TON;
END_VAR

// --- Compute cycle time (dt) ---
IF __FIRST_SCAN THEN
    lastCycleTime := T#0MS;
END_IF;

VAR_TEMP
    dt : REAL;
END_VAR

dt := REAL_TO_TIME(TIME_TCK() - TIME_TCK()); // placeholder, replace with your dt source if available
// If you have a known cycle time, set dt := 0.05 for 50 ms task, etc.

// --- Controller core ---
Error := Setpoint - ProcessValue;

// Deadband handling
IF ABS(Error) <= Deadband THEN
    Error := 0.0;
END_IF;

// Integrator with simple anti-windup (clamp to output limits)
IF Enable THEN
    integ := integ + Ki * Error * dt;
    // Clamp integral contribution to avoid pushing output beyond limits
    IF integ > (MaxPos - MinPos) THEN
        integ := (MaxPos - MinPos);
    ELSIF integ < -(MaxPos - MinPos) THEN
        integ := -(MaxPos - MinPos);
    END_IF;
ELSE
    integ := 0.0;
END_IF;

// Compute control effort (position estimate change request)
VAR_TEMP
    u : REAL;
END_VAR
u := Kp * Error + integ;

// Convert effort to desired position estimate
PosEstimate := PosEstimate + u;
IF PosEstimate > MaxPos THEN
    PosEstimate := MaxPos;
ELSIF PosEstimate < MinPos THEN
    PosEstimate := MinPos;
END_IF;

// --- 3-step pulse generation ---
// Only pulse when outside deadband and respecting minimum off-time
// Use TON timers for pulse width and inter-pulse gap
IF Enable THEN
    // Determine direction
    IF (Error > Deadband) AND NOT tGap.Q THEN
        // Need to open
        tOpen(IN := TRUE, PT := T_Impulse);
        tClose(IN := FALSE, PT := T_Impulse);
        ValveOpenCmd := tOpen.Q;
        ValveCloseCmd := FALSE;
        IF tOpen.Q THEN
            tGap(IN := TRUE, PT := T_MinOff);
        END_IF;
    ELSIF (Error < -Deadband) AND NOT tGap.Q THEN
        // Need to close
        tClose(IN := TRUE, PT := T_Impulse);
        tOpen(IN := FALSE, PT := T_Impulse);
        ValveCloseCmd := tClose.Q;
        ValveOpenCmd := FALSE;
        IF tClose.Q THEN
            tGap(IN := TRUE, PT := T_MinOff);
        END_IF;
    ELSE
        // No action
        tOpen(IN := FALSE, PT := T_Impulse);
        tClose(IN := FALSE, PT := T_Impulse);
        ValveOpenCmd := FALSE;
        ValveCloseCmd := FALSE;
    END_IF;
ELSE
    tOpen(IN := FALSE, PT := T_Impulse);
    tClose(IN := FALSE, PT := T_Impulse);
    tGap(IN := FALSE, PT := T_MinOff);
    ValveOpenCmd := FALSE;
    ValveCloseCmd := FALSE;
END_IF;

// Update gap timer (runs after a pulse)
tGap(IN := tGap.IN, PT := T_MinOff);
```

Notes and integration tips:
- Replace the `dt` placeholder with your OB cycle time (e.g., set `dt := 0.05;` for 50 ms task) or compute from `OBx_PREV_CYCLE`.
- `ValveOpenCmd`/`ValveCloseCmd` are pulses; wire them to digital outputs via an instance DB.
- `PosEstimate` is an internal estimate; if you have a position feedback, drive `PosEstimate` from it and reduce Ki.
- Tune `Deadband`, `Kp`, `Ki`, `T_Impulse`, and `T_MinOff` to your process.

```plaintext
FUNCTION_BLOCK FB_ThreeStepRegulator
{ S7_Optimized_Access := 'TRUE' }
VAR_INPUT
    Setpoint      : REAL;     // Desired value
    ProcessValue  : REAL;     // Measured value
    Kp            : REAL := 0.5;   // Proportional gain
    Ki            : REAL := 0.05;  // Integral gain (per second)
    Deadband      : REAL := 0.2;   // No action range (engineering units)
    MaxPos        : REAL := 100.0; // Max open percent
    MinPos        : REAL := 0.0;   // Min close percent
    T_Impulse     : TIME := T#1S;  // Pulse width for open/close
    T_MinOff      : TIME := T#500MS; // Min off-time between pulses
    Enable        : BOOL := TRUE;
END_VAR
VAR_OUTPUT
    ValveOpenCmd  : BOOL;     // Pulse to open valve
    ValveCloseCmd : BOOL;     // Pulse to close valve
    PosEstimate   : REAL;     // Estimated valve position (0..100)
    Error         : REAL;     // Current control error
END_VAR
VAR
    integ         : REAL;
    lastCycleTime : TIME := T#0MS;
    tOpen         : TON;
    tClose        : TON;
    tGap          : TON;
END_VAR

// --- Compute cycle time (dt) ---
IF __FIRST_SCAN THEN
    lastCycleTime := T#0MS;
END_IF;

VAR_TEMP
    dt : REAL;
END_VAR

dt := REAL_TO_TIME(TIME_TCK() - TIME_TCK()); // placeholder, replace with your dt source if available
// If you have a known cycle time, set dt := 0.05 for 50 ms task, etc.

// --- Controller core ---
Error := Setpoint - ProcessValue;

// Deadband handling
IF ABS(Error) <= Deadband THEN
    Error := 0.0;
END_IF;

// Integrator with simple anti-windup (clamp to output limits)
IF Enable THEN
    integ := integ + Ki * Error * dt;
    // Clamp integral contribution to avoid pushing output beyond limits
    IF integ > (MaxPos - MinPos) THEN
        integ := (MaxPos - MinPos);
    ELSIF integ < -(MaxPos - MinPos) THEN
        integ := -(MaxPos - MinPos);
    END_IF;
ELSE
    integ := 0.0;
END_IF;

// Compute control effort (position estimate change request)
VAR_TEMP
    u : REAL;
END_VAR
u := Kp * Error + integ;

// Convert effort to desired position estimate
PosEstimate := PosEstimate + u;
IF PosEstimate > MaxPos THEN
    PosEstimate := MaxPos;
ELSIF PosEstimate < MinPos THEN
    PosEstimate := MinPos;
END_IF;

// --- 3-step pulse generation ---
// Only pulse when outside deadband and respecting minimum off-time
// Use TON timers for pulse width and inter-pulse gap
IF Enable THEN
    // Determine direction
    IF (Error > Deadband) AND NOT tGap.Q THEN
        // Need to open
        tOpen(IN := TRUE, PT := T_Impulse);
        tClose(IN := FALSE, PT := T_Impulse);
        ValveOpenCmd := tOpen.Q;
        ValveCloseCmd := FALSE;
        IF tOpen.Q THEN
            tGap(IN := TRUE, PT := T_MinOff);
        END_IF;
    ELSIF (Error < -Deadband) AND NOT tGap.Q THEN
        // Need to close
        tClose(IN := TRUE, PT := T_Impulse);
        tOpen(IN := FALSE, PT := T_Impulse);
        ValveCloseCmd := tClose.Q;
        ValveOpenCmd := FALSE;
        IF tClose.Q THEN
            tGap(IN := TRUE, PT := T_MinOff);
        END_IF;
    ELSE
        // No action
        tOpen(IN := FALSE, PT := T_Impulse);
        tClose(IN := FALSE, PT := T_Impulse);
        ValveOpenCmd := FALSE;
        ValveCloseCmd := FALSE;
    END_IF;
ELSE
    tOpen(IN := FALSE, PT := T_Impulse);
    tClose(IN := FALSE, PT := T_Impulse);
    tGap(IN := FALSE, PT := T_MinOff);
    ValveOpenCmd := FALSE;
    ValveCloseCmd := FALSE;
END_IF;

// Update gap timer (runs after a pulse)
tGap(IN := tGap.IN, PT := T_MinOff);
```

