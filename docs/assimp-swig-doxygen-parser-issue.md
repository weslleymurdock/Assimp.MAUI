# Assimp headers fail SWIG C# generation with `-doxygen`

## Proposed issue title

`SWIG C# Doxygen parser rejects valid Assimp enum sentinel declarations`

## Summary

When the Assimp C/C++ headers are passed to SWIG for C# generation with
`-doxygen`, SWIG reports a syntax error in `mesh.h` even though the header is
valid C++ and compiles normally:

```text
external/assimp/include/assimp/mesh.h:456: Error: Syntax error in input(1).
```

The failure affects the native binding builds for Android, iOS, Mac Catalyst,
and Windows.

## Reproduction

Using the Assimp headers from the `v6.0.6` tag and SWIG 4.5.1:

```bash
swig -c++ -csharp -doxygen \
  -namespace Assimp.Maui \
  -dllimport assimpmaui \
  -Iexternal/assimp/include \
  -outdir out \
  -o out/assimpmaui.cxx \
  swig/assimp.i
```

The first reported failure is the closing line of this valid enum:

```cpp
/**
 * This value is not used. It is just here to force the
 * compiler to map this enum to a 32 Bit integer.
 */
#ifndef SWIG
    _aiPrimitiveType_Force32Bit = INT_MAX
#endif
}; //! enum aiPrimitiveType
```

Equivalent declarations are present in `anim.h`, `light.h`, `material.h`,
`mesh.h`, and `metadata.h`.

## Expected behavior

SWIG should accept the declarations above, preserve their Doxygen comments,
and generate the C# bindings without changing the public names of the
generated types or members.

## Temporary downstream workaround

This repository currently creates a temporary header projection only while
SWIG parses the interface. The Assimp submodule and its original headers are
not modified, and the native C++ compiler continues to use the original
headers.

The projection performs two narrowly scoped parser workarounds:

1. It omits the non-SWIG 32-bit enum sentinel block when that block is directly
   attached to its Doxygen comment.
2. It performs a line-level replacement equivalent to the following `sed`
   operation, changing only the closing line that contains `//! enum`:

   ```bash
   sed -E 's/^([[:space:]]*};)[[:space:]]*\/\/!+ enum.*$/\1/'
   ```

All other Doxygen comments are passed to SWIG unchanged. SWIG is still invoked
with `-doxygen`; disabling Doxygen is not an acceptable workaround because the
generated C# API must contain XML documentation comments.

## Validation

With the temporary projection and SWIG 4.5.1:

```text
SWIG exit code: 0
Generated C# files: 97
Generated XML documentation comment lines: 2173
```

The generated names remain controlled by the existing `swig/assimp.i`
interface and no rename rule was added as part of this workaround.

## Suggested upstream fix

Please add a regression test covering an enum that contains:

- a Doxygen comment immediately before an `#ifndef SWIG` sentinel;
- an `INT_MAX` force-32-bit enumerator; and
- a trailing `//! enum ...` comment after the closing brace.

The parser should treat this as valid C++ input and emit the Doxygen text for
the target language. If the parser cannot support this form, Assimp and SWIG
should agree on a documented, portable spelling that preserves the comments
and remains valid for the C++ compiler.

## Pull request proposal

The corresponding upstream pull request should:

- fix the SWIG Doxygen parser or add the required C++ parser regression;
- add a C# generation test that checks both successful generation and emitted
  XML documentation comments;
- verify that the generated public names are unchanged; and
- run the test against the Assimp headers used by the Android, Apple, and
  Windows binding jobs.

