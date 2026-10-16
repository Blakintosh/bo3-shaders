// Vertex shader for lit_advanced_fullspec_parallax. The tools build is the shared tools vertex shader
// (blak/gbuffer_vs_lit_tools.h, mesh UVs); the game build follows.
#if TOOLSGFX
#define TESS_TOOLS_PLAIN 1
#include "blak/gbuffer_vs_lit_tools.h"
#else
#define DUAL_QUAT_SKINNING 1
#include "blak/blak_common.h"

struct VertexShaderInput
{
	float3 				Position    				: POSITION;
	float4 				Colour      				: COLOR;
	float2 				TexCoord    				: TEXCOORD;
	float3 				Normal      				: NORMAL;
	float4 				Tangent     				: TANGENT;
    float4              Weights                     : BLENDWEIGHT;
	uint4               Indices                     : BLENDINDICES;
};

struct VertexShaderOutput
{
	float4 				Position    				: SV_POSITION;
    float3              Colour                      : COLOR0;
	float 				Alpha      	    	  		: COLOR1;
	float2 				TexCoord    				: TEXCOORD0;
	float3 				Normal      				: TEXCOORD1;
	float3 				Tangent     				: TEXCOORD2;
	float3 				BiTangent   				: TEXCOORD3;
    float4              PixelPosition               : TEXCOORD4;
    float3              TangentViewPos              : TEXCOORD5;
    float3              TangentPixelPos             : TEXCOORD6;
#if GENERATE_MOTION_VECTOR
	float4 				MotionVectorPosition 		: TEXCOORD7;
#endif
};

VertexShaderOutput vs_main(in VertexShaderInput IN, in uint instance : INSTANCE_SEMANTIC)
{
	VertexShaderOutput OUT = (VertexShaderOutput)0;

	float3 pos = IN.Position;
	float3 nor = Utility_DecodeNormal(IN.Normal);
	float3 tan = Utility_DecodeNormal(IN.Tangent.xyz);

	// The SDK always skins in game; world vertices (wc/, USE_GPU_SKIN 0) have no bone weights and turn into NaNs.
#if USE_GPU_SKIN
	Utility_SkinVertex(
		pos,
		nor,
		tan,
		IN.Indices,
		IN.Weights,
		instance);
#endif

    float3 result = Transform_ObjectToCamera(Transform_ObjectPositionToWorldSpace(pos, instance), instance);

	OUT.Position	= Transform_ObjectToClip(result, instance);
    OUT.PixelPosition = float4(Transform_ObjectPositionToWorldSpace(pos, instance), 1.0);
	OUT.TexCoord   	= IN.TexCoord;
	OUT.Normal     	= Transform_ObjectNormalToWorldSpace(nor, instance).xyz;
	OUT.Tangent    	= Transform_ObjectNormalToWorldSpace(tan, instance).xyz;
	OUT.BiTangent  	= cross(OUT.Normal, OUT.Tangent) * Utility_DecodeBiTangentSign(IN.Tangent.w);
    OUT.Colour = IN.Colour.xyz;
    OUT.Alpha = IN.Colour.w;
    
    float3x3 TBN = transpose(float3x3(OUT.Tangent, OUT.BiTangent, OUT.Normal));

#if TOOLSGFX
    OUT.TangentViewPos = mul(TBN, gScene.wldCameraPosition);
#else
    OUT.TangentViewPos = mul(TBN, eyeOffset.xyz);
#endif
    OUT.TangentPixelPos = mul(TBN, OUT.PixelPosition.xyz);

#if GENERATE_MOTION_VECTOR
	pos = IN.Position;

#if USE_GPU_SKIN
	Utility_SkinVertexMotionVector(
		pos,
		IN.Indices,
		IN.Weights,
		instance);
#endif
	
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(Transform_ObjectPositionToWorldSpaceMotionVector(pos, instance));
#endif

	return OUT;
}
#endif
