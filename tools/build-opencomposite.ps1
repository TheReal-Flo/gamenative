param(
    [string]$VulkanSdk = $env:VULKAN_SDK,
    [string]$WorkDirectory
)

$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$commit = "a27e7e6a64bdcd1eff6b7fba1ea2ea34bcf1273d"
$patch = Join-Path $PSScriptRoot "patches\opencomposite-background-support.patch"
if ([string]::IsNullOrWhiteSpace($WorkDirectory)) {
    $WorkDirectory = Join-Path $repository "app\build\opencomposite"
}
$source = Join-Path $WorkDirectory "source"
$build = Join-Path $WorkDirectory "build"

if ([string]::IsNullOrWhiteSpace($VulkanSdk)) {
    throw "Set VULKAN_SDK or pass -VulkanSdk. OpenComposite needs Vulkan headers and Lib\vulkan-1.lib."
}
$vulkanInclude = Join-Path $VulkanSdk "Include"
$vulkanLibrary = Join-Path $VulkanSdk "Lib\vulkan-1.lib"
if (-not (Test-Path -LiteralPath (Join-Path $vulkanInclude "vulkan\vulkan.h") -PathType Leaf)) {
    throw "Vulkan headers were not found under $vulkanInclude"
}
if (-not (Test-Path -LiteralPath $vulkanLibrary -PathType Leaf)) {
    throw "Vulkan import library was not found at $vulkanLibrary"
}

New-Item -ItemType Directory -Force -Path $WorkDirectory | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $source ".git") -PathType Container)) {
    git clone https://gitlab.com/znixian/OpenOVR.git $source
    if ($LASTEXITCODE -ne 0) { throw "Could not clone OpenComposite" }
}
git -C $source fetch origin $commit
if ($LASTEXITCODE -ne 0) { throw "Could not fetch OpenComposite commit $commit" }
git -C $source checkout --detach --force $commit
if ($LASTEXITCODE -ne 0) { throw "Could not check out OpenComposite commit $commit" }
git -C $source submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "Could not initialize OpenComposite submodules" }
git -C $source reset --hard $commit
git -C $source clean -dffx
git -C $source apply --check $patch
if ($LASTEXITCODE -ne 0) { throw "The GameNative OpenComposite patch no longer applies" }
git -C $source apply $patch
if ($LASTEXITCODE -ne 0) { throw "Could not apply the GameNative OpenComposite patch" }

$bundledVulkan = Join-Path $source "libs\vulkan"
New-Item -ItemType Directory -Force -Path (Join-Path $bundledVulkan "Include"), (Join-Path $bundledVulkan "Lib") | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $vulkanInclude "*") -Destination (Join-Path $bundledVulkan "Include")
Copy-Item -Force -LiteralPath $vulkanLibrary -Destination (Join-Path $bundledVulkan "Lib\vulkan-1.lib")

cmake -S $source -B $build -A x64 -DOC_VERSION="a27e7e6-gamenative-scene-only"
if ($LASTEXITCODE -ne 0) { throw "Could not configure OpenComposite" }
cmake --build $build --config Release --target OCOVR --parallel
if ($LASTEXITCODE -ne 0) { throw "Could not build OpenComposite" }

$binary = Join-Path $build "bin\Release\vrclient_x64.dll"
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "OpenComposite output is missing: $binary" }
foreach ($flavor in @("modernXr", "legacyXr")) {
    $assets = Join-Path $repository "app\src\$flavor\assets"
    New-Item -ItemType Directory -Force -Path $assets | Out-Null
    Copy-Item -Force -LiteralPath $binary -Destination (Join-Path $assets "opencomposite_x64.dll")
}
& (Join-Path $PSScriptRoot "verify-xr-payload.ps1")
if ($LASTEXITCODE -ne 0) { throw "XR payload verification failed" }
Copy-Item -Force -LiteralPath (Join-Path $repository "app\src\modernXr\assets\payload.version") `
    -Destination (Join-Path $repository "app\src\legacyXr\assets\payload.version")
Write-Host "Staged patched OpenComposite from commit $commit"
