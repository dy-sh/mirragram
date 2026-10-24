# Builds tdjson.dll for Windows x64 with OpenSSL and zlib linked statically.
# Requires: Visual Studio with C++ tools, CMake, git and vcpkg
# (VCPKG_ROOT or VCPKG_INSTALLATION_ROOT).
$ErrorActionPreference = 'Stop'

$TdCommit = if ($env:TD_COMMIT) { $env:TD_COMMIT } else { 'c15d3f5a5de6e3ba5839822c451152e5e18bb700' } # TDLib 1.8.68
$Root = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Root '.tdlib/src'
$Out = Join-Path $Root '.tdlib/out/windows-x64'
$Vcpkg = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { $env:VCPKG_INSTALLATION_ROOT }
if (-not $Vcpkg) { throw 'vcpkg not found: set VCPKG_ROOT' }

function Invoke-Native {
  & $args[0] $args[1..($args.Count - 1)]
  if ($LASTEXITCODE -ne 0) { throw "Failed: $($args -join ' ')" }
}

$Triplet = 'x64-windows-static-md'
Invoke-Native "$Vcpkg/vcpkg" install gperf:x64-windows "openssl:$Triplet" "zlib:$Triplet"

if (-not (Test-Path (Join-Path $Src '.git'))) {
  Invoke-Native git clone https://github.com/tdlib/td.git $Src
}
Invoke-Native git -C $Src fetch --quiet origin
Invoke-Native git -C $Src checkout --quiet $TdCommit

$Build = Join-Path $Src 'build-windows'
New-Item -ItemType Directory -Force $Build | Out-Null
Invoke-Native cmake -S $Src -B $Build -A x64 `
  "-DCMAKE_TOOLCHAIN_FILE=$Vcpkg/scripts/buildsystems/vcpkg.cmake" `
  "-DVCPKG_TARGET_TRIPLET=$Triplet" `
  "-DGPERF_EXECUTABLE=$Vcpkg/installed/x64-windows/tools/gperf/gperf.exe"
Invoke-Native cmake --build $Build --config Release --target tdjson --parallel

New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item (Join-Path $Build 'Release/tdjson.dll') (Join-Path $Out 'tdjson.dll')
Write-Host "OK: $Out/tdjson.dll"
