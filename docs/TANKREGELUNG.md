# Tankregelung S7-1500 mit WinCC Unified V21 und PLCSIM Advanced

## Ziel

Dieses Paket beschreibt eine einfache Füllstandsregelung für einen Tank auf einer Siemens S7-1500 CPU im TIA Portal V21. Die Regelung kann mit PLCSIM Advanced getestet und über eine einfache WinCC Unified V21 Visualisierung bedient werden.

## Funktionsumfang

- Betriebsarten: Aus, Hand, Automatik
- Analoger Füllstand in Prozent
- Pumpe/Füllventil als Stellglied zum Befüllen
- Ablaufventil als Handfunktion zum Entleeren
- Zwei-Punkt-Regelung mit Hysterese
- Grenzwertüberwachung für sehr niedrigen und sehr hohen Füllstand
- Störquittierung
- Simulationsbaustein für PLCSIM Advanced ohne echte Peripherie
- HMI-Schnittstelle über einen globalen Datenbaustein

## Empfohlene Bausteinstruktur

| Baustein | Typ | Aufgabe |
|---|---|---|
| OB1 | OB | Zyklischer Aufruf von `FB_TankControl` und optional `FB_TankSim` |
| FB_TankControl | FB | Betriebsarten, Verriegelungen, Grenzwerte, Füllstandsregelung |
| FB_TankSim | FB | Einfaches Tankmodell für PLCSIM Advanced |
| DB_TankControl | Instanz-DB | Instanzdaten für `FB_TankControl` |
| DB_TankSim | Instanz-DB | Instanzdaten für `FB_TankSim` |
| DB_HMI_Tank | Global-DB | Bedien- und Anzeigedaten für WinCC Unified |

## Symbolische HMI-Tags

| HMI-Name | PLC-Variable | Datentyp | Richtung |
|---|---|---|---|
| `Tank_LevelPct` | `DB_HMI_Tank.LevelPct` | Real | PLC -> HMI |
| `Tank_SetpointPct` | `DB_HMI_Tank.SetpointPct` | Real | HMI -> PLC |
| `Tank_HysteresisPct` | `DB_HMI_Tank.HysteresisPct` | Real | HMI -> PLC |
| `Tank_Mode` | `DB_HMI_Tank.Mode` | Int | HMI -> PLC |
| `Tank_StartAuto` | `DB_HMI_Tank.StartAuto` | Bool | HMI -> PLC |
| `Tank_Stop` | `DB_HMI_Tank.Stop` | Bool | HMI -> PLC |
| `Tank_ManualFill` | `DB_HMI_Tank.ManualFill` | Bool | HMI -> PLC |
| `Tank_ManualDrain` | `DB_HMI_Tank.ManualDrain` | Bool | HMI -> PLC |
| `Tank_ResetFault` | `DB_HMI_Tank.ResetFault` | Bool | HMI -> PLC |
| `Tank_FillValveCmd` | `DB_HMI_Tank.FillValveCmd` | Bool | PLC -> HMI |
| `Tank_DrainValveCmd` | `DB_HMI_Tank.DrainValveCmd` | Bool | PLC -> HMI |
| `Tank_AutoActive` | `DB_HMI_Tank.AutoActive` | Bool | PLC -> HMI |
| `Tank_Fault` | `DB_HMI_Tank.Fault` | Bool | PLC -> HMI |
| `Tank_AlarmLowLow` | `DB_HMI_Tank.AlarmLowLow` | Bool | PLC -> HMI |
| `Tank_AlarmHighHigh` | `DB_HMI_Tank.AlarmHighHigh` | Bool | PLC -> HMI |
| `Tank_StatusText` | `DB_HMI_Tank.StatusText` | String[80] | PLC -> HMI |

## Betriebsarten

| Wert | Betriebsart |
|---:|---|
| 0 | Aus |
| 1 | Hand |
| 2 | Automatik |

## Automatik-Regelverhalten

Die Regelung arbeitet bewusst einfach als Zweipunktregler:

- Wenn `LevelPct <= SetpointPct - HysteresisPct`, wird Befüllen eingeschaltet.
- Wenn `LevelPct >= SetpointPct + HysteresisPct`, wird Befüllen ausgeschaltet.
- Bei `LevelPct >= HighHighPct` wird eine Störung gesetzt.
- Bei `LevelPct <= LowLowPct` wird eine Warnung gesetzt, aber die Automatik darf weiter füllen.

Beispiel:

- Sollwert: 60 %
- Hysterese: 3 %
- Füllen EIN bei <= 57 %
- Füllen AUS bei >= 63 %

## WinCC Unified Bildvorschlag

Erstelle ein Bild `Tank_Overview`.

### Bedienbereich

- Sollwert-Eingabefeld: `Tank_SetpointPct`
- Hysterese-Eingabefeld: `Tank_HysteresisPct`
- Betriebsart-Auswahl: `Tank_Mode`
- Taster `Start Auto`: setzt `Tank_StartAuto`
- Taster `Stop`: setzt `Tank_Stop`
- Taster `Reset`: setzt `Tank_ResetFault`
- Taster `Füllen Hand`: setzt `Tank_ManualFill`
- Taster `Entleeren Hand`: setzt `Tank_ManualDrain`

### Anzeigen

- Tankgrafik oder Balkenanzeige mit `Tank_LevelPct`, Bereich 0 bis 100 %
- Numerische Anzeige `Tank_LevelPct`
- Statusanzeige `Tank_StatusText`
- Symbol für Füllventil: sichtbar/grün bei `Tank_FillValveCmd`
- Symbol für Ablaufventil: sichtbar/grün bei `Tank_DrainValveCmd`
- Alarmbanner bei `Tank_Fault`
- Warnsymbol bei `Tank_AlarmLowLow`
- Warnsymbol bei `Tank_AlarmHighHigh`

### Dynamisierung

- Tankfüllstand: Höhe/Füllgrad an `Tank_LevelPct` koppeln.
- Ventilfarbe:
  - Grau bei `FALSE`
  - Grün bei `TRUE`
- Störtext:
  - Rot sichtbar bei `Tank_Fault = TRUE`

## PLCSIM Advanced Testablauf

1. S7-1500 CPU in TIA Portal V21 anlegen.
2. Bausteine aus `Tankregelung_SCL_Quellen.scl` in TIA Portal anlegen oder importieren.
3. Global-DB `DB_HMI_Tank` anlegen.
4. OB1-Aufrufe gemäß Beispiel einfügen.
5. Projekt übersetzen.
6. PLCSIM Advanced Instanz mit passendem CPU-Typ starten.
7. PLC laden.
8. Beobachtungstabelle für `DB_HMI_Tank` erstellen.
9. `Mode = 2`, `StartAuto = TRUE`, danach wieder `FALSE` setzen.
10. Prüfen, ob die Simulation den Füllstand bis zum Sollwertbereich anhebt.
11. `SetpointPct` ändern, z. B. von 60 auf 75 %.
12. Prüfen, ob die Regelung nachführt.
13. `LevelPct` über Simulation oder DB-Wert auf > 95 % bringen.
14. Prüfen, ob `Fault = TRUE` und `FillValveCmd = FALSE`.
15. Füllstand unter 90 % bringen, `ResetFault = TRUE`, danach wieder `FALSE`.

## Hinweise für ein echtes Projekt

- Für reale Analogwerte muss der Eingangswert skaliert werden, z. B. 4-20 mA auf 0-100 %.
- Ausgänge sollten bei echter Hardware nicht direkt aus HMI-Daten gesetzt werden, sondern über geprüfte Prozesslogik.
- Für Pumpen sollten Rückmeldungen, Motorschutz, Laufzeitüberwachung und Trockenlaufschutz ergänzt werden.
- Für Prozessanlagen sind Sicherheitsfunktionen nicht in der Standard-PLC-Logik zu ersetzen.``
