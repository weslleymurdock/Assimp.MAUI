#!/usr/bin/env bash
set -e

ASSIMP_TAG="${ASSIMP_TAG:-v6.0.6}"
MACOS_DEPLOYMENT_TARGET="14.0"
PUBLISH_LOCAL=true
SSH_HOST=""
REMOTE_BUILD=false
case "${CI:-}" in
  true|1|yes|TRUE|YES) PUBLISH_LOCAL=false ;;
esac

# --- Argument Parsing ---
BUILD_ARM64=false
BUILD_X64=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -arm64) BUILD_ARM64=true ;;
    -x64) BUILD_X64=true ;;
    --ci|--no-publish-local) PUBLISH_LOCAL=false ;;
    --local|--publish-local) PUBLISH_LOCAL=true ;;
    --ssh)
      [ "$#" -ge 2 ] || { echo "Missing host after --ssh"; exit 1; }
      SSH_HOST="$2"
      shift
      ;;
    --remote-build) REMOTE_BUILD=true ;;
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

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"

clean_maccatalyst_outputs() {
  rm -rf -- "$REPO_ROOT/src/Assimp.Maui/Platforms/MacCatalyst/Maui"
  for ARCH in "${ARCHS[@]}"; do
    rm -rf -- "$REPO_ROOT/src/Assimp.Maui/Platforms/MacCatalyst/runtimes/maccatalyst-$ARCH/native"
  done
}

if [ -n "$SSH_HOST" ] && [ "$REMOTE_BUILD" = false ]; then
  command -v ssh >/dev/null 2>&1 || { echo "ERROR: ssh is required for --ssh"; exit 1; }
  command -v scp >/dev/null 2>&1 || { echo "ERROR: scp is required for --ssh"; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "ERROR: tar is required for --ssh"; exit 1; }

  clean_maccatalyst_outputs
  LOCAL_JOB="$(mktemp -d "${TMPDIR:-/tmp}/assimp-maui-maccatalyst-ssh.XXXXXX")"
  REMOTE_DIR="$(ssh "$SSH_HOST" 'mktemp -d /tmp/assimp-maui-maccatalyst-ssh.XXXXXX')"
  [ -n "$REMOTE_DIR" ] || { echo "ERROR: remote temporary directory was not created"; exit 1; }
  cleanup_remote() {
    ssh "$SSH_HOST" "rm -rf '$REMOTE_DIR'" >/dev/null 2>&1 || true
    rm -rf -- "$LOCAL_JOB"
  }
  trap cleanup_remote EXIT

  tar -czf "$LOCAL_JOB/source.tar.gz" \
    --exclude='.git' --exclude='*/.git/*' \
    -C "$REPO_ROOT" external/assimp src/Assimp.Maui swig scripts/assimp-maccatalyst.sh
  scp "$LOCAL_JOB/source.tar.gz" "$SSH_HOST:$REMOTE_DIR/source.tar.gz"
  ssh "$SSH_HOST" "mkdir -p '$REMOTE_DIR/source' && tar -xzf '$REMOTE_DIR/source.tar.gz' -C '$REMOTE_DIR/source'"

  remote_command="cd '$REMOTE_DIR/source' && bash scripts/assimp-maccatalyst.sh --remote-build --local"
  [ "$BUILD_ARM64" = true ] && remote_command+=" -arm64"
  [ "$BUILD_X64" = true ] && remote_command+=" -x64"
  ssh "$SSH_HOST" "$remote_command"
  ssh "$SSH_HOST" "tar -czf '$REMOTE_DIR/result.tar.gz' -C '$REMOTE_DIR/source' src/Assimp.Maui/Platforms/MacCatalyst"
  scp "$SSH_HOST:$REMOTE_DIR/result.tar.gz" "$LOCAL_JOB/result.tar.gz"
  tar -xzf "$LOCAL_JOB/result.tar.gz" -C "$REPO_ROOT"
  echo "Mac Catalyst build completed on $SSH_HOST and copied to $REPO_ROOT/src/Assimp.Maui/Platforms/MacCatalyst"
  exit 0
fi

if [ "$PUBLISH_LOCAL" = true ]; then
  echo "=== Local artifact publishing enabled ==="
  clean_maccatalyst_outputs
fi

echo "=== 0. Cleaning previous builds ==="
for ARCH in "${ARCHS[@]}"; do
  rm -rf "build/maccatalyst-$ARCH"
done
rm -rf src/Assimp.Maui/Platforms/MacCatalyst/Maui

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
if [ "$REMOTE_BUILD" = true ]; then
  echo "Using Assimp source transferred by the SSH caller."
elif [ ! -d "external/assimp/.git" ]; then
  echo "Cloning Assimp into external/assimp at tag $ASSIMP_TAG..."
  git clone --depth 1 --branch "$ASSIMP_TAG" https://github.com/assimp/assimp.git external/assimp
else
  echo "Directory external/assimp found. Ensuring tag $ASSIMP_TAG..."
  cd external/assimp
  git fetch --tags --depth 1 origin tag "$ASSIMP_TAG"
  git checkout "$ASSIMP_TAG"
  cd ../..
fi

if [ "$REMOTE_BUILD" = false ]; then
  cd external/assimp
  git submodule update --init --recursive --depth 1
  cd ../..
fi

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

mkdir -p src/Assimp.Maui/Platforms/MacCatalyst/Maui

prepare_swig_parse_tree() {
  SWIG_PARSE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assimp-swig-headers.XXXXXX")"
  mkdir -p "$SWIG_PARSE_ROOT/assimp"
  cp -R external/assimp/include/assimp/. "$SWIG_PARSE_ROOT/assimp/"
  sed 's#external/assimp/include/assimp/#assimp/#g' swig/assimp.i > "$SWIG_PARSE_ROOT/assimp.i"

  local header temp
  while IFS= read -r -d '' header; do
    temp="$header.tmp"
    awk '
      function is_force32(value) {
        return value ~ /^[[:space:]]*_[A-Za-z0-9]+_Force32Bit[[:space:]]*=[[:space:]]*INT_MAX/ || value ~ /^[[:space:]]*FORCE_32BIT[[:space:]]*=[[:space:]]*INT_MAX/
      }
      function emit_pending_doc() {
        printf "%s", pending_doc
        pending_doc = ""
        pending = 0
      }
      BEGIN { in_doc = 0; pending = 0; pending_doc = "" }
      {
        line = $0
        if (in_doc) {
          pending_doc = pending_doc line ORS
          if (line ~ /\*\//) { in_doc = 0; pending = 1 }
          next
        }
        if (pending) {
          if (line ~ /^[[:space:]]*#ifndef SWIG[[:space:]]*$/) {
            if ((getline sentinel) <= 0) { emit_pending_doc(); print line; next }
            if (is_force32(sentinel)) {
              if ((getline endif_line) > 0 && endif_line ~ /^[[:space:]]*#endif/) {
                pending_doc = ""; pending = 0
                print "    /* SWIG parser: omitted 32-bit enum sentinel. */"
                next
              }
              emit_pending_doc(); print line; print sentinel
              if (endif_line != "") print endif_line
              next
            }
            emit_pending_doc(); print line; print sentinel
            next
          }
          emit_pending_doc()
        }
        if (line ~ /^[[:space:]]*\/\*\*/) {
          pending_doc = line ORS
          if (line !~ /\*\//) { in_doc = 1 } else { pending = 1 }
          next
        }
        if (line ~ /^[[:space:]]*#ifndef SWIG[[:space:]]*$/) {
          if ((getline sentinel) <= 0) { print line; next }
          if (is_force32(sentinel)) {
            if ((getline endif_line) > 0 && endif_line ~ /^[[:space:]]*#endif/) {
              print "    /* SWIG parser: omitted 32-bit enum sentinel. */"
              next
            }
            print line; print sentinel
            if (endif_line != "") print endif_line
            next
          }
          print line; print sentinel
          next
        }
        print line
      }
      END { if (in_doc || pending) printf "%s", pending_doc }
    ' "$header" > "$temp"
    # Keep the workaround line-scoped: equivalent to sed on `}; //! enum ...`.
    sed -E 's/^([[:space:]]*};)[[:space:]]*\/\/!+ enum.*$/\1/' "$temp" > "$header"
    rm -f "$temp"
  done < <(find "$SWIG_PARSE_ROOT/assimp" -type f -name '*.h' -print0)
}

prepare_swig_parse_tree

# For static libraries on Mac Catalyst, DllImport in C# points to "__Internal"
SWIG_OUT="src/Assimp.Maui/Platforms/MacCatalyst/Maui"
SWIG_ARGS=(
  -c++ -csharp
  -namespace Assimp.Maui
  -dllimport __Internal
  -outdir "$SWIG_OUT"
  -o "$SWIG_OUT/assimpmaui.cxx"
  "$SWIG_PARSE_ROOT/assimp.i"
)

echo "Using $(swig -version 2>&1 | awk '/SWIG Version/{print $3; exit}') with Doxygen-enabled C# generation."
swig -doxygen -I"$SWIG_PARSE_ROOT" "${SWIG_ARGS[@]}"
rm -rf "$SWIG_PARSE_ROOT"

echo "=== 5. Compiling Native SWIG Static Wrapper (.a) for selected Architectures ==="
for ARCH in "${ARCHS[@]}"; do
  BUILD_DIR="build/maccatalyst-$ARCH"
  echo "Compiling wrapper for $ARCH..."

  xcrun -sdk macosx clang++ -c -O3 \
    -target "${ARCH}-apple-ios${MACOS_DEPLOYMENT_TARGET}-macabi" \
    src/Assimp.Maui/Platforms/MacCatalyst/Maui/assimpmaui.cxx \
    -Iexternal/assimp/include \
    -I"${BUILD_DIR}/include" \
    -o "${BUILD_DIR}/lib/assimpmaui.o"
  
  ar rcs "${BUILD_DIR}/lib/libassimpmaui.a" "${BUILD_DIR}/lib/assimpmaui.o"

  if [ "$PUBLISH_LOCAL" = true ]; then
    RUNTIME_DIR="src/Assimp.Maui/Platforms/MacCatalyst/runtimes/maccatalyst-$ARCH/native"
    mkdir -p "$RUNTIME_DIR"
    cp -f "${BUILD_DIR}/lib/"*.a "$RUNTIME_DIR/"
    echo "Published Mac Catalyst $ARCH assets to $RUNTIME_DIR"
  fi
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
