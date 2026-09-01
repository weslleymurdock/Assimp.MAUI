# Assimp.MAUI

[![NuGet Version](https://img.shields.io/nuget/v/Assimp.MAUI.svg)](https://www.nuget.org/packages/Assimp.MAUI)
[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE.md)

**Assimp.MAUI** is a .NET MAUI wrapper and cross-platform binary distribution for the [Open Asset Import Library (Assimp)](https://github.com/assimp/assimp). This package bundles pre-compiled native Assimp binaries targeting all .NET MAUI supported platforms and Runtime Identifiers (RIDs), enabling seamless loading and processing of over 40 3D model formats (such as OBJ, FBX, GLTF, COLLADA, and STL) in cross-platform applications.

---

## 🚀 Supported Platforms (Target Frameworks & RIDs)

This package includes native binaries optimized for the following .NET MAUI targets:

* **Android:** `net10.0-android` (`arm64-v8a`, `armeabi-v7a`, `x86_64`)
* **iOS:** `net10.0-ios` (`ios-arm64`, `iossimulator-arm64`, `iossimulator-x64`)
* **macOS (Mac Catalyst):** `net10.0-maccatalyst` (`maccatalyst-x64`, `maccatalyst-arm64`)
* **Windows:** `net10.0-windows10.0.19041.0` (`win10-x64`, `win10-arm64`)

---

## 📦 Installation

Install the package into your .NET MAUI project via NuGet Package Manager or the .NET CLI:

```bash
dotnet add package Assimp.MAUI
```
Or add it directly to your project's .csproj file:

```xml
<ItemGroup>
  <PackageReference Include="Assimp.MAUI" Version="6.0.5.0-rc1"/>
</ItemGroup>
```

## 💻 Usage Example

TBD.

## 🛠️ Build Automation (GitHub Actions)

This repository utilizes GitHub Actions to natively compile Assimp C++ source code across host runners for each target platform, packaging the final .nupkg artifact automatically.


## 📜 License and Attribution

This project is licensed under the BSD-3-Clause License, fully adhering to the original Assimp license and embedded third-party software terms.

Assimp.MAUI (Wrapper & Infrastructure): Copyright (c) 2026, Weslley Luiz (and contributors).

Assimp Library: Copyright (c) 2006-2024, Assimp Development Team.

Embedded Dependencies (Poly2Tri, zlib, etc.): Retain their respective original copyright notices.

Refer to the LICENSE.md file in this repository for full license terms.