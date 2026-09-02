#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$InstallDependencies
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'dist'
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this build with Windows PowerShell 5.1 (powershell.exe), not pwsh.'
}

$sourcePath = Join-Path $PSScriptRoot 'zapret-gui.ps1'
$versionPath = Join-Path $PSScriptRoot 'VERSION'
$gearPath = Join-Path $PSScriptRoot 'settings-gear.png'
foreach ($requiredPath in @($sourcePath, $versionPath, $gearPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file not found: $requiredPath"
    }
}

$version = ([IO.File]::ReadAllText($versionPath)).Trim()
if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$') {
    throw "VERSION must use the 1.2.3 or 1.2.3.4 format: $version"
}
$assemblyVersion = '{0}.{1}.{2}.{3}' -f $Matches[1], $Matches[2], $Matches[3], $(if ($Matches[4]) { $Matches[4] } else { '0' })

$ps2exeVersion = [version]'1.0.18'
$ps2exeHash = 'hPx2l6ZCPdtf9BzYuS/j/P7B/1zCz5szfeKTpHfi3ujX8Gsvb3KfaGhI+n84u/kAWezjlD2e3Wkxy5ny3wT1Kg=='
$toolDirectory = Join-Path $PSScriptRoot ".build\ps2exe\$ps2exeVersion"
$manifestPath = Join-Path $toolDirectory 'ps2exe.psd1'
$ps2exe = Get-Module -ListAvailable ps2exe |
    Where-Object { $_.Version -eq $ps2exeVersion } |
    Select-Object -First 1
if (-not $ps2exe -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $ps2exe = Get-Module -ListAvailable $manifestPath | Select-Object -First 1
}
if (-not $ps2exe) {
    if (-not $InstallDependencies) {
        throw 'The ps2exe module is missing. Run again with -InstallDependencies.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $toolParent = Split-Path -Parent $toolDirectory
        if (-not (Test-Path -LiteralPath $toolParent)) {
            New-Item -ItemType Directory -Path $toolParent -Force | Out-Null
        }
        $downloadDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ps2exe-download-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
        try {
            $packagePath = Join-Path $downloadDirectory 'ps2exe.nupkg'
            $packageUri = "https://www.powershellgallery.com/api/v2/package/ps2exe/$ps2exeVersion"
            $webClient = [Net.WebClient]::new()
            try {
                $webClient.Headers['User-Agent'] = 'ZapretGUI-Build'
                $webClient.DownloadFile($packageUri, $packagePath)
            } finally {
                $webClient.Dispose()
            }
            $sha512 = [Security.Cryptography.SHA512]::Create()
            try {
                $packageBytes = [IO.File]::ReadAllBytes($packagePath)
                $actualHash = [Convert]::ToBase64String($sha512.ComputeHash($packageBytes))
            } finally {
                $sha512.Dispose()
            }
            if ($actualHash -ne $ps2exeHash) {
                throw 'The downloaded ps2exe package failed SHA-512 verification.'
            }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $extractDirectory = Join-Path $downloadDirectory 'extract'
            [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractDirectory)
            if (-not (Test-Path -LiteralPath (Join-Path $extractDirectory 'ps2exe.psd1') -PathType Leaf)) {
                throw 'The verified ps2exe package has an unexpected layout.'
            }
            if (Test-Path -LiteralPath $toolDirectory) {
                Remove-Item -LiteralPath $toolDirectory -Recurse -Force
            }
            Move-Item -LiteralPath $extractDirectory -Destination $toolDirectory
        } finally {
            if (Test-Path -LiteralPath $downloadDirectory) {
                Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $ps2exe = Get-Module -ListAvailable $manifestPath | Select-Object -First 1
}
if (-not $ps2exe) { throw 'Unable to install the ps2exe module.' }
Import-Module $ps2exe.Path -Force

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$releaseName = "ZapretGUI-$version-win10-win11"
$releaseDirectory = Join-Path $OutputDirectory $releaseName
if (Test-Path -LiteralPath $releaseDirectory) {
    Remove-Item -LiteralPath $releaseDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

$workDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ZapretGUI-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

try {
    $source = [IO.File]::ReadAllText($sourcePath)
    $fallback = "return '$version'"
    $source = $source.Replace("return '1.0.0'", $fallback)
    if (-not $source.Contains($fallback)) {
        throw 'Unable to embed the GUI version into the compiled script.'
    }
    $gearAssign = '$script:EmbeddedSettingsGearPngBase64 = [string]::Empty'
    if (-not $source.Contains($gearAssign)) {
        throw 'Unable to find the settings-gear embed assignment in the compiled script.'
    }
    $gearBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($gearPath))
    $source = $source.Replace($gearAssign, ('$script:EmbeddedSettingsGearPngBase64 = ''{0}''' -f $gearBase64))
    if ($source.Contains($gearAssign)) {
        throw 'Unable to embed settings-gear.png into the compiled script.'
    }
    $compiledSourcePath = Join-Path $workDirectory 'zapret-gui.compiled.ps1'
    [IO.File]::WriteAllText($compiledSourcePath, $source, [Text.UTF8Encoding]::new($true))

    Add-Type -AssemblyName System.Drawing
    $iconPngPath = Join-Path $workDirectory 'app-icon.png'
    $iconPath = Join-Path $workDirectory 'app-icon.ico'
    $sourceImage = [Drawing.Image]::FromFile($gearPath)
    try {
        $bitmap = [Drawing.Bitmap]::new(256, 256, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $scale = [Math]::Min(224.0 / $sourceImage.Width, 224.0 / $sourceImage.Height)
                $width = [int][Math]::Round($sourceImage.Width * $scale)
                $height = [int][Math]::Round($sourceImage.Height * $scale)
                $left = [int][Math]::Floor((256 - $width) / 2)
                $top = [int][Math]::Floor((256 - $height) / 2)
                $graphics.DrawImage($sourceImage, $left, $top, $width, $height)
            } finally {
                $graphics.Dispose()
            }
            $bitmap.Save($iconPngPath, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bitmap.Dispose()
        }
    } finally {
        $sourceImage.Dispose()
    }

    $pngBytes = [IO.File]::ReadAllBytes($iconPngPath)
    $iconStream = [IO.File]::Create($iconPath)
    try {
        $writer = [IO.BinaryWriter]::new($iconStream)
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]1)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$pngBytes.Length)
            $writer.Write([uint32]22)
            $writer.Write($pngBytes)
        } finally {
            $writer.Dispose()
        }
    } finally {
        $iconStream.Dispose()
    }

    $exePath = Join-Path $releaseDirectory 'ZapretGUI.exe'
    Invoke-ps2exe `
        -inputFile $compiledSourcePath `
        -outputFile $exePath `
        -noConsole `
        -noOutput `
        -STA `
        -requireAdmin `
        -DPIAware `
        -supportOS `
        -iconFile $iconPath `
        -title 'ZAPRET GUI' `
        -description 'GUI wrapper for Flowseal zapret-discord-youtube' `
        -company 'ZAPRET GUI' `
        -product 'ZAPRET GUI' `
        -copyright 'ZAPRET GUI contributors' `
        -version $assemblyVersion

    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw 'The compiler did not create ZapretGUI.exe.'
    }

    $readmeSrc = Join-Path $PSScriptRoot 'README.md'
    if (-not (Test-Path -LiteralPath $readmeSrc -PathType Leaf)) {
        throw "Required file not found: $readmeSrc"
    }
    Copy-Item -LiteralPath $readmeSrc -Destination (Join-Path $releaseDirectory 'README.md')
    Copy-Item -LiteralPath $readmeSrc -Destination (Join-Path $releaseDirectory 'README.txt')

    $files = Get-ChildItem -LiteralPath $releaseDirectory -File | Sort-Object Name
    $hashLines = foreach ($file in $files) {
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($file.Name)"
    }
    [IO.File]::WriteAllLines(
        (Join-Path $releaseDirectory 'SHA256SUMS.txt'),
        $hashLines,
        [Text.UTF8Encoding]::new($false))

    $zipPath = Join-Path $OutputDirectory "$releaseName.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -LiteralPath $releaseDirectory -DestinationPath $zipPath -CompressionLevel Optimal

    Write-Host "EXE: $exePath"
    Write-Host "ZIP: $zipPath"
} finally {
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
