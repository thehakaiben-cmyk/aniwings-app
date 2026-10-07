# Run from the project root. This starts the desktop UI preview on an Android AVD.
param([string]$Device = 'emulator-5554')
$previewProject = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $previewProject
try {
    & flutter run --device-id=$Device --dart-define=DESKTOP_EMULATOR_PREVIEW=true @args
    $previewExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $previewExitCode
