#Requires -RunAsAdministrator
<#
    TinyBuilderPlus.ps1
    A Tiny11-Builder-style Windows image customizer with NTLite-style
    software pre-install and update-slipstreaming, wrapped in a simple GUI.

    Run this directly with PowerShell, or compile it to TinyBuilderPlus.exe
    with Build-Exe.ps1.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
Import-Module (Join-Path $ScriptRoot "Modules\ImageHelpers.psm1") -Force
Import-Module (Join-Path $ScriptRoot "Modules\Debloat.psm1") -Force
Import-Module (Join-Path $ScriptRoot "Modules\SoftwareInjector.psm1") -Force
Import-Module (Join-Path $ScriptRoot "Modules\UpdateIntegrator.psm1") -Force

# ---------- Working paths ----------
$Work = Join-Path $env:TEMP "TinyBuilderPlus"
$ExtractDir = Join-Path $Work "Extracted"
$MountDir   = Join-Path $Work "Mount"
New-Item -ItemType Directory -Path $Work -Force | Out-Null

# ---------- Main window ----------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "TinyBuilder+"
$form.Size            = New-Object System.Drawing.Size(560, 520)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

function New-Label($text, $x, $y, $w = 500) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, 20)
    $form.Controls.Add($l); return $l
}
function New-TextBox($x, $y, $w = 350) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y); $t.Size = New-Object System.Drawing.Size($w, 22)
    $form.Controls.Add($t); return $t
}
function New-Button($text, $x, $y, $w = 90) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 25)
    $form.Controls.Add($b); return $b
}

New-Label "1. Windows 11 ISO path:" 15 15
$isoBox = New-TextBox 15 38
$isoBrowse = New-Button "Browse..." 375 37 80
$isoBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "ISO files (*.iso)|*.iso"
    if ($dlg.ShowDialog() -eq "OK") { $isoBox.Text = $dlg.FileName }
})

New-Label "2. Edition index (leave blank to list editions during build):" 15 70
$indexBox = New-TextBox 15 92 100

New-Label "3. Software list (JSON):" 15 130
$appsBox = New-TextBox 15 152
$appsBox.Text = Join-Path $ScriptRoot "Config\SampleApps.json"
$appsBrowse = New-Button "Browse..." 375 151 80
$appsBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON files (*.json)|*.json"
    if ($dlg.ShowDialog() -eq "OK") { $appsBox.Text = $dlg.FileName }
})

New-Label "4. Updates folder (.msu/.cab), optional:" 15 190
$updatesBox = New-TextBox 15 212
$updatesBrowse = New-Button "Browse..." 375 211 80
$updatesBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { $updatesBox.Text = $dlg.SelectedPath }
})

New-Label "5. Bloat/tweak config (JSON):" 15 250
$bloatBox = New-TextBox 15 272
$bloatBox.Text = Join-Path $ScriptRoot "Config\BloatApps.json"
$bloatBrowse = New-Button "Browse..." 375 271 80
$bloatBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON files (*.json)|*.json"
    if ($dlg.ShowDialog() -eq "OK") { $bloatBox.Text = $dlg.FileName }
})

New-Label "6. Output ISO path:" 15 310
$outBox = New-TextBox 15 332
$outBrowse = New-Button "Browse..." 375 331 80
$outBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "ISO files (*.iso)|*.iso"
    if ($dlg.ShowDialog() -eq "OK") { $outBox.Text = $dlg.FileName }
})

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ScrollBars = "Vertical"; $logBox.ReadOnly = $true
$logBox.Location = New-Object System.Drawing.Point(15, 370)
$logBox.Size = New-Object System.Drawing.Size(515, 70)
$form.Controls.Add($logBox)

function Write-Log($msg) {
    $logBox.AppendText("$(Get-Date -Format 'HH:mm:ss')  $msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

$buildBtn = New-Button "Build Image" 15 450 150
$buildBtn.Add_Click({
    try {
        $buildBtn.Enabled = $false
        if (-not $isoBox.Text -or -not (Test-Path $isoBox.Text)) { throw "Select a valid ISO path." }
        if (-not $outBox.Text) { throw "Select an output ISO path." }

        Write-Log "Extracting ISO..."
        Copy-IsoContents -IsoPath $isoBox.Text -DestFolder $ExtractDir

        $wimPath = Join-Path $ExtractDir "sources\install.wim"
        $esdPath = Join-Path $ExtractDir "sources\install.esd"
        if (-not (Test-Path $wimPath) -and (Test-Path $esdPath)) {
            if (-not $indexBox.Text) { throw "install.esd found — enter the edition index to convert (see Get-ImageEditions)." }
            Write-Log "Converting install.esd to install.wim for index $($indexBox.Text)..."
            Convert-EsdToWim -EsdPath $esdPath -WimOutPath $wimPath -Index ([int]$indexBox.Text)
        }

        if (-not $indexBox.Text) {
            $editions = Get-ImageEditions -WimPath $wimPath
            $list = ($editions | ForEach-Object { "$($_.Index): $($_.Name)" }) -join "`n"
            [System.Windows.Forms.MessageBox]::Show("Available editions:`n$list`n`nRe-run and enter an index.", "Choose an edition") | Out-Null
            return
        }

        Write-Log "Mounting image index $($indexBox.Text)..."
        Mount-Image -WimPath $wimPath -Index ([int]$indexBox.Text) -MountDir $MountDir

        Write-Log "Removing bloat apps..."
        Remove-BloatApps -MountDir $MountDir -ConfigPath $bloatBox.Text

        Write-Log "Applying registry tweaks..."
        Set-OfflineRegistryTweaks -MountDir $MountDir -ConfigPath $bloatBox.Text

        if ($appsBox.Text -and (Test-Path $appsBox.Text)) {
            Write-Log "Staging pre-installed software..."
            Add-PreinstalledSoftware -MountDir $MountDir -ConfigPath $appsBox.Text
        }

        if ($updatesBox.Text -and (Test-Path $updatesBox.Text)) {
            Write-Log "Integrating Windows updates..."
            Add-UpdatePackages -MountDir $MountDir -UpdatesFolder $updatesBox.Text
        }

        Write-Log "Committing and unmounting image..."
        Dismount-ImageAndCommit -MountDir $MountDir

        Write-Log "Exporting final ISO (requires Windows ADK oscdimg)..."
        Export-FinalIso -SourceFolder $ExtractDir -OutputIsoPath $outBox.Text

        Write-Log "Done! Output: $($outBox.Text)"
        [System.Windows.Forms.MessageBox]::Show("Build complete:`n$($outBox.Text)", "TinyBuilder+") | Out-Null
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Build failed", "OK", "Error") | Out-Null
    }
    finally {
        $buildBtn.Enabled = $true
    }
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
