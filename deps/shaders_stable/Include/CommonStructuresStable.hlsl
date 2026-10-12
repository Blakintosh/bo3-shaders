#ifndef __COMMON_STABLE_STRUCT_INCLUDED__
#define __COMMON_STABLE_STRUCT_INCLUDED__

// The following structures and data were obtained from shaders included in the Black Ops III Mod Tools

struct BonesInstanceData
{
	row_major float3x4                  objMatrixT;
	float4                              extra;
};

struct ModelInstanceData
{
	uint 										boneArrayIndex;           		// Offset:    0
	uint 										shaderConstantSet;        		// Offset:    4
	uint 										flagsAndPrevFrameIndex;   		// Offset:    8
	uint 										worldMatrix;              		// Offset:   12
	uint 										siegeAnimStateOffset;     		// Offset:   16
	uint 										prevFrameSiegeAnimStateOffset;	// Offset:   20
};

#endif // __COMMON_STABLE_STRUCT_INCLUDED__