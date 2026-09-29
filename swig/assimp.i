%module(directors="1") Assimp

%{
/* NATIVE HEADERS AND MACRO FIXES */
#define PACK_STRUCT
#include <assimp/cimport.h>
#include <assimp/cfileio.h>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <assimp/types.h>
#include <cstring>

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

static aiNode* AssimpFindNodeRecursive(aiNode* node, const char* name) {
    if (node == nullptr || name == nullptr) {
        return nullptr;
    }

    if (std::strcmp(node->mName.C_Str(), name) == 0) {
        return node;
    }

    for (unsigned int i = 0; i < node->mNumChildren; ++i) {
        aiNode* child = node->mChildren[i];
        aiNode* result = AssimpFindNodeRecursive(child, name);
        if (result != nullptr) {
            return result;
        }
    }

    return nullptr;
}

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

/* --- C# CONVENTIONS & ENUM FIXES --- */

%typemap(csbase) enum aiPostProcessSteps "uint";
%typemap(csbase) enum aiImporterFlags "uint";

/* Ignore internal C/C++ bounds and aliases that break C# generation */
%csconstvalue("ShadingMode_NoShading") aiShadingMode_Unlit;

/* C# PascalCase Renaming for Enum items (removes aiPrefix_) */
%rename("%(regex:/^ai[a-zA-Z0-9]+_([a-zA-Z0-9]+)/\\1/)s", %$isenumitem) "";

/* General renaming rules */
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

/* Ignores GetAiType conflicting functions at metadata avoiding ambiguity of GCC/Clang */
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
/* ------------------------------------------------------------------------- */
/* Engine-oriented accessors                                                 */
/* ------------------------------------------------------------------------- */
/*
 * These extensions expose existing Assimp scene relationships and data
 * through typed accessors. They do not transfer ownership or introduce
 * engine state. Returned pointers remain owned by aiScene.
 *
 * Accessor names are explicitly PascalCase for the generated C# API.
 */

%extend aiScene {
    aiNode* GetRootNode() {
        return self->mRootNode;
    }

    aiMesh* GetMesh(unsigned int index) {
        return index < self->mNumMeshes ? self->mMeshes[index] : nullptr;
    }

    aiMaterial* GetMaterial(unsigned int index) {
        return index < self->mNumMaterials ? self->mMaterials[index] : nullptr;
    }

    aiAnimation* GetAnimation(unsigned int index) {
        return index < self->mNumAnimations ? self->mAnimations[index] : nullptr;
    }

    aiTexture* GetTexture(unsigned int index) {
        return index < self->mNumTextures ? self->mTextures[index] : nullptr;
    }

    aiLight* GetLight(unsigned int index) {
        return index < self->mNumLights ? self->mLights[index] : nullptr;
    }

    aiCamera* GetCamera(unsigned int index) {
        return index < self->mNumCameras ? self->mCameras[index] : nullptr;
    }
}

%extend aiNode {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    aiNode* GetParent() const {
        return self->mParent;
    }

    aiNode* GetChild(unsigned int index) const {
        return index < self->mNumChildren ? self->mChildren[index] : nullptr;
    }

    unsigned int GetChildCount() const {
        return self->mNumChildren;
    }

    unsigned int GetMeshCount() const {
        return self->mNumMeshes;
    }

    unsigned int GetMeshIndex(unsigned int index) const {
        return index < self->mNumMeshes ? self->mMeshes[index] : static_cast<unsigned int>(-1);
    }

    aiNode* FindNode(const char* name) const {
        return AssimpFindNodeRecursive(self, name);
    }

    float GetTransformationElement(unsigned int row, unsigned int column) const {
        if (row >= 4 || column >= 4) {
            return 0.0f;
        }

        const unsigned int index = row * 4 + column;
        switch (index) {
            case 0: return self->mTransformation.a1;
            case 1: return self->mTransformation.a2;
            case 2: return self->mTransformation.a3;
            case 3: return self->mTransformation.a4;
            case 4: return self->mTransformation.b1;
            case 5: return self->mTransformation.b2;
            case 6: return self->mTransformation.b3;
            case 7: return self->mTransformation.b4;
            case 8: return self->mTransformation.c1;
            case 9: return self->mTransformation.c2;
            case 10: return self->mTransformation.c3;
            case 11: return self->mTransformation.c4;
            case 12: return self->mTransformation.d1;
            case 13: return self->mTransformation.d2;
            case 14: return self->mTransformation.d3;
            default: return self->mTransformation.d4;
        }
    }
}

%extend aiMesh {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    unsigned int GetPrimitiveTypes() const {
        return self->mPrimitiveTypes;
    }

    unsigned int GetMaterialIndex() const {
        return self->mMaterialIndex;
    }

    float GetVertexComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mVertices == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mVertices[index][component];
    }

    float GetNormalComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mNormals == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mNormals[index][component];
    }

    float GetTangentComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mTangents == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mTangents[index][component];
    }

    float GetBitangentComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mBitangents == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mBitangents[index][component];
    }

    float GetTextureCoordinateComponent(
        unsigned int channel,
        unsigned int index,
        unsigned int component) const {
        if (channel >= AI_MAX_NUMBER_OF_TEXTURECOORDS ||
            index >= self->mNumVertices ||
            component >= 3 ||
            self->mTextureCoords[channel] == nullptr) {
            return 0.0f;
        }

        return self->mTextureCoords[channel][index][component];
    }

    unsigned int GetTextureCoordinateComponentCount(unsigned int channel) const {
        if (channel >= AI_MAX_NUMBER_OF_TEXTURECOORDS) {
            return 0;
        }

        return self->mTextureCoords[channel] == nullptr
            ? 0
            : self->mNumUVComponents[channel];
    }

    float GetVertexColorComponent(
        unsigned int channel,
        unsigned int index,
        unsigned int component) const {
        if (channel >= AI_MAX_NUMBER_OF_COLOR_SETS ||
            index >= self->mNumVertices ||
            component >= 4 ||
            self->mColors[channel] == nullptr) {
            return 0.0f;
        }

        return self->mColors[channel][index][component];
    }

    unsigned int GetFaceIndexCount(unsigned int faceIndex) const {
        if (faceIndex >= self->mNumFaces || self->mFaces == nullptr) {
            return 0;
        }

        return self->mFaces[faceIndex].mNumIndices;
    }

    unsigned int GetFaceIndex(unsigned int faceIndex, unsigned int index) const {
        if (faceIndex >= self->mNumFaces || self->mFaces == nullptr) {
            return static_cast<unsigned int>(-1);
        }

        const aiFace& face = self->mFaces[faceIndex];
        return index < face.mNumIndices ? face.mIndices[index] : static_cast<unsigned int>(-1);
    }

    aiBone* GetBone(unsigned int index) const {
        return index < self->mNumBones && self->mBones != nullptr
            ? self->mBones[index]
            : nullptr;
    }

    aiAnimMesh* GetAnimMesh(unsigned int index) const {
        return index < self->mNumAnimMeshes && self->mAnimMeshes != nullptr
            ? self->mAnimMeshes[index]
            : nullptr;
    }
}

%extend aiBone {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    unsigned int GetWeightCount() const {
        return self->mNumWeights;
    }

    unsigned int GetWeightVertexId(unsigned int index) const {
        return index < self->mNumWeights && self->mWeights != nullptr
            ? self->mWeights[index].mVertexId
            : static_cast<unsigned int>(-1);
    }

    float GetWeight(unsigned int index) const {
        return index < self->mNumWeights && self->mWeights != nullptr
            ? self->mWeights[index].mWeight
            : 0.0f;
    }

    float GetOffsetMatrixElement(unsigned int row, unsigned int column) const {
        if (row >= 4 || column >= 4) {
            return 0.0f;
        }

        const unsigned int index = row * 4 + column;
        switch (index) {
            case 0: return self->mOffsetMatrix.a1;
            case 1: return self->mOffsetMatrix.a2;
            case 2: return self->mOffsetMatrix.a3;
            case 3: return self->mOffsetMatrix.a4;
            case 4: return self->mOffsetMatrix.b1;
            case 5: return self->mOffsetMatrix.b2;
            case 6: return self->mOffsetMatrix.b3;
            case 7: return self->mOffsetMatrix.b4;
            case 8: return self->mOffsetMatrix.c1;
            case 9: return self->mOffsetMatrix.c2;
            case 10: return self->mOffsetMatrix.c3;
            case 11: return self->mOffsetMatrix.c4;
            case 12: return self->mOffsetMatrix.d1;
            case 13: return self->mOffsetMatrix.d2;
            case 14: return self->mOffsetMatrix.d3;
            default: return self->mOffsetMatrix.d4;
        }
    }
}

%extend aiAnimMesh {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    float GetVertexComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mVertices == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mVertices[index][component];
    }

    float GetNormalComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumVertices || self->mNormals == nullptr || component >= 3) {
            return 0.0f;
        }

        return self->mNormals[index][component];
    }

    float GetWeight() const {
        return self->mWeight;
    }
}

%extend aiAnimation {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    double GetDuration() const {
        return self->mDuration;
    }

    double GetTicksPerSecond() const {
        return self->mTicksPerSecond;
    }

    double GetDurationInSeconds() const {
        return self->mTicksPerSecond > 0.0
            ? self->mDuration / self->mTicksPerSecond
            : 0.0;
    }

    double GetTimeInTicks(double timeInSeconds) const {
        return self->mTicksPerSecond > 0.0
            ? timeInSeconds * self->mTicksPerSecond
            : 0.0;
    }

    aiNodeAnim* GetChannel(unsigned int index) const {
        return index < self->mNumChannels && self->mChannels != nullptr
            ? self->mChannels[index]
            : nullptr;
    }

    aiMeshAnim* GetMeshChannel(unsigned int index) const {
        return index < self->mNumMeshChannels && self->mMeshChannels != nullptr
            ? self->mMeshChannels[index]
            : nullptr;
    }

    aiMeshMorphAnim* GetMorphMeshChannel(unsigned int index) const {
        return index < self->mNumMorphMeshChannels && self->mMorphMeshChannels != nullptr
            ? self->mMorphMeshChannels[index]
            : nullptr;
    }
}

%extend aiNodeAnim {
    const char* GetNodeName() const {
        return self->mNodeName.C_Str();
    }

    unsigned int GetPositionKeyCount() const {
        return self->mNumPositionKeys;
    }

    unsigned int GetRotationKeyCount() const {
        return self->mNumRotationKeys;
    }

    unsigned int GetScalingKeyCount() const {
        return self->mNumScalingKeys;
    }

    double GetPositionKeyTime(unsigned int index) const {
        return index < self->mNumPositionKeys && self->mPositionKeys != nullptr
            ? self->mPositionKeys[index].mTime
            : 0.0;
    }

    float GetPositionKeyComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumPositionKeys ||
            self->mPositionKeys == nullptr ||
            component >= 3) {
            return 0.0f;
        }

        return self->mPositionKeys[index].mValue[component];
    }

    double GetRotationKeyTime(unsigned int index) const {
        return index < self->mNumRotationKeys && self->mRotationKeys != nullptr
            ? self->mRotationKeys[index].mTime
            : 0.0;
    }

    float GetRotationKeyComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumRotationKeys ||
            self->mRotationKeys == nullptr ||
            component >= 4) {
            return 0.0f;
        }

        switch (component) {
            case 0: return self->mRotationKeys[index].mValue.w;
            case 1: return self->mRotationKeys[index].mValue.x;
            case 2: return self->mRotationKeys[index].mValue.y;
            default: return self->mRotationKeys[index].mValue.z;
        }
    }

    double GetScalingKeyTime(unsigned int index) const {
        return index < self->mNumScalingKeys && self->mScalingKeys != nullptr
            ? self->mScalingKeys[index].mTime
            : 0.0;
    }

    float GetScalingKeyComponent(unsigned int index, unsigned int component) const {
        if (index >= self->mNumScalingKeys ||
            self->mScalingKeys == nullptr ||
            component >= 3) {
            return 0.0f;
        }

        return self->mScalingKeys[index].mValue[component];
    }

    aiAnimBehaviour GetPreState() const {
        return self->mPreState;
    }

    aiAnimBehaviour GetPostState() const {
        return self->mPostState;
    }

    aiAnimInterpolation GetPositionKeyInterpolation(unsigned int index) const {
        return index < self->mNumPositionKeys && self->mPositionKeys != nullptr
            ? self->mPositionKeys[index].mInterpolation
            : aiAnimInterpolation_Linear;
    }

    aiAnimInterpolation GetRotationKeyInterpolation(unsigned int index) const {
        return index < self->mNumRotationKeys && self->mRotationKeys != nullptr
            ? self->mRotationKeys[index].mInterpolation
            : aiAnimInterpolation_Linear;
    }

    aiAnimInterpolation GetScalingKeyInterpolation(unsigned int index) const {
        return index < self->mNumScalingKeys && self->mScalingKeys != nullptr
            ? self->mScalingKeys[index].mInterpolation
            : aiAnimInterpolation_Linear;
    }
}

%extend aiMeshAnim {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    unsigned int GetKeyCount() const {
        return self->mNumKeys;
    }

    double GetKeyTime(unsigned int index) const {
        return index < self->mNumKeys && self->mKeys != nullptr
            ? self->mKeys[index].mTime
            : 0.0;
    }

    unsigned int GetKeyValue(unsigned int index) const {
        return index < self->mNumKeys && self->mKeys != nullptr
            ? self->mKeys[index].mValue
            : static_cast<unsigned int>(-1);
    }
}

%extend aiMeshMorphAnim {
    const char* GetName() const {
        return self->mName.C_Str();
    }

    unsigned int GetKeyCount() const {
        return self->mNumKeys;
    }

    double GetKeyTime(unsigned int index) const {
        return index < self->mNumKeys && self->mKeys != nullptr
            ? self->mKeys[index].mTime
            : 0.0;
    }

    unsigned int GetKeyValueCount(unsigned int index) const {
        return index < self->mNumKeys && self->mKeys != nullptr
            ? self->mKeys[index].mNumValuesAndWeights
            : 0;
    }

    unsigned int GetKeyValue(unsigned int keyIndex, unsigned int valueIndex) const {
        if (keyIndex >= self->mNumKeys ||
            self->mKeys == nullptr ||
            valueIndex >= self->mKeys[keyIndex].mNumValuesAndWeights) {
            return static_cast<unsigned int>(-1);
        }

        return self->mKeys[keyIndex].mValues[valueIndex];
    }

    double GetKeyWeight(unsigned int keyIndex, unsigned int valueIndex) const {
        if (keyIndex >= self->mNumKeys ||
            self->mKeys == nullptr ||
            valueIndex >= self->mKeys[keyIndex].mNumValuesAndWeights) {
            return 0.0;
        }

        return self->mKeys[keyIndex].mWeights[valueIndex];
    }
}

/* Existing native methods whose names are not C#-idiomatic. */
%rename("AddChildren") aiNode::addChildren;
%rename("FindBoneNode") aiNode::findBoneNode;
