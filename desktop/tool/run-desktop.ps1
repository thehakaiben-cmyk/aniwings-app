$desktopProject = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $desktopProject
try {
    & flutter run --device-id=windows @args
    $desktopExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $desktopExitCode
