%module(directors="1") Assimp

%{
/* NATIVE HEADERS AND MACRO FIXES */
#define PACK_STRUCT
#include <assimp/cimport.h>
#include <assimp/cfileio.h>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <assimp/types.h>

/* C++ DIRECTORS FOR CALLBACKS */
class LogStream {
public:
    virtual ~LogStream() {}
    virtual void OnLogMessage(const char* message) = 0;
    static void CCallback(const char* message, char* user) {
        if (user) reinterpret_cast<LogStream*>(user)->OnLogMessage(message);
    }
    aiLogStream GetNative() {
        aiLogStream stream;
        stream.callback = &LogStream::CCallback;
        stream.user = reinterpret_cast<char*>(this);
        return stream;
    }
};

class File {
public:
    virtual ~File() {}
    virtual size_t Read(char* buffer, size_t size, size_t count) = 0;
    virtual size_t Write(const char* buffer, size_t size, size_t count) = 0;
    virtual size_t Tell() = 0;
    virtual aiReturn Seek(size_t offset, aiOrigin origin) = 0;
    virtual void Flush() = 0;

    static size_t CRead(aiFile* pFile, char* pBuffer, size_t size, size_t count) {
        return reinterpret_cast<File*>(pFile->UserData)->Read(pBuffer, size, count);
    }
    static size_t CWrite(aiFile* pFile, const char* pBuffer, size_t size, size_t count) {
        return reinterpret_cast<File*>(pFile->UserData)->Write(pBuffer, size, count);
    }
    static size_t CTell(aiFile* pFile) {
        return reinterpret_cast<File*>(pFile->UserData)->Tell();
    }
    static aiReturn CSeek(aiFile* pFile, size_t offset, aiOrigin origin) {
        return reinterpret_cast<File*>(pFile->UserData)->Seek(offset, origin);
    }
    static void CFlush(aiFile* pFile) {
        reinterpret_cast<File*>(pFile->UserData)->Flush();
    }
};

class FileSystem {
public:
    virtual ~FileSystem() {}
    virtual File* Open(const char* fileName, const char* openMode) = 0;
    virtual void Close(File* pFile) = 0;

    static aiFile* COpen(aiFileIO* pFileIO, const char* fileName, const char* openMode) {
        FileSystem* fs = reinterpret_cast<FileSystem*>(pFileIO->UserData);
        File* f = fs->Open(fileName, openMode);
        if (!f) return nullptr;
        aiFile* aif = new aiFile();
        aif->ReadProc = &File::CRead;
        aif->WriteProc = &File::CWrite;
        aif->TellProc = &File::CTell;
        aif->SeekProc = &File::CSeek;
        aif->FlushProc = &File::CFlush;
        aif->UserData = reinterpret_cast<char*>(f);
        return aif;
    }

    static void CClose(aiFileIO* pFileIO, aiFile* pFile) {
        FileSystem* fs = reinterpret_cast<FileSystem*>(pFileIO->UserData);
        File* f = reinterpret_cast<File*>(pFile->UserData);
        fs->Close(f);
        delete pFile;
    }

    aiFileIO GetNative() {
        aiFileIO io;
        io.OpenProc = &FileSystem::COpen;
        io.CloseProc = &FileSystem::CClose;
        io.UserData = reinterpret_cast<char*>(this);
        return io;
    }
};
%}

/* .NET & SWIG base types */
%include "stdint.i"
%include "typemaps.i"
%include "enums.swg"

/* Enabling Directors */
%feature("director") LogStream;
%feature("director") File;
%feature("director") FileSystem;

class LogStream {
public:
    virtual ~LogStream();
    virtual void OnLogMessage(const char* message) = 0;
    aiLogStream GetNative();
};

class File {
public:
    virtual ~File();
    virtual size_t Read(char* buffer, size_t size, size_t count) = 0;
    virtual size_t Write(const char* buffer, size_t size, size_t count) = 0;
    virtual size_t Tell() = 0;
    virtual aiReturn Seek(size_t offset, aiOrigin origin) = 0;
    virtual void Flush() = 0;
};

class FileSystem {
public:
    virtual ~FileSystem();
    virtual File* Open(const char* fileName, const char* openMode) = 0;
    virtual void Close(File* pFile) = 0;
    aiFileIO GetNative();
};

/* C# CONVENTIONS (PascalCase) & TYPE MAPPINGS */

/* flag enums thats exceeds Int32 nativamente to uint */
%typemap(csbase) aiPostProcessSteps "uint";
%typemap(csbase) aiImporterFlags "uint";

/* Resolves enums formatting. 
 * E.g: aiProcess_CalcTangentSpace -> CalcTangentSpace
 * aiShadingMode_NoShading -> NoShading */
%rename("%(regex:/^ai[a-zA-Z0-9]+_([a-zA-Z0-9]+)/\\1/)s", %$isenumitem) "";

/* General proprs and structs rules */
%rename("%(regex:/^ai(.*)/\\1/)s") "";
%rename("%(regex:/^m([A-Z].*)/\\1/)s", %$isvariable) "";
%rename("%(regex:/^m_([a-zA-Z].*)/\\1/)s", %$isvariable) "";

/* Macros and Parsing Errors fixes */
#define __attribute__(x)
#define AI_NO_EXCEPT
#define PACK_STRUCT

typedef float ai_real;
typedef int ai_int;
typedef unsigned int ai_uint;

/* Hides C++ and incompatible Templates */
%ignore aiString::Append;
%ignore aiString::Clear;
%ignore aiMaterial::Get;
%ignore aiMaterial::GetTexture;
%ignore aiMaterial::AddProperty;
%ignore aiMaterial::AddBinaryProperty;
%ignore aiMaterial::RemoveProperty;
%ignore aiMaterial::Clear;
%ignore aiMaterial::CopyPropertyList;

/* Ignores GetAiType conflicting functions at  metadata avoiding ambiguity of GCC/Clang */
%ignore GetAiType;

/* Assimp C API Headers Includes  */
%include "external/assimp/include/assimp/defs.h"
%include "external/assimp/include/assimp/types.h"
%include "external/assimp/include/assimp/vector2.h"
%include "external/assimp/include/assimp/vector3.h"
%include "external/assimp/include/assimp/color4.h"
%include "external/assimp/include/assimp/matrix3x3.h"
%include "external/assimp/include/assimp/matrix4x4.h"
%include "external/assimp/include/assimp/quaternion.h"
%include "external/assimp/include/assimp/aabb.h"

%include "external/assimp/include/assimp/postprocess.h"
%include "external/assimp/include/assimp/texture.h"
%include "external/assimp/include/assimp/mesh.h"
%include "external/assimp/include/assimp/light.h"
%include "external/assimp/include/assimp/camera.h"
%include "external/assimp/include/assimp/material.h"

%include "external/assimp/include/assimp/anim.h"
%include "external/assimp/include/assimp/metadata.h"
%include "external/assimp/include/assimp/cfileio.h"
%include "external/assimp/include/assimp/scene.h"
%include "external/assimp/include/assimp/cimport.h"