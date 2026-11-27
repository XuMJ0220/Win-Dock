param([switch] $NoOpen)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$edgePath = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

$appPaths = [ordered]@{
    explorer   = "$env:WINDIR\explorer.exe"
    edge       = $edgePath
    notepad    = "$env:WINDIR\System32\notepad.exe"
    powershell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    calculator = "$env:WINDIR\System32\calc.exe"
    settings   = "$env:WINDIR\ImmersiveControlPanel\SystemSettings.exe"
}

$nativeIcons = [ordered]@{}
foreach ($app in $appPaths.Keys) {
    $appPath = $appPaths[$app]
    if (!$appPath -or !(Test-Path -LiteralPath $appPath -PathType Leaf)) { continue }

    $icon = $null
    $bitmap = $null
    $stream = [System.IO.MemoryStream]::new()
    try {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($appPath)
        if (!$icon) { continue }
        $bitmap = $icon.ToBitmap()
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $nativeIcons[$app] = 'data:image/png;base64,' + [Convert]::ToBase64String($stream.ToArray())
    } catch {
        Write-Verbose "Could not extract the icon for $app. The preview will use its text fallback."
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
        if ($icon) { $icon.Dispose() }
        $stream.Dispose()
    }
}

$html = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html'))
$css = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'styles.css'))
$javascript = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'prototype.js'))
$iconJson = ConvertTo-Json -InputObject $nativeIcons -Compress
$html = $html.Replace('<link rel="stylesheet" href="./styles.css">', "<style>$css</style>")
$html = $html.Replace('<script src="./prototype.js"></script>', "<script>window.winDockIconSources = $iconJson;</script><script>$javascript</script>")

$previewFolder = Join-Path ([System.IO.Path]::GetTempPath()) 'Win-Dock\dock-appearance-prototype'
[System.IO.Directory]::CreateDirectory($previewFolder) | Out-Null
$previewFile = Join-Path $previewFolder 'Win-Dock-appearance.html'
[System.IO.File]::WriteAllText($previewFile, $html, [System.Text.UTF8Encoding]::new($false))
if (!$NoOpen) {
    Start-Process -FilePath $previewFile
}
Write-Output $previewFile
