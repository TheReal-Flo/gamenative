# Run after build-windows-xr-runtime.ps1 has prepared headers and imports.
$ErrorActionPreference = "Stop"
$repository = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repository "app\build\windows-xr-runtime"
$source = Join-Path $repository "app\src\main\windows\openxr_runtime"
$bin = Join-Path $env:LOCALAPPDATA "Android\Sdk\ndk\29.0.14206865\toolchains\llvm\prebuilt\windows-x86_64\bin"
foreach ($arch in @("x64", "x86")) {
    $is64 = $arch -eq "x64"
    $target = if ($is64) { "x86_64-w64-windows-gnu" } else { "i686-w64-windows-gnu" }
    $machine = if ($is64) { "i386:x86-64" } else { "i386" }
    $definition = Join-Path $build "test-kernel32-$arch.def"
    $extra = if ($is64) { @("CreateThread", "WaitForSingleObject") } else { @("CreateThread@24", "WaitForSingleObject@8") }
    Set-Content $definition ((Get-Content (Join-Path $source "kernel32_$arch.def")) + $extra)
    $kernel = Join-Path $build "test-kernel32-$arch.a"
    & "$bin\llvm-dlltool.exe" -m $machine -k -d $definition -l $kernel
    if ($LASTEXITCODE -ne 0) { throw "Test imports failed" }
    $exe = Join-Path $build "test-locks-$arch.exe"
    & "$bin\clang.exe" "--target=$target" -O2 -ffreestanding -nostdlib "-Wl,-e,test_main" -I (Join-Path $build "_deps\openxr_sdk-build\include") (Join-Path $PSScriptRoot "tests\windows-xr-locks.c") $kernel (Join-Path $build "libws2_32_$arch.a") (Join-Path $build "libntdll_$arch.a") (Join-Path $build "libdxgi_$arch.a") -o $exe
    if ($LASTEXITCODE -ne 0) { throw "Test build failed: $arch" }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw "Lock tests failed: $arch exit $LASTEXITCODE" }
    Write-Host "Lock concurrency tests passed: $arch"
}
