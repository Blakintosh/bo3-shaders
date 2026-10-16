// Tessellated "build shadowmap depth" for the blak *_tess techsets: the same tessellation and displacement as the
// gbuffer pass (blak/blak_tess_common.hlsl), so the shadow matches the displaced surface. Depth only; the stock shadow
// vertex shader projects the same way (PerSceneConsts viewProjectionMatrix and eyeOffset, which the shadow pass
// fills for the light's view).
//
// TESS_HEIGHT_BLEND: the blend techset's height (two layers, vertex alpha; blak/tess_blend.h).

#include "blak/blak_tess_common.hlsl"

SamplerState aoSampler;
Texture2D<float4> heightMap;

#if TESS_HEIGHT_BLEND
Texture2D<float4> heightMap2;
#if BLEND_RGB_LAYERS >= 3
Texture2D<float4> heightMap3;
#endif
#if BLEND_RGB_LAYERS >= 4
Texture2D<float4> heightMap4;
#endif
#include "blak/tess_blend.h"
#endif

struct ShadowOutput
{
	float4 Position : SV_POSITION;
};

[domain("tri")]
ShadowOutput ds_main(PatchConstants factors, float3 bary : SV_DomainLocation, const OutputPatch<ControlPoint, 3> patch)
{
	TessSurface s = TessInterpolate(bary, patch);
#if TESS_HEIGHT_BLEND
	float height = BlendHeight(s).x;
#else
	float height = TessSampleHeight(heightMap, aoSampler, s);
#endif
	ShadowOutput OUT;
	OUT.Position = Transform_ObjectToClip(Transform_ObjectToCamera(s.Position + s.Direction * TessAmount(s, height), 0), 0);
	return OUT;
}

void ps_main(ShadowOutput IN)
{
}
