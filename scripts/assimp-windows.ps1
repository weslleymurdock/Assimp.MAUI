#requires -Version 5.1

param(
    [string]$Arch = "x64", # Opções: x64, arm64
    [switch]$PublishLocal,
    [switch]$NoPublishLocal
)

if ($Arch.Count -gt 1) {
    $overallExitCode = 0
    foreach ($targetArch in $Arch) {
        $forwardedArgs = @('-Arch', $targetArch)
        if ($PublishLocal) { $forwardedArgs += '-PublishLocal' }
        if ($NoPublishLocal) { $forwardedArgs += '-NoPublishLocal' }
        & $PSCommandPath @forwardedArgs
        if ($LASTEXITCODE -ne 0) { $overallExitCode = $LASTEXITCODE }
    }
    exit $overallExitCode
}

$ErrorActionPreference = "Stop"
$ASSIMP_TAG = if ($env:ASSIMP_TAG) { $env:ASSIMP_TAG } else { "v6.0.6" }
$BUILD_DIR = "$PSScriptRoot/../build/windows-$Arch"
$SWIG_OUT = "$PSScriptRoot/../src/Assimp.Maui/Platforms/Windows/Maui"
$RUNTIME_RID = if ($Arch -eq "arm64") { "win-arm64" } else { "win-x64" }
$PUBLISH_LOCAL = $PublishLocal -or (-not $NoPublishLocal -and $env:CI -notin @('true', '1', 'yes', 'TRUE', 'YES'))

if ($Arch -ne "x64" -and $Arch -ne "arm64") {
    Write-Error "Invalid architecture. Use 'x64' or 'arm64'."
    exit 1
}

Write-Host "=== 0. Detecting or Installing Visual Studio 2022 Build Tools ===" -ForegroundColor Cyan

$VcvarsPath = $null

$VsWhereCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "$env:ProgramData\Microsoft\VisualStudio\Installer\vswhere.exe",
    "$env:LOCALAPPDATA\Microsoft\VisualStudio\Installer\vswhere.exe"
)
$VsWhere = $VsWhereCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($VsWhere) {
    $VsRequirements = @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
    if ($Arch -eq 'arm64') { $VsRequirements += 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
    $VsPath = & $VsWhere -latest -products * -requires $VsRequirements -property installationPath
    if ($VsPath) {
        $PotentialPath = Join-Path $VsPath "VC\Auxiliary\Build\vcvarsall.bat"
        if (Test-Path $PotentialPath) {
            $VcvarsPath = $PotentialPath
        }
    }
}

if (!$VcvarsPath) {
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' }
    foreach ($drive in $drives) {
        $driveLetter = $drive.Name.Substring(0, 1)
        foreach ($SearchPath in @(
            "${driveLetter}:\Program Files\Microsoft Visual Studio",
            "${driveLetter}:\Program Files (x86)\Microsoft Visual Studio",
            "${driveLetter}:\Microsoft Visual Studio"
        )) {
            if (Test-Path $SearchPath) {
                $found = Get-ChildItem -Path $SearchPath -Filter "vcvarsall.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $VcvarsPath = $found.FullName
                    break
                }
            }
        }
        if ($VcvarsPath) { break }
    }
}

if (!$VcvarsPath) {
    Write-Host "Visual Studio C++ Build Tools not found on any drive. Installing silently..." -ForegroundColor Yellow

    $bestDrive = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | Sort-Object TotalFreeSpace -Descending | Select-Object -First 1
    $installDriveLetter = $bestDrive.Name.Substring(0, 1)
    $installPath = "${installDriveLetter}:\VS2022BuildTools"

    Write-Host "Selected drive with most free space for installation: ${installDriveLetter}:\ (Free: $([math]::Round($bestDrive.TotalFreeSpace / 1GB, 2)) GB)" -ForegroundColor Green

    $installerUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $installerPath = "$env:TEMP\vs_BuildTools.exe"

    Write-Host "Downloading Visual Studio Build Tools installer..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

    Write-Host "Running silent installation (this may take a few minutes)..." -ForegroundColor Cyan
    $arm64Component = if ($Arch -eq "arm64") { " --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" } else { "" }
    $processArgs = "--quiet --wait --norestart --nocache --installPath `"$installPath`" --add Microsoft.VisualStudio.Workload.VCTools$arm64Component --includeRecommended"
    $installProcess = Start-Process -FilePath $installerPath -ArgumentList $processArgs -Wait -PassThru

    if ($installProcess.ExitCode -ne 0 -and $installProcess.ExitCode -ne 3010) {
        throw "Visual Studio Build Tools installation failed with exit code: $($installProcess.ExitCode)"
    }

    $VcvarsPath = Join-Path $installPath "VC\Auxiliary\Build\vcvarsall.bat"
}

if (!$VcvarsPath -or !(Test-Path $VcvarsPath)) {
    throw "vcvarsall.bat could not be located at: $VcvarsPath"
}

Write-Host "Using MSVC toolchain located at: $VcvarsPath" -ForegroundColor Green

Set-Location $PSScriptRoot/..

if ($PUBLISH_LOCAL) {
    Write-Host "=== Local artifact publishing enabled ===" -ForegroundColor Cyan
    if (Test-Path $SWIG_OUT) { Remove-Item -Recurse -Force $SWIG_OUT }
    $runtimeDir = "src/Assimp.Maui/Platforms/Windows/runtimes/$RUNTIME_RID/native"
    if (Test-Path $runtimeDir) { Remove-Item -Recurse -Force $runtimeDir }
}

Write-Host "=== 1. Cleaning previous builds ===" -ForegroundColor Cyan
if (Test-Path $BUILD_DIR) { Remove-Item -Recurse -Force $BUILD_DIR }
if (Test-Path $SWIG_OUT) { Remove-Item -Recurse -Force $SWIG_OUT }

Write-Host "=== 2. Cloning/Updating Assimp Repository (Tag $ASSIMP_TAG) ===" -ForegroundColor Cyan
if (!(Test-Path "external/assimp/.git")) {
    New-Item -ItemType Directory -Force -Path "external" | Out-Null
    git clone --depth 1 --branch "$ASSIMP_TAG" https://github.com/assimp/assimp.git external/assimp
}
else {
    Push-Location "external/assimp"
    git fetch --tags --depth 1 origin tag "$ASSIMP_TAG"
    git checkout "$ASSIMP_TAG"
    Pop-Location
}

Push-Location "external/assimp"
git submodule update --init --recursive --depth 1
Pop-Location

Write-Host "=== 3. Configuring and Building Assimp for Windows ($Arch) ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null

cmake -S external/assimp -B $BUILD_DIR `
    -G "Visual Studio 17 2022" `
    -A $(if ($Arch -eq "arm64") { "ARM64" } else { "x64" }) `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=ON `
    -DASSIMP_BUILD_TESTS=OFF `
    -DASSIMP_BUILD_ASSIMP_TOOLS=OFF `
    -DASSIMP_BUILD_ZLIB=ON `
    -DASSIMP_INSTALL_PDB=OFF `
    -DASSIMP_INJECT_DEBUG_POSTFIX=OFF

cmake --build $BUILD_DIR --config Release -j $env:NUMBER_OF_PROCESSORS

Write-Host "=== 4. Generating SWIG C# Bindings for Windows ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $SWIG_OUT | Out-Null

$swigParseRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("assimp-swig-headers-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $swigParseRoot "assimp") | Out-Null
Copy-Item -Recurse -Force "external/assimp/include/assimp/*" (Join-Path $swigParseRoot "assimp")
$swigInterface = Join-Path $swigParseRoot "assimp.i"
$interfaceText = [System.IO.File]::ReadAllText("swig/assimp.i").Replace("external/assimp/include/assimp/", "assimp/")
[System.IO.File]::WriteAllText($swigInterface, $interfaceText)

$force32Pattern = '^[ \t]*_[A-Za-z0-9]+_Force32Bit[ \t]*=[ \t]*INT_MAX'
$force32MetadataPattern = '^[ \t]*FORCE_32BIT[ \t]*=[ \t]*INT_MAX'
$enumTailPattern = '^[ \t]*};[ \t]*//!+ enum.*$'

foreach ($header in (Get-ChildItem -LiteralPath (Join-Path $swigParseRoot "assimp") -Filter "*.h" -Recurse -File)) {
    $lines = [System.IO.File]::ReadAllText($header.FullName) -split "`r?`n"
    $output = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt $lines.Length; $index++) {
        if ($lines[$index] -match '^\s*/\*\*') {
            $docLines = New-Object 'System.Collections.Generic.List[string]'
            do {
                $docLines.Add($lines[$index])
                $docClosed = $lines[$index] -match '\*/'
                $index++
                if ($index -ge $lines.Length) { break }
            } while (-not $docClosed)

            if (($index + 2) -lt $lines.Length -and
                $lines[$index] -match '^\s*#ifndef SWIG\s*$' -and
                ($lines[$index + 1] -match $force32Pattern -or $lines[$index + 1] -match $force32MetadataPattern) -and
                $lines[$index + 2] -match '^\s*#endif') {
                $output.Add('    /* SWIG parser: omitted 32-bit enum sentinel. */')
                $index += 2
                continue
            }

            foreach ($docLine in $docLines) { $output.Add($docLine) }
            $index--
            continue
        }

        if ($lines[$index] -match '^\s*#ifndef SWIG\s*$' -and ($index + 2) -lt $lines.Length -and ($lines[$index + 1] -match $force32Pattern -or $lines[$index + 1] -match $force32MetadataPattern) -and $lines[$index + 2] -match '^\s*#endif') {
            $output.Add('    /* SWIG parser: omitted 32-bit enum sentinel. */')
            $index += 2
            continue
        }

        # Keep the workaround line-scoped: equivalent to sed on `}; //! enum ...`.
        if ($lines[$index] -match $enumTailPattern) {
            $output.Add("};")
        } else {
            $output.Add($lines[$index])
        }
    }
    [System.IO.File]::WriteAllText($header.FullName, ($output -join [Environment]::NewLine))
}

Write-Host "Using $((& swig -version 2>&1 | Select-String 'SWIG Version' | ForEach-Object { $_.ToString().Trim() })) with Doxygen-enabled C# generation." -ForegroundColor Cyan
& swig -c++ -csharp `
    -doxygen `
    -namespace Assimp.Maui `
    -dllimport "assimpmaui" `
    ("-I" + $swigParseRoot) `
    -outdir $SWIG_OUT `
    -o "$SWIG_OUT/assimpmaui.cxx" `
    $swigInterface
if ($LASTEXITCODE -ne 0) { throw "SWIG C# binding generation failed with Doxygen-enabled temporary headers." }
Remove-Item -Recurse -Force $swigParseRoot

Write-Host "=== 5. Building Native SWIG Wrapper DLL for Windows ($Arch) ===" -ForegroundColor Cyan
$VcvarsArch = if ($Arch -eq "arm64") { "x64_arm64" } else { "x64" }
$BinDir = "$BUILD_DIR/bin/Release"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$CmdScript = @"
call "$VcvarsPath" $VcvarsArch
cl /LD /EHsc /O2 /std:c++17 `
    src\Assimp.Maui\Platforms\Windows\Maui\assimpmaui.cxx `
    /Iexternal\assimp\include `
    /Ibuild\windows-$Arch\include `
    /link /LIBPATH:build\windows-$Arch\lib\Release assimp-vc143-mt.lib `
    /OUT:build\windows-$Arch\bin\Release\assimpmaui.dll
"@

$TempBat = [System.IO.Path]::GetTempFileName() + ".bat"
Set-Content -Path $TempBat -Value $CmdScript
& cmd.exe /c $TempBat
Remove-Item $TempBat

Write-Host "=== 6. Build Result ===" -ForegroundColor Cyan
$AssimpDll = "$BUILD_DIR/bin/Release/assimp-vc143-mt.dll"
$WrapperDll = "$BUILD_DIR/bin/Release/assimpmaui.dll"

if ((Test-Path $AssimpDll) -and (Test-Path $WrapperDll)) {
    Write-Host "SUCCESS: Windows binaries compiled successfully for $Arch!" -ForegroundColor Green
    Get-Item $AssimpDll, $WrapperDll | Select-Object Name, Length
    if ($PUBLISH_LOCAL) {
        $runtimeDir = "src/Assimp.Maui/Platforms/Windows/runtimes/$RUNTIME_RID/native"
        New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
        Get-ChildItem -LiteralPath "$BUILD_DIR/bin/Release" -Filter '*.dll' -File | Copy-Item -Destination $runtimeDir -Force
        Write-Host "Published Windows $RUNTIME_RID assets to $runtimeDir" -ForegroundColor Green
    }
}
else {
    Write-Error "ERROR: Windows compilation failed for $Arch."
    exit 1
}
