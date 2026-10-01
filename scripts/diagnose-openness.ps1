# Diagnostics for TIA Openness DLL loading. Run in Windows PowerShell 5.1 (not PowerShell 7).
param([string]$TiaVersion = "V21")

$apiDir = "C:\Program Files\Siemens\Automation\Portal $TiaVersion\PublicAPI\$TiaVersion\net48"
Write-Host "PowerShell: $($PSVersionTable.PSVersion) / CLR: $($PSVersionTable.CLRVersion)"
Write-Host "--- DLLs in $apiDir ---"
Get-ChildItem $apiDir -Filter *.dll | Select-Object -ExpandProperty Name

# Resolve dependencies from the API folder
$null = Register-ObjectEvent -InputObject ([AppDomain]::CurrentDomain) -EventName AssemblyResolve -Action {
    $n = ($EventArgs.Name -split ',')[0]
    $p = Join-Path $using:apiDir "$n.dll"
    if (Test-Path $p) { [Reflection.Assembly]::LoadFrom($p) }
} -ErrorAction SilentlyContinue

foreach ($name in "Siemens.Engineering.Base.dll", "Siemens.Engineering.Step7.dll") {
    $path = Join-Path $apiDir $name
    Write-Host "`n--- Loading $name ---"
    try {
        $asm = [Reflection.Assembly]::LoadFrom($path)
        Write-Host "OK: $($asm.FullName)"
        $null = $asm.GetTypes()
    } catch [System.Reflection.ReflectionTypeLoadException] {
        Write-Host "ReflectionTypeLoadException - LoaderExceptions:"
        $_.Exception.LoaderExceptions | Where-Object { $_ } | ForEach-Object { $_.Message } | Select-Object -Unique
    } catch { Write-Host "ERROR: $($_.Exception.Message)" }
}

Write-Host "`n--- Static methods of Siemens.Engineering.TiaPortal ---"
$t = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
    try { $_.GetTypes() } catch { $_.Exception.Types | Where-Object { $_ } }
} | Where-Object { $_.FullName -eq "Siemens.Engineering.TiaPortal" } | Select-Object -First 1
if ($t) {
    $t.GetMethods("Public,Static") | ForEach-Object { $_.ToString() }
    Write-Host "Assembly: $($t.Assembly.Location)"
} else { Write-Host "Type Siemens.Engineering.TiaPortal not found" }
