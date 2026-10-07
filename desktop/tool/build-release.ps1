# Build release script for Windows
# Produces:
#   1. release/aniwings-desktop-windows-v<version>.exe         (Self-contained single-file portable executable)
#   2. release/aniwings-desktop-windows-v<version>-setup.exe   (Inno Setup installer, if Inno Setup is available)
#   3. release/aniwings-desktop-windows-v<version>-portable.zip (Portable ZIP bundle with all runtime DLLs & assets)

param(
    [switch]$SkipBuild = $false
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$desktopProject = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $desktopProject

try {
    # 1. Parse version from pubspec.yaml
    $pubspecPath = Join-Path $desktopProject 'pubspec.yaml'
    if (-not (Test-Path $pubspecPath)) {
        throw "Could not find pubspec.yaml at $pubspecPath"
    }

    $pubspecContent = Get-Content -LiteralPath $pubspecPath -Raw
    if ($pubspecContent -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
        $appVersion = $matches[1]
    } else {
        throw "Could not parse version from pubspec.yaml"
    }

    Write-Host "AniWings Desktop Release Version: v$appVersion" -ForegroundColor Cyan

    # 2. Ensure release directory exists
    $releaseDir = Join-Path $desktopProject 'release'
    if (-not (Test-Path $releaseDir)) {
        New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    }

    # 3. Build Windows release if not skipped
    if (-not $SkipBuild) {
        Write-Host "Running: flutter build windows --release..." -ForegroundColor Cyan
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed with exit code $LASTEXITCODE"
        }
    }

    # 4. Locate built output directory
    $possibleOutputDirs = @(
        (Join-Path $desktopProject 'build\windows\x64\runner\Release'),
        (Join-Path $desktopProject 'build\windows\runner\Release')
    )

    $sourceExe = $null
    $sourceDir = $null
    foreach ($dir in $possibleOutputDirs) {
        $candidate = Join-Path $dir 'aniwings.exe'
        if (Test-Path $candidate) {
            $sourceExe = $candidate
            $sourceDir = $dir
            break
        }
    }

    if (-not $sourceExe) {
        throw "Build finished, but could not find aniwings.exe in build output paths."
    }

    Write-Host "Source directory: $sourceDir" -ForegroundColor Cyan

    # 5. Prepare the full release bundle folder with all DLLs and data assets
    $bundleDir = Join-Path $releaseDir "aniwings-desktop-windows-v$appVersion"
    if (Test-Path $bundleDir) {
        Remove-Item -LiteralPath $bundleDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $bundleDir -Recurse -Force
    Write-Host "Release bundle directory created: $bundleDir" -ForegroundColor Green

    # 6. Create portable ZIP archive
    $portableZipPath = Join-Path $releaseDir "aniwings-desktop-windows-v$appVersion-portable.zip"
    if (Test-Path $portableZipPath) {
        Remove-Item -LiteralPath $portableZipPath -Force
    }
    Write-Host "Creating portable ZIP archive: $portableZipPath..." -ForegroundColor Cyan
    [System.IO.Compression.ZipFile]::CreateFromDirectory($sourceDir, $portableZipPath)
    Write-Host "Portable ZIP created: $portableZipPath" -ForegroundColor Green

    # 7. Build self-contained single-file portable .exe using C# launcher stub
    $targetExeName = "aniwings-desktop-windows-v$appVersion.exe"
    $targetExePath = Join-Path $releaseDir $targetExeName
    $launcherTemplate = Join-Path $desktopProject 'tool\windows\Launcher.cs'
    $iconPath = Join-Path $desktopProject 'windows\runner\resources\app_icon.ico'

    $cscCandidates = @(
        "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
        "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    )
    $cscExe = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($cscExe -and (Test-Path $launcherTemplate)) {
        Write-Host "Building self-contained single-file executable: $targetExePath..." -ForegroundColor Cyan
        $tempCsFile = Join-Path $env:TEMP "AniWings_Launcher_$appVersion.cs"
        $csContent = Get-Content -LiteralPath $launcherTemplate -Raw
        $csContent = $csContent.Replace('__APP_VERSION__', $appVersion)
        Set-Content -LiteralPath $tempCsFile -Value $csContent -Encoding UTF8

        $cscArgs = @(
            '/nologo',
            '/target:winexe',
            '/platform:x64',
            '/optimize+',
            "/win32icon:$iconPath",
            "/resource:$portableZipPath,bundle.zip",
            '/r:System.IO.Compression.dll',
            '/r:System.IO.Compression.FileSystem.dll',
            '/r:System.Windows.Forms.dll',
            "/out:$targetExePath",
            $tempCsFile
        )

        & $cscExe $cscArgs
        Remove-Item -LiteralPath $tempCsFile -Force -ErrorAction SilentlyContinue

        if (Test-Path $targetExePath) {
            Write-Host "Self-contained single .exe created: $targetExePath" -ForegroundColor Green
        } else {
            Write-Warning "Failed to compile single .exe with csc.exe. Falling back to copying runner exe."
            Copy-Item -LiteralPath $sourceExe -Destination $targetExePath -Force
        }
    } else {
        Write-Warning "C# compiler not found. Falling back to copying runner exe."
        Copy-Item -LiteralPath $sourceExe -Destination $targetExePath -Force
    }

    # 8. Build Inno Setup installer if Inno Setup is available
    $isccCandidates = @(
        (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    )
    $isccExe = $isccCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    $issFile = Join-Path $desktopProject 'tool\windows\installer.iss'

    if ($isccExe -and (Test-Path $issFile)) {
        Write-Host "Building Inno Setup installer using $isccExe..." -ForegroundColor Cyan
        $setupBaseName = "aniwings-desktop-windows-v$appVersion-setup"
        & $isccExe /Q `
            "/DMyAppVersion=$appVersion" `
            "/DMySourceDir=$sourceDir" `
            "/DMyOutputDir=$releaseDir" `
            "/DMyOutputBaseFilename=$setupBaseName" `
            "/DMyIconPath=$iconPath" `
            $issFile

        $setupExePath = Join-Path $releaseDir "$setupBaseName.exe"
        if (Test-Path $setupExePath) {
            Write-Host "Setup installer created: $setupExePath" -ForegroundColor Green
        }
    } else {
        Write-Host "Inno Setup (iscc.exe) not found. Skipping installer generation. (Portable single .exe and zip were created)." -ForegroundColor Yellow
        Write-Host "Tip: To enable installer generation locally, install Inno Setup: winget install JRSoftware.InnoSetup" -ForegroundColor DarkGray
    }

    Write-Host "Successfully generated release artifacts for Windows v$appVersion" -ForegroundColor Green
}
finally {
    Pop-Location
}
