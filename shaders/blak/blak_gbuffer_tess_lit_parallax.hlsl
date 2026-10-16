// Domain shader for lit_advanced_fullspec_parallax_tess (stages and controls: blak/blak_tess_common.hlsl). The pixel
// shader is blak/blak_gbuffer_ps_lit_parallax.hlsl, unchanged: ds_main emits exactly what gbuffer_vs_lit_parallax.hlsl
// emits, so the PS can't tell the difference.

#include "blak/blak_tess_common.hlsl"

SamplerState aoSampler;
Texture2D<float4> heightMap;

// Same layout as gbuffer_vs_lit_parallax.hlsl's VertexShaderOutput.
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
	float d0 = TessAmount(s, TessSampleHeight(heightMap, aoSampler, s));
	float3 offset = s.Direction * d0;
	float3 pos = s.Position + offset;

	// The displaced surface's normal and frame (world mode), so the lighting and the pixel shader's texture planes follow the relief.
	float3 nrm = s.Normal, tng = s.Tangent, btg = s.BiTangent;
	if (TessHasNormal())
	{
		TessSurface st = TessShift(s, s.Tangent * s.Eps);
		TessSurface sb = TessShift(s, s.BiTangent * s.Eps);
		float dT = TessAmount(st, TessSampleHeight(heightMap, aoSampler, st));
		float dB = TessAmount(sb, TessSampleHeight(heightMap, aoSampler, sb));
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
	OUT.Colour        = TessVertexColour(s) * TessDebugTint(bary, factors);
	OUT.Alpha         = s.Colour.w;

	float3x3 TBN = transpose(float3x3(tng, btg, nrm));
	OUT.TangentViewPos  = mul(TBN, TESS_EYE);
	OUT.TangentPixelPos = mul(TBN, pos);

#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(s.PrevPosition + offset);
#endif
	return OUT;
}
