# Adds a WinCC Unified PC runtime to the open TIA Portal project (e.g. CPU007), creates a start screen,
# an HMI connection to the PLC, a tag for M100.7 (100 ms) and a small circle (~5 mm) in the top left
# corner whose background colour follows the tag: false = dark grey, true = light green.
#
# Run in Windows PowerShell 5.1 with TIA Portal V21 already open and the project loaded:
#   .\add-wincc-unified.ps1
# Every step reports OK / FEHLER separately; on an API error the available members are printed
# so the script can be adjusted to the exact V21 API (it has not been tested against V21).
param(
    [string]$HmiName        = "HMI_RT_1",
    [string]$HmiIp          = "192.168.0.51",
    [string]$SubnetMask     = "255.255.255.0",
    # Leave empty to search the hardware catalog for "WinCC Unified PC" entries
    [string]$HmiTypeIdentifier = "",
    [string]$PlcName        = "PLC_1",
    [string]$PlcIp          = "192.168.0.18",
    [string]$ConnectionName = "HMI_Connection_1",
    [string]$ConnectionDriver = "SIMATIC S7-1500",
    [string]$ScreenName     = "Startbild",
    [string]$TagName        = "M100_7",
    [string]$TagAddress     = "%M100.7",
    [int]$CycleMs           = 100,
    [int]$CircleDiameterPx  = 19,    # ~5 mm at 96 dpi
    [string]$TiaVersion     = "V21"
)

$ErrorActionPreference = "Stop"

# ---------- load Openness DLLs (see new-tia-project.ps1) ----------
$portalRoot = "C:\Program Files\Siemens\Automation\Portal $TiaVersion"
$apiDir     = Join-Path $portalRoot "PublicAPI\$TiaVersion\net48"
$dlls = @()
foreach ($n in "Siemens.Engineering.Contract", "Siemens.Engineering.ClientAdapter.Interfaces") {
    $p = Join-Path $portalRoot "Bin\PublicAPI\$n.dll"; if (Test-Path $p) { $dlls += $p }
}
foreach ($n in "Siemens.Engineering.Base.dll", "Siemens.Engineering.Step7.dll", "Siemens.Engineering.WinCCUnified.dll") {
    $p = Join-Path $apiDir $n; if (Test-Path $p) { $dlls += $p } else { Write-Warning "DLL not found: $p" }
}
foreach ($d in $dlls) { Write-Host "Loading Openness DLL: $d"; Add-Type -Path $d }

# ---------- helpers ----------
function Show-Api($obj, [string]$title) {
    Write-Host "--- API: $title ($($obj.GetType().FullName)) ---" -ForegroundColor Yellow
    $obj.GetType().GetMembers("Public,Instance") | Where-Object { $_.Name -notmatch '^(get_|set_|add_|remove_)' -or $_.MemberType -eq 'Property' } |
        ForEach-Object { "  " + $_.ToString() } | Select-Object -Unique
}

function Step([string]$name, [scriptblock]$body) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    try { & $body; Write-Host "OK: $name" -ForegroundColor Green; return $true }
    catch {
        Write-Host "FEHLER: $name" -ForegroundColor Red
        $e = $_.Exception
        while ($e) { Write-Host "  [$($e.GetType().Name)] $($e.Message)" -ForegroundColor Red; $e = $e.InnerException }
        return $false
    }
}

function Get-TiaService($item, [Type]$t) { $item.GetType().GetMethod("GetService").MakeGenericMethod($t).Invoke($item, @()) }

function Find-Type([string]$shortName) {
    [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
        try { $_.GetTypes() } catch { $_.Exception.Types | Where-Object { $_ } }
    } | Where-Object { $_.Name -eq $shortName } | Select-Object -First 1
}

function Create-Generic($composition, [Type]$t, [string]$name) {
    $m = $composition.GetType().GetMethods() | Where-Object { $_.Name -eq "Create" -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    if (-not $m) { Show-Api $composition "composition"; throw "No generic Create<T>(name) on $($composition.GetType().Name)" }
    $m.MakeGenericMethod($t).Invoke($composition, @($name))
}

# ---------- attach to running TIA Portal ----------
$procs = @([Siemens.Engineering.TiaPortal]::GetProcesses())
if ($procs.Count -eq 0) { throw "Kein laufendes TIA Portal gefunden. Starte TIA Portal $TiaVersion und oeffne das Projekt." }
$tia = $procs[0].Attach()
$project = $tia.Projects | Select-Object -First 1
if (-not $project) { throw "Im laufenden TIA Portal ist kein Projekt geoeffnet." }
Write-Host "Projekt: $($project.Name)"

$script:hmiDevice = $null
$script:hmi = $null

# ---------- 1. device ----------
Step "WinCC Unified PC Runtime hinzufuegen ($HmiName)" {
    $typeId = $HmiTypeIdentifier
    if (-not $typeId) {
        $found = @($tia.HardwareCatalog.Find("WinCC Unified"))
        Write-Host "Katalogeintraege mit 'WinCC Unified': $($found.Count)"
        $found | ForEach-Object { Write-Host ("  {0}  |  {1}" -f $_.TypeIdentifier, $_.Name) }
        $pc = @($found | Where-Object { ($_.TypeIdentifier + " " + $_.Name) -match "PC" -and ($_.TypeIdentifier + " " + $_.Name) -match "Runtime|RT" })
        if ($pc.Count -ne 1) { throw "Katalogeintrag nicht eindeutig. Waehle einen TypeIdentifier aus der Liste oben und starte mit -HmiTypeIdentifier '<wert>'." }
        $typeId = $pc[0].TypeIdentifier
    }
    Write-Host "TypeIdentifier: $typeId"
    $script:hmiDevice = $project.Devices.CreateWithItem($typeId, $HmiName, $HmiName)
} | Out-Null
if (-not $script:hmiDevice) { Write-Host "`nAbbruch: Geraet konnte nicht angelegt werden." -ForegroundColor Red; return }

# ---------- 2. IP address ----------
Step "IP-Adresse $HmiIp setzen" {
    $stack = [System.Collections.Generic.Stack[Siemens.Engineering.HW.DeviceItem]]::new()
    foreach ($i in $script:hmiDevice.DeviceItems) { $stack.Push($i) }
    $done = $false
    while ($stack.Count -gt 0 -and -not $done) {
        $item = $stack.Pop()
        $ni = Get-TiaService $item ([Siemens.Engineering.HW.Features.NetworkInterface])
        if ($null -ne $ni -and $ni.Nodes.Count -gt 0) {
            $ni.Nodes[0].SetAttribute("Address", $HmiIp); $ni.Nodes[0].SetAttribute("SubnetMask", $SubnetMask); $done = $true
        } else { foreach ($s in $item.DeviceItems) { $stack.Push($s) } }
    }
    if (-not $done) { throw "Keine Netzwerkschnittstelle am PC-Geraet gefunden. IP bitte manuell setzen (ggf. fehlt ein Kommunikationsmodul/Ethernet-Schnittstelle)." }
} | Out-Null

# ---------- 3. HMI software ----------
Step "HMI-Software ermitteln" {
    $stack = [System.Collections.Generic.Stack[Siemens.Engineering.HW.DeviceItem]]::new()
    foreach ($i in $script:hmiDevice.DeviceItems) { $stack.Push($i) }
    while ($stack.Count -gt 0 -and -not $script:hmi) {
        $item = $stack.Pop()
        $sc = Get-TiaService $item ([Siemens.Engineering.HW.Features.SoftwareContainer])
        if ($null -ne $sc -and $sc.Software -and $sc.Software.GetType().Name -match "Hmi") { $script:hmi = $sc.Software }
        else { foreach ($s in $item.DeviceItems) { $stack.Push($s) } }
    }
    if (-not $script:hmi) { throw "Keine HmiSoftware im Geraet gefunden." }
    Write-Host "HMI-Software: $($script:hmi.GetType().FullName)"
} | Out-Null
if (-not $script:hmi) { return }
$hmi = $script:hmi

# ---------- 4. start screen ----------
$screen = $null
Step "Startbild '$ScreenName' erzeugen" {
    $script:screen = $hmi.Screens.Create($ScreenName)
    try { $hmi.SetAttribute("StartScreen", $ScreenName) }
    catch { Write-Warning "Startbild konnte nicht als Start-Screen gesetzt werden (Attribut 'StartScreen'): $($_.Exception.Message). Bitte in den Runtime-Einstellungen pruefen." }
} | Out-Null
$screen = $script:screen

# ---------- 5. HMI connection ----------
Step "HMI-Verbindung '$ConnectionName' zu $PlcName ($PlcIp)" {
    try { $script:conn = $hmi.Connections.Create($ConnectionName, $ConnectionDriver, $PlcName) }
    catch {
        Show-Api $hmi.Connections "Connections"
        $hmi.Connections.GetType().GetMethods() | Where-Object Name -eq "Create" | ForEach-Object { Write-Host ("  Create overload: " + $_.ToString()) }
        throw
    }
    try { $script:conn.SetAttribute("Node", $PlcIp) } catch { Write-Warning "Verbindungsattribut 'Node' nicht gesetzt: $($_.Exception.Message)" }
} | Out-Null

# ---------- 6. tag M100.7 ----------
Step "Variable $TagName ($TagAddress, $CycleMs ms)" {
    $table = $hmi.TagTables | Select-Object -First 1
    if (-not $table) { $table = $hmi.TagTables.Create("Default tag table") }
    $script:tag = $table.Tags.Create($TagName)
    foreach ($kv in @(@("DataType","Bool"), @("Connection",$ConnectionName), @("PlcTag",$TagAddress), @("AcquisitionCycle","T100ms"))) {
        try { $script:tag.SetAttribute($kv[0], $kv[1]) } catch { Write-Warning "Tag-Attribut $($kv[0]) nicht gesetzt: $($_.Exception.Message)" }
    }
} | Out-Null

# ---------- 7. circle + dynamization ----------
Step "Kreis (${CircleDiameterPx}px ~ 5 mm) oben links" {
    if (-not $screen) { throw "Kein Startbild vorhanden." }
    $t = Find-Type "HmiCircle"
    if (-not $t) { Show-Api $screen "Screen"; throw "Typ HmiCircle nicht gefunden." }
    $c = Create-Generic $screen.ScreenItems $t "Kreis_M100_7"
    foreach ($kv in @(@("Left",5), @("Top",5), @("Width",$CircleDiameterPx), @("Height",$CircleDiameterPx))) {
        $c.SetAttribute($kv[0], $kv[1])
    }
    try { $c.SetAttribute("BackColor", [System.Drawing.Color]::FromArgb(64,64,64)) }
    catch { Write-Warning "Anfangsfarbe nicht gesetzt: $($_.Exception.Message)" }
    $script:circle = $c
} | Out-Null

Step "Hintergrundfarbe an $TagName koppeln (false = dunkelgrau, true = hellgruen)" {
    if (-not $script:circle) { throw "Kreis nicht vorhanden." }
    $colors = [ordered]@{ "0" = @(64,64,64); "1" = @(144,238,144) }   # false -> dunkelgrau, true -> hellgruen

    function Set-ColorAttr($obj, [string]$attr, [int[]]$rgb) {
        # The exact value format of colour attributes differs between versions: try the likely ones.
        $argb = [System.Drawing.Color]::FromArgb(255, $rgb[0], $rgb[1], $rgb[2])
        $uint = [uint32](([uint32]255 -shl 24) -bor ([uint32]$rgb[0] -shl 16) -bor ([uint32]$rgb[1] -shl 8) -bor [uint32]$rgb[2])
        $hex  = "#{0:X2}{1:X2}{2:X2}" -f $rgb[0], $rgb[1], $rgb[2]
        $last = $null
        foreach ($v in @($argb, $uint, $hex, ("{0},{1},{2}" -f $rgb[0], $rgb[1], $rgb[2]))) {
            try { $obj.SetAttribute($attr, $v); Write-Host "  $attr = $v ($($v.GetType().Name))"; return } catch { $last = $_ }
        }
        throw $last
    }

    # Candidate dynamization types, most specific first. The first one that can be created AND configured wins.
    $names = "AppearanceDynamization", "TagDynamization", "ResourceListDynamization"
    $configured = $false
    foreach ($n in $names) {
        $dynType = Find-Type $n
        if (-not $dynType) { Write-Host "Typ $n nicht vorhanden."; continue }
        Write-Host "Versuche Dynamisierungstyp: $($dynType.FullName)"
        try {
            $dyn = Create-Generic $script:circle.Dynamizations $dynType "BackColor"
            Show-Api $dyn "Dynamisierung $n"
            $dyn.SetAttribute("Tag", $TagName)
            # Range/appearance list: look for a composition member that can create entries
            $coll = $dyn.GetType().GetProperties() | Where-Object { $_.Name -match "Appearances|Ranges|Entries|Mappings|Items" } | Select-Object -First 1
            if ($coll) {
                $list = $coll.GetValue($dyn)
                Show-Api $list "Eintragsliste $($coll.Name)"
                foreach ($k in $colors.Keys) {
                    $entry = $list.Create()
                    foreach ($a in "RangeFrom","LowerBound","Value","From") { try { $entry.SetAttribute($a, [int]$k); break } catch { } }
                    foreach ($a in "RangeTo","UpperBound","To") { try { $entry.SetAttribute($a, [int]$k) } catch { } }
                    Set-ColorAttr $entry "BackColor" $colors[$k]
                }
                $configured = $true; break
            } else { Write-Warning "Typ $n hat keine Eintragsliste fuer die Farbzuordnung." }
        } catch {
            Write-Warning "$n fehlgeschlagen: $($_.Exception.Message)"
            try { $script:circle.Dynamizations | Where-Object { $_.Name -eq "BackColor" } | ForEach-Object { $_.Delete() } } catch { }
        }
    }

    if (-not $configured) {
        # Fallback: script-based dynamization (JavaScript expression evaluated on tag change)
        $st = Find-Type "ScriptDynamization"
        if (-not $st) { Show-Api $script:circle.Dynamizations "Dynamizations"; throw "Keine Dynamisierung konfigurierbar (Details siehe API-Ausgabe oben)." }
        $dyn = Create-Generic $script:circle.Dynamizations $st "BackColor"
        Show-Api $dyn "ScriptDynamization"
        $dyn.SetAttribute("ScriptCode", "export function BackColor_Dynamization(item) { return Tags.Read('$TagName') ? 'rgb(144,238,144)' : 'rgb(64,64,64)'; }")
        Write-Warning "Farbzuordnung per Skript-Dynamisierung gesetzt (Fallback)."
    }
} | Out-Null

try { $project.Save(); Write-Host "`nProjekt gespeichert." } catch { Write-Warning "Speichern fehlgeschlagen: $($_.Exception.Message)" }
Write-Host "Fertig. Pruefe jeden Schritt oben (OK/FEHLER)."
