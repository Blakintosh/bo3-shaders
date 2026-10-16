// Domain shader for the *_conform decal techsets: a decal that takes the height of whatever is rendered under it.
//
// The decal is tessellated like the blak *_tess surfaces, and each generated vertex slides along the decal's normal
// until it meets the visible surface in the scene depth (floatZSampler, the opaque depth the engine copies before the
// decal pass). Nothing about the host is needed: tessellated brushes, patches, terrain and models (world or mesh mode),
// POM-free flat geometry, anything. The decal keeps its own UVs, vertex colour and alpha (reveal blends still work);
// its normal comes from the conformed neighbours.
//
// The pixel shader is Treyarch's gbuffer_decal.hlsl, unchanged: ds_main emits what the stock decal vertex shader does
// (SV_POSITION, COLOR0 = vertex colour^2.2, COLOR1 = vertex alpha, TEXCOORD0-3).
//
// Controls: tessDisplace (cg10_y) is the search range, units either side of the decal (cover the host's relief; 0 =
// 16); tessDecalLift (cg13_w) pulls the result towards the camera along the view ray (units: a depth bias that doesn't
// move it on screen), since the decal's vertices and the host's are not the same and the host can poke through between
// them (about 2 units for 40 units of relief). The decal tessellates at TESS_SPACING_FORCE (3 units) whatever the
// material says, so it hugs the host closely; near/far as for the other *_tess techsets.
// The search runs in screen space (see Conform): samples off screen or behind the camera are skipped, a line hidden
// all along falls back to the visible point on the view ray, and only a point nothing can place keeps the flat position.

#include "blak/blak_tess_common.hlsl"

Texture2D<float4> iSceneDepth;	// CodeTexture( "floatZSampler" ) in game; in the tools the TessTopology plugin binds it
#if TOOLSGFX
// Bound by the TessTopology MTPlugin in Radiant (the tools don't give a domain shader code textures): texel 0 =
// (MinDepth, MaxDepth, 0, 0), texel 1 = (TopLeftX, TopLeftY, Width, Height) of the viewport. Without the plugin both
// are 0 and the decal stays flat.
Texture2D<float4> iConformViewport;
#endif

// The game's scene viewport maps depth into [0, 63/64] (MaxDepth 0.984375, seen in RenderDoc on world and decal draws
// alike), so the depth buffer holds clip z/w * 63/64; compare like with like. The tools (Radiant) bind their own depth
// copy and camera constants (see iConformViewport).
#if TOOLSGFX
#define CONFORM_MATRIX gScene.transforms.offToClpMatrix
#define CONFORM_TARGET float2(gScene.renderTargetSize)
#else
#define CONFORM_VIEWPORT_DEPTH 0.984375
#define CONFORM_MATRIX viewProjectionMatrix
#define CONFORM_TARGET renderTargetSize.xy
#endif
#define CONFORM_CLIP(p) mul(float4((p) - TESS_EYE, 1.0), CONFORM_MATRIX)
#define CONFORM_STEPS 12
#define CONFORM_REFINE 6

struct DomainShaderOutput
{
	float4 				Position    				: SV_POSITION;
	float3 				Colour      				: COLOR0;
	float 				Alpha       				: COLOR1;
	float2 				TexCoord    				: TEXCOORD0;
	float3 				Normal      				: TEXCOORD1;
	float3 				Tangent     				: TEXCOORD2;
	float3 				BiTangent   				: TEXCOORD3;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float4 				MotionVectorPosition 		: TEXCOORD7;
#endif
};

// Is the world point p in front of the visible surface? (reverse Z: larger depth = nearer). onScreen says whether the
// answer means anything.
// Where the world point p lands: whether it is on screen (and in front of the camera), its own depth as the depth
// buffer would store it, and the depth the buffer holds at that pixel.
struct ScenePoint
{
	bool  onScreen;
	float depth;
	float scene;
};

// The viewport's depth range: depth buffer value = range.x + ndc depth * (range.y - range.x).
float2 ViewportDepthRange()
{
#if TOOLSGFX
	float4 range = iConformViewport.Load(int3(0, 0, 0));
	return range.y > range.x ? range.xy : float2(0, 1);
#else
	return float2(0, CONFORM_VIEWPORT_DEPTH);
#endif
}

ScenePoint Project(float3 p)
{
	ScenePoint r;
	float4 c = CONFORM_CLIP(p);
	float2 ndc = c.xy / max(c.w, 1e-4);
	// A little past the screen edge still counts, reading the depth at the nearest edge pixel (approximate, but it keeps
	// vertices just off screen on the surface instead of dropping them flat and tearing the triangles that cross the
	// edge).
	r.onScreen = c.w > 0.5 && all(abs(ndc) < 1.5);
	float2 uv = ndc * float2(0.5, -0.5) + 0.5;
#if TOOLSGFX
	float4 vp = iConformViewport.Load(int3(1, 0, 0));
	if (vp.z <= 0)
		vp = float4(0, 0, CONFORM_TARGET);
	float2 pixel = vp.xy + uv * vp.zw;
#else
	float2 pixel = uv * CONFORM_TARGET;
#endif
	float2 range = ViewportDepthRange();
	r.depth = range.x + c.z / max(c.w, 1e-4) * (range.y - range.x);
	int2 size = int2(CONFORM_TARGET);
	int2 px = clamp(int2(pixel), 0, size - 1);
	r.scene = iSceneDepth.Load(int3(px, 0)).r;
	return r;
}

// Is p in front of the visible surface (reverse Z: a larger depth is nearer)?
bool InFront(float3 p, out bool onScreen)
{
	ScenePoint r = Project(p);
	onScreen = r.onScreen;
	return r.depth >= r.scene;
}

// How far along n (within +-range) the line through p meets the visible surface. It walks down from +range; samples
// that are off screen or behind the camera (close to the surface the top of the range can be above the camera) are
// skipped, and a crossing counts from the last sample seen in front to the first one behind.
// Failing that (all of the line hidden or off screen), the visible point on the view ray through p, if it lies within
// the range; found is false only when neither works.
float Conform(float3 p, float3 n, float range, out bool found)
{
	found = false;
	bool on, front = false;
	float hi = range;
	[loop]
	for (int i = 0; i <= CONFORM_STEPS; i++)
	{
		float t = range - 2.0 * range * i / CONFORM_STEPS;
		bool f = InFront(p + n * t, on);
		if (!on)
		{
			front = false;
			continue;
		}
		if (f)
		{
			front = true;
			hi = t;
			continue;
		}
		if (front)
		{
			float lo = t;
			[unroll]
			for (int k = 0; k < CONFORM_REFINE; k++)
			{
				float m = (lo + hi) * 0.5;
				if (InFront(p + n * m, on))
					hi = m;
				else
					lo = m;
			}
			found = true;
			return (lo + hi) * 0.5;
		}
	}

	// The view ray: the clip position of eye + s * (p - eye) is s * A + B, so the depth buffer value d at p's pixel
	// gives s = (B.z - d' * B.w) / (d' * A.w - A.z), with d' the value as an ndc depth.
	ScenePoint r = Project(p);
	if (r.onScreen)
	{
		float2 dr = ViewportDepthRange();
		float d = (r.scene - dr.x) / (dr.y - dr.x);
		float4 A = mul(float4(p - TESS_EYE, 0.0), CONFORM_MATRIX);
		float4 B = mul(float4(0.0, 0.0, 0.0, 1.0), CONFORM_MATRIX);
		float den = d * A.w - A.z;
		if (abs(den) > 1e-12)
		{
			float sr = (B.z - d * B.w) / den;
			float t = dot(TESS_EYE + sr * (p - TESS_EYE) - p, n);
			if (sr > 0 && abs(t) <= range)
			{
				found = true;
				return t;
			}
		}
	}
	return 0;
}

[domain("tri")]
DomainShaderOutput ds_main(PatchConstants factors, float3 bary : SV_DomainLocation, const OutputPatch<ControlPoint, 3> patch)
{
	TessSurface s = TessInterpolate(bary, patch);
	float3 n = normalize(s.Normal);
	float range = tessDisplace != 0 ? abs(tessDisplace) : 16.0;

	bool f0, fT, fB;
	float d0 = Conform(s.Position, n, range, f0);
	float3 p0 = s.Position + n * d0;

	// Normal from two conformed neighbours, half a vertex spacing away.
	float3 tng0 = normalize(s.MeshTangent), btg0 = normalize(s.MeshBiTangent);
	float3 pT = s.Position + tng0 * s.Eps, pB = s.Position + btg0 * s.Eps;
	pT += n * Conform(pT, n, range, fT);
	pB += n * Conform(pB, n, range, fB);
	float3 nrm = n;
	if (f0 && fT && fB)
	{
		float3 c = cross(pT - p0, pB - p0);
		if (dot(c, c) > 1e-8)
		{
			c = normalize(c);
			nrm = dot(c, n) < 0 ? -c : c;
		}
	}
	float3 tng, btg;
	TessReframe(nrm, s.MeshTangent, s.MeshBiTangent, tng, btg);

	// The lift moves the vertex towards the camera along its view ray: same pixel, nearer depth. It only has to cover
	// the host's triangles poking through between the decal's vertices, and it can't make the decal float.
	float3 offset = n * d0;
	offset += normalize(TESS_EYE - (s.Position + offset)) * tessDecalLift;
	float3 pos = s.Position + offset;

	DomainShaderOutput OUT;
	OUT.Position  = Transform_ObjectToClip(Transform_ObjectToCamera(pos, 0), 0);
	OUT.Colour    = pow(abs(s.Colour.rgb), 2.2);
	// tessDebug 4: red where the search failed (flat), else blue (bottom of the range) to yellow (top).
	// tessDebug 5: where the result sits within its coarse search step (grey ramp; a flat 0.5 means no refinement).
	if (tessDebug > 4.5)
		OUT.Colour = frac((range - d0) / (2.0 * range / CONFORM_STEPS));
	else if (tessDebug > 3.5)
		OUT.Colour = f0 ? lerp(float3(0, 0, 1), float3(1, 1, 0), saturate(d0 / range * 0.5 + 0.5)) : float3(1, 0, 0);
	OUT.Alpha     = s.Colour.a;
	OUT.TexCoord  = s.MeshTexCoord;
	OUT.Normal    = nrm;
	OUT.Tangent   = tng;
	OUT.BiTangent = btg;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	OUT.MotionVectorPosition = Transform_ObjectToClipMotionVector(s.PrevPosition + offset);
#endif
	return OUT;
}
