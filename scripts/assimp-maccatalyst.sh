#!/usr/bin/env bash
set -e

ASSIMP_TAG="v6.0.5"
MACOS_DEPLOYMENT_TARGET="14.0"

# --- Argument Parsing ---
BUILD_ARM64=false
BUILD_X64=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -arm64) BUILD_ARM64=true ;;
    -x64) BUILD_X64=true ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# If no specific architecture was provided, default to BOTH
if [ "$BUILD_ARM64" = false ] && [ "$BUILD_X64" = false ]; then
  BUILD_ARM64=true
  BUILD_X64=true
fi

# Define architectures array based on selections
ARCHS=()
if [ "$BUILD_ARM64" = true ]; then ARCHS+=("arm64"); fi
if [ "$BUILD_X64" = true ]; then ARCHS+=("x86_64"); fi

echo "=== 0. Cleaning previous builds ==="
for ARCH in "${ARCHS[@]}"; do
  rm -rf "build/maccatalyst-$ARCH"
done
rm -rf src/Assimp.Maui.MacCatalyst/Maui

echo "=== 1. Checking System Dependencies (Homebrew) ==="
for pkg in cmake swig ninja; do
  if ! brew list --formula | grep -q "^${pkg}\$"; then
    echo "Installing missing package: $pkg..."
    brew install "$pkg"
  else
    echo "Package $pkg is already installed."
  fi
done

echo "=== 2. Cloning Assimp Repository (Tag $ASSIMP_TAG) ==="
mkdir -p external
if [ ! -d "external/assimp/.git" ]; then
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
cd ../..

echo "=== 3. Configuring and Building Assimp for selected Mac Catalyst Architectures ==="
echo "Architectures to build: ${ARCHS[*]}"

for ARCH in "${ARCHS[@]}"; do
  BUILD_DIR="build/maccatalyst-$ARCH"
  echo "---------------------------------------------------"
  echo "Building Mac Catalyst for Architecture: $ARCH"
  echo "---------------------------------------------------"
  
  mkdir -p "$BUILD_DIR"

  # CMake configuration for Mac Catalyst using macabi target and disabling internal zlib
  cmake -S external/assimp -B "$BUILD_DIR" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT=macosx \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_C_FLAGS="-target ${ARCH}-apple-ios${MACOS_DEPLOYMENT_TARGET}-macabi" \
    -DCMAKE_CXX_FLAGS="-target ${ARCH}-apple-ios${MACOS_DEPLOYMENT_TARGET}-macabi" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DASSIMP_BUILD_TESTS=OFF \
    -DASSIMP_BUILD_ASSIMP_TOOLS=OFF \
    -DASSIMP_BUILD_ZLIB=OFF \
    -DASSIMP_INSTALL_PDB=OFF \
    -DASSIMP_INJECT_DEBUG_POSTFIX=OFF

  echo "Compiling base library (libassimp.a) for $ARCH..."
  cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu)
done

echo "=== 4. Generating SWIG C# Bindings for Mac Catalyst ==="
if [ ! -f "swig/assimp.i" ]; then
  echo "ERROR: File swig/assimp.i not found! Make sure to create it."
  exit 1
fi

mkdir -p src/Assimp.Maui.MacCatalyst/Maui

# For static libraries on Mac Catalyst, DllImport in C# points to "__Internal"
swig -c++ -csharp \
  -namespace Assimp.Maui \
  -dllimport __Internal \
  -outdir src/Assimp.Maui.MacCatalyst/Maui \
  -o src/Assimp.Maui.MacCatalyst/Maui/assimpmaui.cxx \
  swig/assimp.i

echo "=== 5. Compiling Native SWIG Static Wrapper (.a) for selected Architectures ==="
for ARCH in "${ARCHS[@]}"; do
  BUILD_DIR="build/maccatalyst-$ARCH"
  echo "Compiling wrapper for $ARCH..."

  xcrun -sdk macosx clang++ -c -O3 \
    -target "${ARCH}-apple-ios${MACOS_DEPLOYMENT_TARGET}-macabi" \
    src/Assimp.Maui.MacCatalyst/Maui/assimpmaui.cxx \
    -Iexternal/assimp/include \
    -I"${BUILD_DIR}/include" \
    -o "${BUILD_DIR}/lib/assimpmaui.o"
  
  ar rcs "${BUILD_DIR}/lib/libassimpmaui.a" "${BUILD_DIR}/lib/assimpmaui.o"
done

echo "=== 6. Build Result ==="
ALL_SUCCESS=true
for ARCH in "${ARCHS[@]}"; do
  BUILD_DIR="build/maccatalyst-$ARCH"
  if [ -f "$BUILD_DIR/lib/libassimpmaui.a" ]; then
    echo "SUCCESS: Mac Catalyst binaries successfully compiled for $ARCH!"
    ls -lh "$BUILD_DIR/lib/"*.a
  else
    echo "ERROR: Wrapper compilation for Mac Catalyst ($ARCH) failed."
    ALL_SUCCESS=false
  fi
done

if [ "$ALL_SUCCESS" = false ]; then
  exit 1
fi