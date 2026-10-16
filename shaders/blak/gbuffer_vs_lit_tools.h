// Tools (Radiant / APE) vertex shader for the blak parallax and *_tess techsets: no tessellation or displacement in
// the tools, but the same texturing as in game, so a surface previews the way it will look. Feeds the tools parallax
// and blend pixel shaders (their PixelShaderInput).
//
// World mode (tessWorldScale > 0) is box-mapped here as in game (blak/blak_tess_common.hlsl in shaders_stable): each
// vertex takes its UVs from the world plane its normal faces most, tessWorldScale units per repeat, with a tangent
// frame to match. TESS_TOOLS_PLAIN (the plain parallax techset) leaves the mesh UVs alone.

#define DUAL_QUAT_SKINNING 1
#include "blak/blak_common.h"

float tessWorldScale;

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

// The tools parallax PS's PixelShaderInput, less SV_IsFrontFace.
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
};

VertexShaderOutput vs_main(in VertexShaderInput IN, in uint instance : INSTANCE_SEMANTIC)
{
	VertexShaderOutput OUT = (VertexShaderOutput)0;

	float3 pos = IN.Position;
	float3 nor = Utility_DecodeNormal(IN.Normal);
	float3 tan = Utility_DecodeNormal(IN.Tangent.xyz);

	Utility_SkinVertex(pos, nor, tan, IN.Indices, IN.Weights, instance);

	float3 wpos = Transform_ObjectPositionToWorldSpace(pos, instance);
	OUT.Position      = Transform_ObjectToClip(Transform_ObjectToCamera(wpos, instance), instance);
	OUT.PixelPosition = float4(wpos, 1.0);
	OUT.TexCoord      = IN.TexCoord;
	OUT.Normal        = Transform_ObjectNormalToWorldSpace(nor, instance).xyz;
	OUT.Tangent       = Transform_ObjectNormalToWorldSpace(tan, instance).xyz;
	OUT.BiTangent     = cross(OUT.Normal, OUT.Tangent) * Utility_DecodeBiTangentSign(IN.Tangent.w);
	OUT.Colour        = IN.Colour.xyz;
	OUT.Alpha         = IN.Colour.w;

#if !TESS_TOOLS_PLAIN
	if (tessWorldScale > 0)
	{
		float3 n = normalize(OUT.Normal), m = abs(n), u, v;
		int b = (m.x >= m.y && m.x >= m.z) ? 0 : (m.y >= m.z ? 1 : 2);
		OUT.TexCoord = (b == 0 ? wpos.yz : (b == 1 ? wpos.xz : wpos.xy)) / tessWorldScale;
		u = b == 0 ? float3(0, 1, 0) : float3(1, 0, 0);
		v = b == 2 ? float3(0, 1, 0) : float3(0, 0, 1);
		OUT.Tangent   = normalize(u - n * dot(u, n) + 1e-5);
		OUT.BiTangent = normalize(v - n * dot(v, n) - OUT.Tangent * dot(v, OUT.Tangent) + 1e-5);
	}
#endif

	float3x3 TBN = transpose(float3x3(OUT.Tangent, OUT.BiTangent, OUT.Normal));
	OUT.TangentViewPos  = mul(TBN, gScene.wldCameraPosition.xyz);
	OUT.TangentPixelPos = mul(TBN, wpos);
	return OUT;
}
