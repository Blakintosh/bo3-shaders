// Tools only (Radiant), used by the TessTopology MTPlugin, not by any techset: a domain shader for Radiant's selection
// overlay on the displacing tess surfaces (lit_advanced_fullspec_parallax_tess, _blend_tess and _blend2/3/4_tess).
// Radiant draws the overlay (ToolsGfx/wireframe.hlsl: VS, GS, PS) with the flat mesh, so on a displaced surface it only
// shows where the flat mesh is in front. The plugin redraws it through the surface's own local and hull shaders and
// this DS, which displaces exactly like the surface's gbuffer DS (blak/blak_gbuffer_tess_lit_parallax.hlsl, or
// blak/blak_gbuffer_tess_lit_blend.hlsl when OVERLAY_BLEND is set: same globals in the same order, height maps from t0 and
// aoSampler at s0, so the surface's own constant buffer, textures and sampler bind as they are) and emits what
// wireframe.hlsl's VS emits (read from its compiled variants in Radiant's shader cache), so Radiant's GS and PS run
// unchanged.
//
// Compile (into bin\plugins\TessTopology): fxc /T ds_5_0 /E ds_main /D TOOLSGFX=1 /D USE_GPU_SKIN=0
// /I deps/shaders_stable_toolsgfx /I shaders and
//   (nothing)                                -> TessOverlayWire.cso        parallax_tess
//   /D OVERLAY_BLEND=1                       -> TessOverlayWireBlend.cso   blend_tess (two layers, vertex alpha)
//   /D OVERLAY_BLEND=1 /D BLEND_RGB_LAYERS=N -> TessOverlayWireBlendN.cso  blend2/3/4_tess (vertex colour)

#include "blak/blak_tess_common.hlsl"

SamplerState aoSampler;
Texture2D<float4> heightMap;
#if OVERLAY_BLEND
Texture2D<float4> heightMap2;
#if BLEND_RGB_LAYERS >= 3
Texture2D<float4> heightMap3;
#endif
#if BLEND_RGB_LAYERS >= 4
Texture2D<float4> heightMap4;
#endif
#include "blak/tess_blend.h"
#define OVERLAY_HEIGHT(s) BlendHeight(s).x
#else
#define OVERLAY_HEIGHT(s) TessSampleHeight(heightMap, aoSampler, s)
#endif

// wireframe.hlsl's VS output signature (POSITON is spelt that way there).
struct DomainShaderOutput
{
	float4 Position  : POSITON;		// clip space
	float4 Colour    : COLOR0;		// gObject.customFloat4s[0] (alpha only when customInt4s.z bit 0)
	float3 Normal    : NORMAL0;		// camera space, normalised
	float3 CamPos    : TEXCOORD0;	// camera space
	float3 ObjPos    : TEXCOORD1;
	float2 Pixel     : TEXCOORD2;	// render target pixel
	uint   EdgeA     : TEXCOORD3;	// edge flags from the normal's w; 128 / 0 = the "no flags" case
	uint   EdgeB     : TEXCOORD4;
	uint   Instance  : TEXCOORD5;
};

[domain("tri")]
DomainShaderOutput ds_main(PatchConstants factors, float3 bary : SV_DomainLocation, const OutputPatch<ControlPoint, 3> patch)
{
	TessSurface s = TessInterpolate(bary, patch);
	float d0 = TessAmount(s, OVERLAY_HEIGHT(s));
	float3 offset = s.Direction * d0;
	float3 pos = s.Position + offset;

	float3 nrm = s.Normal;
	if (TessHasNormal())
	{
		TessSurface st = TessShift(s, s.Tangent * s.Eps);
		TessSurface sb = TessShift(s, s.BiTangent * s.Eps);
		float dT = TessAmount(st, OVERLAY_HEIGHT(st));
		float dB = TessAmount(sb, OVERLAY_HEIGHT(sb));
		nrm = TessDisplacedNormal(s, d0, dT, dB);
	}

	DomainShaderOutput OUT;
	// The same expression as the surface's gbuffer DS, so the overlay lands on exactly the same depth.
	OUT.Position = Transform_ObjectToClip(Transform_ObjectToCamera(pos, 0), 0);
	float4 col = gObject.customFloat4s[0];
	OUT.Colour   = float4(col.xyz, (gObject.customInt4s.z & 1) ? col.w : 1.0);
	OUT.Normal   = normalize(mul(nrm, (float3x3)gScene.transforms.offToCamMatrix));
	OUT.CamPos   = mul(float4(pos - TESS_EYE, 1.0), gScene.transforms.offToCamMatrix).xyz;
	OUT.ObjPos   = pos;
	float2 uv    = OUT.Position.xy / OUT.Position.w * float2(0.5, -0.5) + 0.5;
	OUT.Pixel    = uv * float2(gScene.renderTargetSize);
	OUT.EdgeA    = 128;
	OUT.EdgeB    = 0;
	OUT.Instance = patch[0].Instance;
	return OUT;
}
