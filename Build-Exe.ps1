<#
    Build-Exe.ps1
    Compiles TinyBuilderPlus.ps1 (+ its Modules/Config folders) into a
    single-file TinyBuilderPlus.exe using the ps2exe module.

    Run this ON WINDOWS, from inside the TinyBuilderPlus folder:
        .\Build-Exe.ps1

    Notes:
    - ps2exe bundles the SCRIPT, not the Modules/Config folders. Those must
      ship alongside the .exe (same folder), which this script arranges in
      .\dist automatically. The GUI script already resolves paths relative
      to $PSScriptRoot / the exe's own folder, so this "just works".
    - -requireAdmin embeds a UAC manifest, since DISM/registry-hive edits
      need elevation.
#>

param(
    [string]$OutputName = "TinyBuilderPlus.exe",
    [string]$IconPath   = ""
)

$ScriptRoot = $PSScriptRoot
$DistDir    = Join-Path $ScriptRoot "dist"

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe module (one-time)..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$exeParams = @{
    InputFile    = Join-Path $ScriptRoot "TinyBuilderPlus.ps1"
    OutputFile   = Join-Path $DistDir $OutputName
    noConsole    = $true
    requireAdmin = $true
    title        = "TinyBuilder+"
    version      = "1.0.0.0"
    company      = "You"
    product      = "TinyBuilder+"
}
if ($IconPath -and (Test-Path $IconPath)) { $exeParams["iconFile"] = $IconPath }

Write-Host "Compiling TinyBuilderPlus.ps1 -> $($exeParams.OutputFile) ..."
Invoke-ps2exe @exeParams

Write-Host "Copying Modules/ and Config/ next to the exe (required at runtime)..."
Copy-Item -Path (Join-Path $ScriptRoot "Modules") -Destination $DistDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptRoot "Config")  -Destination $DistDir -Recurse -Force

Write-Host ""
Write-Host "Done. Distribute the entire 'dist' folder (exe + Modules + Config) as a unit —"
Write-Host "the exe expects Modules\ and Config\ to sit next to it."
