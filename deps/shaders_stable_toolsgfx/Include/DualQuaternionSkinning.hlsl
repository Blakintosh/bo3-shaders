#ifndef __DUAL_QUAT_INCLUDED__
#define __DUAL_QUAT_INCLUDED__

#include "Include/Quaternion.hlsl"

float2x4 DualQuaternion_GetBoneDualQuaternion(uint boneIndex, uint instance)
{
	float3x4 boneMatrix           = Transform_GetBoneMatrix(boneIndex, instance);
    float4 boneRotation           = Quaternion_FromRotationMatrix(transpose((float3x3)boneMatrix));
    float4 boneTranslationQuat    = float4(boneMatrix[0][3], boneMatrix[1][3], boneMatrix[2][3], 0.0f);
	
    return float2x4(
		boneRotation,
		Quaternion_Multiply(boneTranslationQuat, boneRotation) * 0.5f);
}

float2x4 DualQuaternion_GetBlendedDualQuaternion(uint4 boneIndices, float4 boneWeights, uint instance)
{
	float2x4 dq0 = DualQuaternion_GetBoneDualQuaternion(boneIndices.x, instance);
	float2x4 dq1 = DualQuaternion_GetBoneDualQuaternion(boneIndices.y, instance);
	float2x4 dq2 = DualQuaternion_GetBoneDualQuaternion(boneIndices.z, instance);
	float2x4 dq3 = DualQuaternion_GetBoneDualQuaternion(boneIndices.w, instance);

	
	// Antipodality correction.
	if (dot(dq0[0], dq1[0]) < 0.0) dq1 *= -1.0;
	if (dot(dq0[0], dq2[0]) < 0.0) dq2 *= -1.0;	
	if (dot(dq0[0], dq3[0]) < 0.0) dq3 *= -1.0;
	

	float2x4 blendedDQ =
		dq0 * boneWeights.x + 
		dq1 * boneWeights.y + 
		dq2 * boneWeights.z + 
		dq3 * boneWeights.w;

	float normDQ = length(blendedDQ[0]);
	return blendedDQ / normDQ;
}

float3 DualQuaternion_TransformPoint(float4 realDQ, float4 dualDQ, float3 pt)
{
	return pt + 2 * cross(realDQ.xyz, cross(realDQ.xyz, pt) + realDQ.w * pt) + 2 * (realDQ.w * dualDQ.xyz - dualDQ.w * realDQ.xyz + cross(realDQ.xyz, dualDQ.xyz));
}

void DualQuaternion_SkinVertex(
    inout float3 inPos,
    inout float3 inNormal,
    inout float3 inTangent,
    uint4 inBoneIndices,
    float4 inBoneWeights,
	uint instance)
{
    float2x4 dq = DualQuaternion_GetBlendedDualQuaternion(inBoneIndices, inBoneWeights, instance);
    float3 blendedPosition = DualQuaternion_TransformPoint(dq[0], dq[1], inPos);

    inPos       = DualQuaternion_TransformPoint(dq[0], dq[1], inPos);
    inNormal    = Quaternion_TransformVector(dq[0], inNormal);
    inTangent   = Quaternion_TransformVector(dq[0], inTangent);
}

#if GENERATE_MOTION_VECTOR
float2x4 DualQuaternion_GetBoneDualQuaternionMotionVector(uint boneIndex, uint instance)
{
	float3x4 boneMatrix           = Transform_GetBoneMatrixMotionVector(boneIndex, instance);
    float4 boneRotation           = Quaternion_FromRotationMatrix(transpose((float3x3)boneMatrix));
    float4 boneTranslationQuat    = float4(boneMatrix[0][3], boneMatrix[1][3], boneMatrix[2][3], 0.0f);
	
    return float2x4(
		boneRotation,
		Quaternion_Multiply(boneTranslationQuat, boneRotation) * 0.5f);
}

float2x4 DualQuaternion_GetBlendedDualQuaternionMotionVector(uint4 boneIndices, float4 boneWeights, uint instance)
{
	float2x4 dq0 = DualQuaternion_GetBoneDualQuaternionMotionVector(boneIndices.x, instance);
	float2x4 dq1 = DualQuaternion_GetBoneDualQuaternionMotionVector(boneIndices.y, instance);
	float2x4 dq2 = DualQuaternion_GetBoneDualQuaternionMotionVector(boneIndices.z, instance);
	float2x4 dq3 = DualQuaternion_GetBoneDualQuaternionMotionVector(boneIndices.w, instance);

	
	// Antipodality correction.
	if (dot(dq0[0], dq1[0]) < 0.0) dq1 *= -1.0;
	if (dot(dq0[0], dq2[0]) < 0.0) dq2 *= -1.0;	
	if (dot(dq0[0], dq3[0]) < 0.0) dq3 *= -1.0;
	

	float2x4 blendedDQ =
		dq0 * boneWeights.x + 
		dq1 * boneWeights.y + 
		dq2 * boneWeights.z + 
		dq3 * boneWeights.w;

	float normDQ = length(blendedDQ[0]);
	return blendedDQ / normDQ;
}

void DualQuaternion_SkinVertexMotionVector(
    inout float3 inPos,
    uint4 inBoneIndices,
    float4 inBoneWeights,
	uint instance)
{
    float2x4 dq = DualQuaternion_GetBlendedDualQuaternionMotionVector(inBoneIndices, inBoneWeights, instance);

    inPos       = DualQuaternion_TransformPoint(dq[0], dq[1], inPos);
}
#endif

#endif // __DUAL_QUAT_INCLUDED__