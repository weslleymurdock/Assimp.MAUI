#!/usr/bin/env bash
set -e

ASSIMP_TAG="v6.0.5"
IOS_DEPLOYMENT_TARGET="14.0"

# --- Argument Parsing ---
BUILD_ARM64=false
BUILD_SIM_ARM64=false
BUILD_X86_64=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -arm64) BUILD_ARM64=true ;;
    -arm64s) BUILD_SIM_ARM64=true ;;
    -x86_64) BUILD_X86_64=true ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done

# If no specific architecture was provided, default to ALL (device arm64, simulator arm64, simulator x86_64)
if [ "$BUILD_ARM64" = false ] && [ "$BUILD_SIM_ARM64" = false ] && [ "$BUILD_X86_64" = false ]; then
  BUILD_ARM64=true
  BUILD_SIM_ARM64=true
  BUILD_X86_64=true
fi

# Build target configurations array (Name | Arch | Sdk | Subfolder)
TARGETS=()
if [ "$BUILD_ARM64" = true ]; then
  TARGETS+=("iphoneos|arm64|iphoneos|ios-arm64")
fi
if [ "$BUILD_SIM_ARM64" = true ]; then
  TARGETS+=("iphonesimulator|arm64|iphonesimulator|ios-simulator-arm64")
fi
if [ "$BUILD_X86_64" = true ]; then
  TARGETS+=("iphonesimulator|x86_64|iphonesimulator|ios-simulator-x86_64")
fi

echo "=== 0. Cleaning previous builds ==="
for ENTRY in "${TARGETS[@]}"; do
  IFS='|' read -r _ _ _ SUBDIR <<< "$ENTRY"
  rm -rf "build/$SUBDIR"
done
rm -rf src/Assimp.Maui.iOS/Maui

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

echo "=== 3. Configuring and Building Assimp for selected iOS targets ==="
for ENTRY in "${TARGETS[@]}"; do
  IFS='|' read -r SYSROOT ARCH SDK SUBDIR <<< "$ENTRY"
  BUILD_DIR="build/$SUBDIR"
  
  echo "---------------------------------------------------"
  echo "Building Assimp for iOS ($SDK - Arch: $ARCH)"
  echo "---------------------------------------------------"
  
  mkdir -p "$BUILD_DIR"

  cmake -S external/assimp -B "$BUILD_DIR" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DASSIMP_BUILD_TESTS=OFF \
    -DASSIMP_BUILD_ASSIMP_TOOLS=OFF \
    -DASSIMP_BUILD_ZLIB=OFF \
    -DASSIMP_INSTALL_PDB=OFF \
    -DASSIMP_INJECT_DEBUG_POSTFIX=OFF

  echo "Compiling base library (libassimp.a) for $ARCH ($SDK)..."
  cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu)
done

echo "=== 4. Generating SWIG C# Bindings for iOS ==="
if [ ! -f "swig/assimp.i" ]; then
  echo "ERROR: File swig/assimp.i not found! Make sure to create it."
  exit 1
fi

mkdir -p src/Assimp.Maui.iOS/Maui

swig -c++ -csharp \
  -namespace Assimp.Maui \
  -dllimport __Internal \
  -outdir src/Assimp.Maui.iOS/Maui \
  -o src/Assimp.Maui.iOS/Maui/assimpmaui.cxx \
  swig/assimp.i

echo "=== 5. Compiling Native SWIG Wrapper (.a) for selected iOS targets ==="
for ENTRY in "${TARGETS[@]}"; do
  IFS='|' read -r SYSROOT ARCH SDK SUBDIR <<< "$ENTRY"
  BUILD_DIR="build/$SUBDIR"

  echo "Compiling wrapper for $ARCH ($SDK)..."

  xcrun -sdk "$SYSROOT" clang++ -c -O3 \
    -arch "$ARCH" \
    -miphoneos-version-min="$IOS_DEPLOYMENT_TARGET" \
    src/Assimp.Maui.iOS/Maui/assimpmaui.cxx \
    -Iexternal/assimp/include \
    -I"${BUILD_DIR}/include" \
    -o "${BUILD_DIR}/lib/assimpmaui.o"

  ar rcs "${BUILD_DIR}/lib/libassimpmaui.a" "${BUILD_DIR}/lib/assimpmaui.o"
done

echo "=== 6. Build Result ==="
ALL_SUCCESS=true
for ENTRY in "${TARGETS[@]}"; do
  IFS='|' read -r _ ARCH SDK SUBDIR <<< "$ENTRY"
  BUILD_DIR="build/$SUBDIR"

  if [ -f "$BUILD_DIR/lib/libassimpmaui.a" ]; then
    echo "SUCCESS: Binaries successfully compiled for iOS ($SDK - $ARCH)!"
    ls -lh "$BUILD_DIR/lib/"*.a
  else
    echo "ERROR: Wrapper compilation for iOS ($SDK - $ARCH) failed."
    ALL_SUCCESS=false
  fi
done

if [ "$ALL_SUCCESS" = false ]; then
  exit 1
fi