#ifndef BLAK_COMMON_TOOLSGFX_INCLUDED
#define BLAK_COMMON_TOOLSGFX_INCLUDED

#include "blak/blak_common_structures_toolsgfx.h"

// The following structures and data were obtained from shaders included in the Black Ops III Mod Tools

#define INSTANCE_SEMANTIC					INSTANCEID

cbuffer CodeSceneConstBuffer : register(b9)
{
	CodeSceneConsts 				gScene : packoffset(c0.x);
};

cbuffer CodeObjectConstBuffer : register(b10)
{
	CodeObjectConsts 				gObject : packoffset(c0.x);
};

cbuffer CodeObjectBonesConstBuffer : register(b11) 
{
	CodeObjectBonesConst 			gObjectBones[1024] : packoffset(c0.x);
};

StructuredBuffer<CodeObjectConsts> gObjectInstanceData : register(t30);

float3x4 Transform_GetBoneMatrix(uint boneIndex, uint instance)
{
	return gObjectBones[boneIndex].objMatrixT;
}

float3 Transform_ObjectPositionToWorldSpace(const float3 pos, const uint instance)
{
	if(instance)
		return mul(float4(pos, 1.0f), gObjectInstanceData[instance].worldMatrix).xyz;
	else
		return mul(float4(pos, 1.0f), gObject.worldMatrix).xyz;
}

float3 Transform_ObjectNormalToWorldSpace(const float3 norm, const uint instance)
{
	if(instance)
		return mul(norm, (float3x3)gObjectInstanceData[instance].worldMatrix);
	else
		return mul(norm, (float3x3)gObject.worldMatrix);
}

float4 Transform_ObjectToWorld(float4 pos, uint instance)
{
	if(instance)
		pos = mul(pos, gObjectInstanceData[instance].worldMatrix);
	pos = mul(pos, gObject.worldMatrix);
	return pos;
}

float3 Transform_ObjectToCamera(const float3 pos, const uint instance)
{
	return -gScene.wldCameraPosition + pos.xyz;
}

float4 Transform_ObjectToClip(float3 pos, uint instance)
{
	return mul(float4(pos, 1.0f), gScene.transforms.offToClpMatrix);
}

#endif // BLAK_COMMON_TOOLSGFX_INCLUDED