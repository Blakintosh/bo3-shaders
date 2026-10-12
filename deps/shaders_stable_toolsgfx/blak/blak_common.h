#ifndef BLAK_COMMON_INCLUDED
#define BLAK_COMMON_INCLUDED

#if TOOLSGFX
#include "blak/blak_common_toolsgfx.h"
#else
#include "blak/blak_common_stable.h"
#endif

#if DUAL_QUAT_SKINNING
#include "blak/blak_dual_quaternion_skinning.h"
#else
#include "blak/blak_linear_blend_skinning.h"
#endif

// What our pixel shader outputs for "gbuffer" techniques, Black Ops III
// uses deferred lighting with forward for anything that can't be done in deferred,
// hence why no lighting calculations here, that is done in a compute shader, this
// just passes into the Geometry Buffer, some values are packed to save space and 
// position seems to be calculated from depth which is common to save bandwidth
struct PixelShaderGBufferOutput
{
	float4 				Albedo    					: SV_TARGET0;
	float4 				NormalGloss    				: SV_TARGET1;
	float4 				ReflectanceOcclusion   		: SV_TARGET2;
};

float3 Utility_DecodeNormal(float3 value)
{
#if TOOLSGFX
    // Passed in as R8G8B8A8_SNORM
    return value;
#else
    // Passed in as R10B10G10A2
    return value * 2 - 1;
#endif
}

float Utility_DecodeBiTangentSign(float sign)
{
#if TOOLSGFX
    // Passed in as R8G8B8A8_SNORM
    return sign;
#else
    // Passed in as R10B10G10A2
    return sign * 2 - 1;
#endif
}

bool Utility_HasBones(uint instance)
{
#if TOOLSGFX
    return gObject.hasBones;
#else
    // TODO: Proper check for has bones in-game, it seems more
    // relevant to check for if siege is used when in-game,
    // then take that path as it seems in-game there will always be "bones"
    return true;
#endif
}

void Utility_SkinVertex(
    inout float3 inPos,
    inout float3 inNormal,
    inout float3 inTangent,
    uint4 inBoneIndices,
    float4 inBoneWeights,
	uint instance)
{
	if(Utility_HasBones(instance))
	{
#if DUAL_QUAT_SKINNING
		DualQuaternion_SkinVertex(
			inPos,
			inNormal,
			inTangent,
			inBoneIndices,
			inBoneWeights,
			instance);
#else
		LinearBlend_SkinVertex(
			inPos,
			inNormal,
			inTangent,
			inBoneIndices,
			inBoneWeights,
			instance);
#endif
	}
	else
	{
#if 0
		// TODO: Siege Anims
		Siege_SkinVertex(
			inPos,
			inNormal,
			inTangent,
			inBoneIndices,
			inBoneWeights,
			instance);
#endif
	}
}

#if GENERATE_MOTION_VECTOR
void Utility_SkinVertexMotionVector(
    inout float3 inPos,
    uint4 inBoneIndices,
    float4 inBoneWeights,
	uint instance)
{
	if(Utility_HasBones(instance))
	{
#if DUAL_QUAT_SKINNING
		DualQuaternion_SkinVertexMotionVector(
			inPos,
			inBoneIndices,
			inBoneWeights,
			instance);
#else
		LinearBlend_SkinVertexMotionVector(
			inPos,
			inBoneIndices,
			inBoneWeights,
			instance);
#endif
	}
	else
	{
#if 0
		// TODO: Siege Anims
		Siege_SkinVertexMotionVector(
			inPos,
			inBoneIndices,
			inBoneWeights,
			instance);
#endif
	}
}
#endif

#endif // BLAK_COMMON_INCLUDED
