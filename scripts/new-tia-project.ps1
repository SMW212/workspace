# Creates a TIA Portal project with an S7-1516 CPU via TIA Openness.
# Run on the engineering PC (Windows) with TIA Portal + Openness installed and
# the user being member of the local group "Siemens TIA Openness".
param(
    [string]$ProjectName   = "CPU007",
    [string]$ProjectDir    = (Join-Path $env:USERPROFILE "Documents\Automation"),
    [string]$DeviceName    = "PLC_1",
    [string]$IpAddress     = "192.168.0.18",
    [string]$SubnetMask    = "255.255.255.0",
    # CPU 1516-3 PN/DP; adjust order number / firmware to the real hardware.
    [string]$TypeIdentifier = "OrderNumber:6ES7 516-3AN02-0AB0/V2.9",
    # TIA Portal version, e.g. V19, V20, V21
    [string]$TiaVersion    = "V21",
    [switch]$WithUI
)

$apiDir = "C:\Program Files\Siemens\Automation\Portal $TiaVersion\PublicAPI\$TiaVersion\net48"
# Dependencies (e.g. Siemens.Engineering.Contract.dll) do not necessarily live in the net48 folder,
# so resolve missing assemblies by searching the whole TIA Portal installation folder once.
$portalRoot = "C:\Program Files\Siemens\Automation\Portal $TiaVersion"
$script:dllIndex = @{}
Get-ChildItem -Path $portalRoot -Filter "Siemens.Engineering*.dll" -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { if (-not $script:dllIndex.ContainsKey($_.BaseName)) { $script:dllIndex[$_.BaseName] = $_.FullName } }
[AppDomain]::CurrentDomain.add_AssemblyResolve([ResolveEventHandler]{
    param($sender, $e)
    $n = ($e.Name -split ',')[0]
    if ($script:dllIndex.ContainsKey($n)) {
        Write-Host "Resolved dependency: $($script:dllIndex[$n])"
        return [Reflection.Assembly]::LoadFrom($script:dllIndex[$n])
    }
    return $null
})

# V21 splits the API into several DLLs (Siemens.Engineering.Base.dll, ...Step7.dll, ...);
# older versions ship a single Siemens.Engineering.dll.
$dlls = @()
# Dependencies live in Bin\PublicAPI; load them explicitly first
foreach ($name in "Siemens.Engineering.Contract", "Siemens.Engineering.ClientAdapter.Interfaces") {
    $dep = Join-Path $portalRoot "Bin\PublicAPI\$name.dll"
    if (Test-Path $dep) { $dlls += $dep } elseif ($script:dllIndex.ContainsKey($name)) { $dlls += $script:dllIndex[$name] }
}
foreach ($name in "Siemens.Engineering.Base.dll", "Siemens.Engineering.Step7.dll", "Siemens.Engineering.dll") {
    $path = Join-Path $apiDir $name
    if (Test-Path $path) { $dlls += $path }
}
if ($dlls.Count -eq 0) { throw "No Openness DLL found in: $apiDir" }
foreach ($dll in $dlls) {
    Write-Host "Loading Openness DLL: $dll"
    Add-Type -Path $dll
}

$mode = if ($WithUI) { [Siemens.Engineering.TiaPortalMode]::WithUserInterface } else { [Siemens.Engineering.TiaPortalMode]::WithoutUserInterface }
# V21 removed TiaPortal.Start(); a new instance is created via the constructor.
# Older versions use the static Start().
$tiaType = [Siemens.Engineering.TiaPortal]
if ($tiaType.GetMethods("Public,Static") | Where-Object Name -eq "Start") {
    $tia = [Siemens.Engineering.TiaPortal]::Start($mode)
} else {
    $tia = [Siemens.Engineering.TiaPortal]::new($mode)
}

try {
    if (-not (Test-Path $ProjectDir)) { New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null }
    $dirInfo = [System.IO.DirectoryInfo]::new($ProjectDir)

    $project = $tia.Projects.Create($dirInfo, $ProjectName)
    Write-Host "Project created: $($project.Path)"

    $device = $project.Devices.CreateWithItem($TypeIdentifier, $DeviceName, $DeviceName)
    Write-Host "CPU added: $DeviceName ($TypeIdentifier)"

    # Find the PROFINET interface of the CPU and set the IP address
    $stack = [System.Collections.Generic.Stack[Siemens.Engineering.HW.DeviceItem]]::new()
    foreach ($item in $device.DeviceItems) { $stack.Push($item) }

    $configured = $false
    while ($stack.Count -gt 0 -and -not $configured) {
        $item = $stack.Pop()
        $netIf = [Siemens.Engineering.HW.Features.NetworkInterface]
        $getNi = $item.GetType().GetMethod("GetService").MakeGenericMethod($netIf)
        $ni = $getNi.Invoke($item, @())
        if ($null -ne $ni -and $ni.Nodes.Count -gt 0) {
            $node = $ni.Nodes[0]
            $node.SetAttribute("Address", $IpAddress)
            $node.SetAttribute("SubnetMask", $SubnetMask)
            Write-Host "IP address set: $IpAddress / $SubnetMask"
            $configured = $true
        } else {
            foreach ($sub in $item.DeviceItems) { $stack.Push($sub) }
        }
    }
    if (-not $configured) { Write-Warning "No PROFINET interface found - IP address not set." }

    $project.Save()
    Write-Host "Project saved."
}
finally {
    if (-not $WithUI) { $tia.Dispose() }
}
