// Domain shader for lit_advanced_fullspec_blend[2/3/4]_tess: layers blended by vertex alpha or colour and their heights
// (blak/tess_blend.h), displaced by the blended height (stages and controls: blak/blak_tess_common.hlsl). The pixel
// shader is blak/blak_gbuffer_ps_lit_blend.hlsl, which blends the same way.

#include "blak/blak_tess_common.hlsl"

SamplerState aoSampler;
Texture2D<float4> heightMap;
Texture2D<float4> heightMap2;
#if BLEND_RGB_LAYERS >= 3
Texture2D<float4> heightMap3;
#endif
#if BLEND_RGB_LAYERS >= 4
Texture2D<float4> heightMap4;
#endif

#include "blak/tess_blend.h"

// Same layout as gbuffer_vs_lit_parallax.hlsl's VertexShaderOutput (the blend PS reads it like the parallax PS).
struct DomainShaderOutput
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
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float4 				MotionVectorPosition 		: TEXCOORD7;
#endif
};

[domain("tri")]
DomainShaderOutput ds_main(PatchConstants factors, float3 bary : SV_DomainLocation, const OutputPatch<ControlPoint, 3> patch)
{
	TessSurface s = TessInterpolate(bary, patch);
	float d0 = TessAmount(s, BlendHeight(s).x);
	float3 offset = s.Direction * d0;
	float3 pos = s.Position + offset;

	// The displaced surface's normal and frame (world mode), so the lighting and the pixel shader's texture planes follow the relief.
	float3 nrm = s.Normal, tng = s.Tangent, btg = s.BiTangent;
	if (TessHasNormal())
	{
		TessSurface st = TessShift(s, s.Tangent * s.Eps);
		TessSurface sb = TessShift(s, s.BiTangent * s.Eps);
		float dT = TessAmount(st, BlendHeight(st).x);
		float dB = TessAmount(sb, BlendHeight(sb).x);
		nrm = TessDisplacedNormal(s, d0, dT, dB);
		TessReframe(nrm, s.Tangent, s.BiTangent, tng, btg);
	}

	DomainShaderOutput OUT;
	OUT.Position      = Transform_ObjectToClip(Transform_ObjectToCamera(pos, 0), 0);
	OUT.PixelPosition = float4(pos, tessWorldScale);	// w: world-mode scale for the pixel shader's triplanar mapping (0 = mesh mode)
	OUT.TexCoord      = s.TexCoord;
	OUT.Normal        = nrm;
	OUT.Tangent       = tng;
	OUT.BiTangent     = btg;
#if BLEND_RGB_LAYERS
	OUT.Colour        = TessVertexColour(s);	// the layer selector, not a tint
#else
	OUT.Colour        = TessVertexColour(s) * TessDebugTint(bary, factors);
#endif
	OUT.Alpha         = s.Colour.w;

	float3x3 TBN = transpose(float3x3(tng, btg, nrm));
	OUT.TangentViewPos  = mul(TBN, TESS_EYE);
	OUT.TangentPixelPos = mul(TBN, pos);

#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(s.PrevPosition + offset);
#endif
	return OUT;
}
