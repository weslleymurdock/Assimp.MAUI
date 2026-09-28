param(
    [string]$Arch = "x64" # Opções: x64, arm64
)

$ErrorActionPreference = "Stop"
$ASSIMP_TAG = "v6.0.5"
$BUILD_DIR = "build/windows-$Arch"
$SWIG_OUT = "src/Assimp.Maui.Windows/Maui"

if ($Arch -ne "x64" -and $Arch -ne "arm64") {
    Write-Error "Invalid architecture. Use 'x64' or 'arm64'."
    exit 1
}

Write-Host "=== 0. Detecting or Installing Visual Studio 2022 Build Tools ===" -ForegroundColor Cyan

$VcvarsPath = $null

$DefaultVsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $DefaultVsWhere) {
    $VsPath = & $DefaultVsWhere -latest -products * -requires Microsoft.Component.VisualStudio.VC.Tools.Core.x86.x64 -property installationPath
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
        $SearchPath = "${driveLetter}:\Microsoft Visual Studio"
        
        if (Test-Path $SearchPath) {
            $found = Get-ChildItem -Path $SearchPath -Filter "vcvarsall.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $VcvarsPath = $found.FullName
                break
            }
        }
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
    $processArgs = "--quiet --wait --norestart --nocache --installPath `"$installPath`" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
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

swig -c++ -csharp `
    -namespace Assimp.Maui `
    -dllimport "assimpmaui" `
    -outdir $SWIG_OUT `
    -o "$SWIG_OUT/assimpmaui.cxx" `
    swig/assimp.i

Write-Host "=== 5. Building Native SWIG Wrapper DLL for Windows ($Arch) ===" -ForegroundColor Cyan
$VcvarsArch = if ($Arch -eq "arm64") { "x64_arm64" } else { "x64" }
$BinDir = "$BUILD_DIR/bin/Release"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$CmdScript = @"
call "$VcvarsPath" $VcvarsArch
cl /LD /EHsc /O2 /std:c++17 `
    src\Assimp.Maui.Windows\Maui\assimpmaui.cxx `
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
}
else {
    Write-Error "ERROR: Windows compilation failed for $Arch."
    exit 1
}