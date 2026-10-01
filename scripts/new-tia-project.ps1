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
    # TIA Portal version, e.g. V17, V18, V19, V20
    [string]$TiaVersion    = "V18",
    [switch]$WithUI
)

$dll = "C:\Program Files\Siemens\Automation\Portal $TiaVersion\PublicAPI\$TiaVersion\Siemens.Engineering.dll"
if (-not (Test-Path $dll)) { throw "Siemens.Engineering.dll not found: $dll" }
Add-Type -Path $dll

$mode = if ($WithUI) { [Siemens.Engineering.TiaPortalMode]::WithUserInterface } else { [Siemens.Engineering.TiaPortalMode]::WithoutUserInterface }
$tia = [Siemens.Engineering.TiaPortal]::Start($mode)   # use ::Open for an already running instance

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
