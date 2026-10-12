#ifndef __LINEAR_BLEND_INCLUDED__
#define __LINEAR_BLEND_INCLUDED__

float3x4 LinearBlend_GetBlendedMatrix(uint4 boneIndices, float4 boneWeights, uint instance)
{
	return Transform_GetBoneMatrix(boneIndices.x, instance) * boneWeights.x + 
		   Transform_GetBoneMatrix(boneIndices.y, instance) * boneWeights.y + 
		   Transform_GetBoneMatrix(boneIndices.z, instance) * boneWeights.z + 
		   Transform_GetBoneMatrix(boneIndices.w, instance) * boneWeights.w;
}

void LinearBlend_SkinVertex(
    inout float3 inPos,
    inout float3 inNormal,
    inout float3 inTangent,
    uint4 inBoneIndices,
    float4 inBoneWeights,
    uint instance)
{
    float3x4 mat = LinearBlend_GetBlendedMatrix(inBoneIndices, inBoneWeights, instance);

    inPos        = mul(mat, float4(inPos, 1));
    inNormal     = mul((float3x3)mat, inNormal);
    inTangent    = mul((float3x3)mat, inTangent);
}

#if GENERATE_MOTION_VECTOR
float3x4 LinearBlend_GetBlendedMatrixMotionVector(uint4 boneIndices, float4 boneWeights, uint instance)
{
	return Transform_GetBoneMatrixMotionVector(boneIndices.x, instance) * boneWeights.x + 
		   Transform_GetBoneMatrixMotionVector(boneIndices.y, instance) * boneWeights.y + 
		   Transform_GetBoneMatrixMotionVector(boneIndices.z, instance) * boneWeights.z + 
		   Transform_GetBoneMatrixMotionVector(boneIndices.w, instance) * boneWeights.w;
}

void LinearBlend_SkinVertexMotionVector(
    inout float3 inPos,
    uint4 inBoneIndices,
    float4 inBoneWeights,
    uint instance)
{
    float3x4 mat = LinearBlend_GetBlendedMatrix(inBoneIndices, inBoneWeights, instance);

    inPos = mul(mat, float4(inPos, 1));
}
#endif

#endif // __LINEAR_BLEND_INCLUDED__
