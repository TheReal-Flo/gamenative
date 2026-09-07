$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$patchMarker = "Ignoring VRApplication_Background: no shared OpenVR server is available"
foreach ($flavor in @("modernXr", "legacyXr")) {
    $destination = Join-Path $repository "app\src\$flavor\assets\opencomposite_x64.dll"
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "Patched OpenComposite payload is missing for $flavor. Run tools\build-opencomposite.ps1."
    }
    $bytes = [System.IO.File]::ReadAllBytes($destination)
    $offset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ([BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x8664) {
        throw "OpenComposite payload for $flavor is not x64"
    }
    if (-not [System.Text.Encoding]::ASCII.GetString($bytes).Contains($patchMarker)) {
        throw "OpenComposite payload for $flavor does not contain the GameNative app-type fix. Run tools\build-opencomposite.ps1."
    }
}
