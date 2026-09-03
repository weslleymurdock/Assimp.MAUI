#!/usr/bin/env bash
set -e

ASSIMP_TAG="v6.0.5"
NDK_VERSION="26.1.10909125" # NDK r26b
MIN_SDK_VERSION="24"
TARGET_SDK_VERSION="37"

# --- Argument Parsing ---
BUILD_ARM=false
BUILD_ARM64=false
BUILD_X86=false
BUILD_X64=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -arm) BUILD_ARM=true ;;
    -arm64) BUILD_ARM64=true ;;
    -x86) BUILD_X86=true ;;
    -x64) BUILD_X64=true ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# If no specific architecture was provided, default to ALL
if [ "$BUILD_ARM" = false ] && [ "$BUILD_ARM64" = false ] && [ "$BUILD_X86" = false ] && [ "$BUILD_X64" = false ]; then
  BUILD_ARM=true
  BUILD_ARM64=true
  BUILD_X86=true
  BUILD_X64=true
fi

# Define the ABIs array based on selections
ABIS=()
if [ "$BUILD_ARM" = true ]; then ABIS+=("armeabi-v7a"); fi
if [ "$BUILD_ARM64" = true ]; then ABIS+=("arm64-v8a"); fi
if [ "$BUILD_X86" = true ]; then ABIS+=("x86"); fi
if [ "$BUILD_X64" = true ]; then ABIS+=("x86_64"); fi

echo "=== 0. Cleaning previous builds ==="
for ABI in "${ABIS[@]}"; do
  rm -rf "build/android-$ABI"
done
rm -rf swig_output/android

echo "=== 1. Checking System Dependencies (Apt) ==="
NEEDED_PACKAGES=()
for pkg in cmake build-essential swig ninja-build zip curl unzip openjdk-17-jdk; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    NEEDED_PACKAGES+=("$pkg")
  fi
done

if [ ${#NEEDED_PACKAGES[@]} -gt 0 ]; then
  echo "Installing missing packages: ${NEEDED_PACKAGES[*]}..."
  sudo apt-get update
  sudo apt-get install -y "${NEEDED_PACKAGES[@]}"
else
  echo "All system packages are already installed."
fi

echo "=== 2. Checking/Configuring Android SDK and NDK ==="
LOCAL_SDK_DIR="$HOME/.android-sdk"

if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
  export ANDROID_HOME="$LOCAL_SDK_DIR"
  export ANDROID_SDK_ROOT="$LOCAL_SDK_DIR"
fi

SDK_ROOT="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
TARGET_NDK_PATH="$SDK_ROOT/ndk/$NDK_VERSION"

if [ -d "$TARGET_NDK_PATH" ]; then
  export ANDROID_NDK_HOME="$TARGET_NDK_PATH"
  echo "Android NDK detected at: $ANDROID_NDK_HOME"
else
  echo "NDK not found. Installing SDK Manager and NDK ($NDK_VERSION)..."
  mkdir -p "$SDK_ROOT/cmdline-tools"

  CMDLINE_ZIP="commandlinetools-linux-11076708_latest.zip"
  if [ ! -f "/tmp/$CMDLINE_ZIP" ]; then
    echo "Downloading Android Command-line Tools..."
    curl -sSL "https://dl.google.com/android/repository/$CMDLINE_ZIP" -o "/tmp/$CMDLINE_ZIP"
  fi

  if [ ! -d "$SDK_ROOT/cmdline-tools/latest" ]; then
    unzip -q -o "/tmp/$CMDLINE_ZIP" -d "$SDK_ROOT/cmdline-tools"
    mv "$SDK_ROOT/cmdline-tools/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest" 2>/dev/null || true
  fi

  SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  echo "Accepting Android SDK licenses..."
  yes | "$SDKMANAGER" --licenses --sdk_root="$SDK_ROOT" > /dev/null 2>&1 || true

  echo "Installing NDK $NDK_VERSION and Platform $TARGET_SDK_VERSION..."
  "$SDKMANAGER" --install "ndk;$NDK_VERSION" "platforms;android-$TARGET_SDK_VERSION" --sdk_root="$SDK_ROOT"
  
  export ANDROID_NDK_HOME="$TARGET_NDK_PATH"
fi

echo "=== 3. Cloning Assimp Repository (Tag $ASSIMP_TAG) ==="
if [ ! -d "external/assimp" ]; then
  echo "Cloning Assimp into external/assimp at tag $ASSIMP_TAG..."
  git clone --depth 1 --branch "$ASSIMP_TAG" https://github.com/assimp/assimp.git external/assimp
else
  echo "Directory external/assimp found. Ensuring tag $ASSIMP_TAG..."
  cd external/assimp
  git fetch --tags --depth 1 origin tag "$ASSIMP_TAG"
  git checkout "$ASSIMP_TAG"
  cd ../..
fi

cd external/assimp
git submodule update --init --recursive --depth 1
cd ../../

# CFLAGS/CXXFLAGS for file I/O compatibility and suppressing implicit declaration warnings in contribs
CMAKE_C_FLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -Wno-implicit-function-declaration -Wno-error=implicit-function-declaration"
CMAKE_CXX_FLAGS="-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"

echo "=== 4. Configuring and Building Assimp Base Library for selected ABIs ==="
echo "Targeting Minimum SDK: $MIN_SDK_VERSION | Target SDK: $TARGET_SDK_VERSION"
echo "Architectures to build: ${ABIS[*]}"

for ABI in "${ABIS[@]}"; do
  BUILD_DIR="build/android-$ABI"
  echo "---------------------------------------------------"
  echo "Building Assimp for ABI: $ABI"
  echo "---------------------------------------------------"
  
  mkdir -p "$BUILD_DIR"

  cmake -S external/assimp -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$MIN_SDK_VERSION" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
    -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" \
    -DASSIMP_BUILD_TESTS=OFF \
    -DASSIMP_BUILD_ASSIMP_TOOLS=OFF \
    -DASSIMP_BUILD_ZLIB=ON \
    -DASSIMP_INSTALL_PDB=OFF \
    -DASSIMP_INJECT_DEBUG_POSTFIX=OFF

  cmake --build "$BUILD_DIR" --config Release -j$(nproc 2>/dev/null || echo 4)
done

echo "=== 5. Generating SWIG C# Bindings for Android ==="
if [ ! -f "swig/assimp.i" ]; then
  echo "ERROR: File swig/assimp.i not found! Make sure to create it."
  exit 1
fi

mkdir -p swig_output/android

swig -c++ -csharp \
  -namespace Assimp.Maui \
  -dllimport "assimpmaui" \
  -outdir src/Assimp.Maui.Android/Maui \
  -o src/Assimp.Maui.Android/Maui/assimpmaui.cxx \
  swig/assimp.i

echo "=== 6. Compiling Native SWIG Wrapper Library (libassimpmaui.so) for each ABI ==="
for ABI in "${ABIS[@]}"; do
  BUILD_DIR="build/android-$ABI"
  echo "Compiling wrapper shared library for $ABI..."

  # Seleciona o compilador Clang correspondente à ABI no NDK toolchain
  case "$ABI" in
    armeabi-v7a) TOOLCHAIN_ARCH="armv7a-linux-androideabi" ;;
    arm64-v8a)   TOOLCHAIN_ARCH="aarch64-linux-android" ;;
    x86)         TOOLCHAIN_ARCH="i686-linux-android" ;;
    x86_64)      TOOLCHAIN_ARCH="x86_64-linux-android" ;;
  esac

  HOST_TAG="linux-x86_64"
  CLANG="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin/clang++"

  # Compila o wrapper como uma Shared Library apontando para a libassimp gerada
  "$CLANG" -shared -O3 \
    --target="${TOOLCHAIN_ARCH}${MIN_SDK_VERSION}" \
    src/Assimp.Maui.Android/Maui/assimpmaui.cxx \
    -Iexternal/assimp/include \
    -I"$BUILD_DIR/include" \
    -L"$BUILD_DIR/bin" \
    -lassimp \
    -o "$BUILD_DIR/bin/libassimpmaui.so"
done

echo "=== 7. Build Result ==="
ALL_SUCCESS=true
for ABI in "${ABIS[@]}"; do
  BUILD_DIR="build/android-$ABI"
  if [ -f "$BUILD_DIR/bin/libassimp.so" ] && [ -f "$BUILD_DIR/bin/libassimpmaui.so" ]; then
    echo "SUCCESS: Binaries compiled successfully for $ABI!"
    ls -lh "$BUILD_DIR/bin/"libassimp*.so
  else
    echo "ERROR: Binaries were not fully generated for $ABI."
    ALL_SUCCESS=false
  fi
done

if [ "$ALL_SUCCESS" = false ]; then
  exit 1
fi