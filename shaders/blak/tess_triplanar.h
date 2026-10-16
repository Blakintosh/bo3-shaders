// World-mode triplanar texturing for the blak *_tess pixel shaders (include after the textures, samplers and, for the
// blend shader, tess_blend.hlsl and TESS_BLEND_BLUR are declared; define TRI_BLEND for the two-layer version).
//
// The domain shader box-maps each face along its undisplaced facing, so a displaced slope would smear the texture
// along it. Here every map is sampled on all three world planes (the same planes and scale the domain shader
// uses) and blended by the displaced surface normal, which the domain shader now outputs. Normal maps are rotated
// into world space per plane, blended, and handed back in the interpolated tangent frame. Parallax is skipped in this
// mode (the displacement carries the relief). Only used in world mode: the domain shader passes tessWorldScale in PixelPosition.w (0 = mesh mode), because the
// pixel stage doesn't reliably receive the material constant (the tools' didn't).

#ifndef BLAK_TESS_TRIPLANAR_H
#define BLAK_TESS_TRIPLANAR_H

#ifndef TRI_SHARPNESS
#define TRI_SHARPNESS 4.0	// higher = narrower blend between planes
#endif

struct TriOut
{
	float4 albedo;
	float2 nxy;	// tangent-space normal xy in the interpolated frame, -1..1
	float  nz;	// the normal map's blue-based term the gloss uses (as the stock code computes it)
	float  gloss;
	float3 spec;
	float  ao;
};

float2 TriUV(float3 p, int a)
{
	return a == 0 ? p.yz : (a == 1 ? p.xz : p.xy);
}

TriOut TriSample(float3 pw, float3 N, float3 Tg, float3 Bg, float3 sel, float bnh, float tessWorldScale)
{
	N = normalize(N);
	float3 w = pow(abs(N), TRI_SHARPNESS);
	w /= (w.x + w.y + w.z + 1e-5);

	TriOut o;
	o.albedo = 0; o.nz = 0; o.gloss = 0; o.spec = 0; o.ao = 0; o.nxy = 0;
	float3 W = 0;

	[unroll]
	for (int a = 0; a < 3; a++)
	{
		float2 uv = TriUV(pw, a) / tessWorldScale;
		float k = w[a];
#ifdef TRI_BLEND
		float lod = heightMap.CalculateLevelOfDetail(aoSampler, uv) + TESS_BLEND_BLUR;
		float bh;
		float3 bw = BlendWeights(BlendHeightsAt(uv, lod), sel, bh);
		float4 c  = BLEND_SAMPLE(colorMap, colorSampler, uv, bw);
		float3 nr = BLEND_SAMPLE(normalMap, normalSampler, uv, bw).xyz;
		float  g  = BLEND_SAMPLE(glossMap, specColorSampler, uv, bw).x;
		float3 sp = BLEND_SAMPLE(specColorMap, specColorSampler, uv, bw).xyz;
		float  ao = BLEND_AO(aoMap.Sample(aoSampler, uv).x, bw);
#else
		float4 c  = colorMap.Sample(colorSampler, uv);
		float3 nr = normalMap.Sample(normalSampler, uv).xyz;
		float  g  = glossMap.Sample(specColorSampler, uv).x;
		float3 sp = specColorMap.Sample(specColorSampler, uv).xyz;
		float  ao = aoMap.Sample(aoSampler, uv).x;
#endif
		// The stock decode of the normal map.
		nr = float3(-0.5, -0.5, 0) + nr;
		nr = bnh * nr + float3(0.5, 0.5, 0);
		float2 xy = nr.xy * 1.9921875 - 1.0;
		float  nz = min(1.0, 0.333333343 * nr.z * nr.z);
		float  z  = sqrt(max(0.0, 1.0 - dot(xy, xy)));

		// Into world space on this plane (the domain shader's plane axes; the facing sign follows the surface).
		float3 u = a == 0 ? float3(0, 1, 0) : float3(1, 0, 0);
		float3 v = a == 2 ? float3(0, 1, 0) : float3(0, 0, 1);
		float3 an = a == 0 ? float3(1, 0, 0) : (a == 1 ? float3(0, 1, 0) : float3(0, 0, 1));
		W += (u * xy.x + v * xy.y + an * z * (N[a] < 0 ? -1.0 : 1.0)) * k;

		o.albedo += c * k;
		o.nz += nz * k;
		o.gloss += g * k;
		o.spec += sp * k;
		o.ao += ao * k;
	}
	W = normalize(W);
	o.nxy = float2(dot(W, normalize(Tg)), dot(W, normalize(Bg)));
	return o;
}

#endif // BLAK_TESS_TRIPLANAR_H
