// Domain shader for lit_decal_reveal_tess. The pixel shader is Treyarch's gbuffer_decal.hlsl, unchanged: ds_main
// emits what the decal pixel shaders read, so every stock decal pixel shader (reveal, normal, spec, AO...) runs as it
// is. In game that is what the stock decal vertex shader emits (SV_POSITION, COLOR0 = vertex colour^2.2, COLOR1 =
// vertex alpha, TEXCOORD0-3; read from its disassembly in RenderDoc; the reveal decals blend by COLOR1); in the tools
// it is vs_generic's (SV_POSITION, COLOR1, TEXCOORD0-3).
//
// The decal inherits the topology of the surface under it by sampling the same height function: give the decal
// material the host's height map (in game in the tint-mask slot, colorMap00, whose stock use isn't needed) and the
// same tessellation controls (world mode: tessWorldScale, axis, anchor, displace, midpoint). World mode makes the
// displacement a function of world position only, so decal and host agree wherever they overlap. Mesh mode can't
// match (the decal's UVs aren't the host's).
// tessDecalLift pushes the decal out along the displaced normal (units) so it can't dip under the host between the
// two meshes' vertices; the material's polygon offset does the rest.
// The decal keeps its own UVs and tangent frame; only the position and the normal follow the relief.

#include "blak/blak_tess_common.hlsl"

SamplerState aoSampler;
#if TOOLSGFX
Texture2D<float4> heightMap;
#else
Texture2D<float4> tintMask;	// the decal's tint-mask slot (colorMap00) carries the host's height map
#endif

struct DomainShaderOutput
{
	float4 				Position    				: SV_POSITION;
#if TOOLSGFX
	float 				Colour      				: COLOR1;
#else
	float3 				Colour      				: COLOR0;
	float 				Alpha       				: COLOR1;
#endif
	float2 				TexCoord    				: TEXCOORD0;
	float3 				Normal      				: TEXCOORD1;
	float3 				Tangent     				: TEXCOORD2;
	float3 				BiTangent   				: TEXCOORD3;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float4 				MotionVectorPosition 		: TEXCOORD7;
#endif
};

[domain("tri")]
DomainShaderOutput ds_main(PatchConstants factors, float3 bary : SV_DomainLocation, const OutputPatch<ControlPoint, 3> patch)
{
	TessSurface s = TessInterpolate(bary, patch);
#if TOOLSGFX
	float d0 = TessAmount(s, TessSampleHeight(heightMap, aoSampler, s));
#else
	float d0 = TessAmount(s, TessSampleHeight(tintMask, aoSampler, s));
#endif

	float3 nrm = s.Normal;
	if (TessHasNormal())
	{
		TessSurface st = TessShift(s, s.Tangent * s.Eps);
		TessSurface sb = TessShift(s, s.BiTangent * s.Eps);
#if TOOLSGFX
		float dT = TessAmount(st, TessSampleHeight(heightMap, aoSampler, st));
		float dB = TessAmount(sb, TessSampleHeight(heightMap, aoSampler, sb));
#else
		float dT = TessAmount(st, TessSampleHeight(tintMask, aoSampler, st));
		float dB = TessAmount(sb, TessSampleHeight(tintMask, aoSampler, sb));
#endif
		nrm = TessDisplacedNormal(s, d0, dT, dB);
	}
	float3 tng, btg;
	TessReframe(nrm, s.MeshTangent, s.MeshBiTangent, tng, btg);

	float3 offset = s.Direction * d0 + nrm * (tessDecalLift * s.Detail);
	float3 pos = s.Position + offset;

	DomainShaderOutput OUT;
	OUT.Position  = Transform_ObjectToClip(Transform_ObjectToCamera(pos, 0), 0);
	OUT.TexCoord  = s.MeshTexCoord;
#if TOOLSGFX
	OUT.Colour    = 0;	// vs_generic leaves it 0
#else
	OUT.Colour    = pow(abs(s.Colour.rgb), 2.2);
	OUT.Alpha     = s.Colour.a;
#endif
	OUT.Normal    = nrm;
	OUT.Tangent   = tng;
	OUT.BiTangent = btg;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(s.PrevPosition + offset);
#endif
	return OUT;
}
