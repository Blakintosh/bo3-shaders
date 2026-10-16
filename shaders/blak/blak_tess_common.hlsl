// Shared tessellation stages for the blak *_tess techsets: the local shader, the hull shader, and the domain shader
// helpers (world transform, interpolation, displacement). Each techset's shader file includes this and writes its
// own ds_main (and ps_main where it needs one).
//
// Where things happen, and why:
// - The game binds material/code SRVs (instance and bone buffers, textures) only to the VS, PS and DS stages, not to
//   the LS or HS. So the LS only decodes and passes the vertex through (object space), and the DS skins, transforms
//   and displaces each control point.
// - The HS never gets material constants. The LS gets them only when bb-linker linked the map with the Tessellation
//   feature. Stock leaves the LS's constant group empty and the game then doesn't rebind it, so a stock-linked LS
//   reads whatever buffer an earlier draw left bound (checked 2026-10-09: the same density whatever the material
//   said). Values outside a sane range fall back to TESS_SPACING / TESS_NEAR / TESS_FAR (a technique can override
//   them: defines += "TESS_FAR 4096"), but a stale buffer can still hold plausible numbers: on stock-linked maps the
//   material's spacing/near/far are not honoured. The LS hands the settings and the camera position to the HS per
//   control point, and the DS uses the same values, so density and displacement fade agree.
//
// Detail: each edge gets a vertex every tessSpacing units within tessNear of the camera, thinning out to a single
// segment at tessFar, where the displacement has faded to nothing too. Edge factors depend only on the edge's two
// corners, so triangles sharing an edge always agree (no cracks). Lengths and distances are measured on the control
// points, i.e. in object space: right for world geometry (wc/), unscaled for models.
//
// Displacement modes:
// - mesh (tessWorldScale 0): height from the mesh UVs, pushed along the interpolated normal. Faces with split normals
//   (hard edges) open up where they meet; use it on patches, terrain and smooth models.
// - world (tessWorldScale > 0): height from the world plane across tessWorldAxis (tessWorldScale units per texture
//   repeat), pushed along that axis, for every face. A point moves the same way whatever triangle, brush or decal it
//   belongs to, so nothing cracks, hard edges included: Z for floors and terrain, X or Y for walls. The texture is
//   box-mapped (each face projects onto the world plane it faces most), so side faces aren't streaked; on faces across
//   the axis that projection is the height's, so colour, normals and POM line up with the displacement.
//   An anchor plane (tessAnchor along the axis, tessAnchorFade units) pins the displacement to 0 there, still by
//   position only: e.g. a floor's underside, or a wall's back face.
//
// The height is sampled at the mip whose texels match the local vertex spacing (from the spacing and the distance
// falloff, position only, so shared vertices agree): detail finer than the mesh would only alias into zigzags and
// spikes; it stays in POM and the normal map.
//
// Material controls: cg10 x tessSpacing (units), y tessDisplace (world units at height 1, 0 = flat), z tessMid
// (height that stays put, 0..1), w tessDebug (1: random tint per generated vertex, 2: heat map of the inside factor,
// 3: vertex alpha replaced by a ramp along world X, to preview a blend or mask without painting);
// cg11 x tessNear, y tessFar (units), z tessWorldScale, w tessMask (displacement scaled by vertex alpha: 1 = 0..1, flattens at alpha 0;
// 2 = -1..1, 0.5 flat and 0 inverts; 3 = 0..2, 0.5 unchanged and 1 doubles it; paint it to flatten where the surface meets something else); cg13 x tessWorldAxis (1 X, 2 Y, 3 or 0 Z; negative
// pushes the other way), y tessAnchor (world coordinate along the axis), z tessAnchorFade (units, 0 = no anchor).

#ifndef BLAK_TESS_COMMON_H
#define BLAK_TESS_COMMON_H

#define DUAL_QUAT_SKINNING 1
#include "blak/blak_common.h"

// The same file serves the tools (Radiant / APE: shaders_stable_toolsgfx/blak, TOOLSGFX 1): their camera is
// gScene.wldCameraPosition, their skinning checks gObject.hasBones itself, and they have no motion vectors.
#if TOOLSGFX
#define TESS_EYE gScene.wldCameraPosition.xyz
#else
#define TESS_EYE eyeOffset.xyz
#endif

#ifndef TESS_SPACING
#if TOOLSGFX
#define TESS_SPACING 4.0	// units between vertices up close (the tools can't read the material's spacing control)
#else
#define TESS_SPACING 8.0	// units between vertices up close
#endif
#endif
#ifndef TESS_NEAR
#define TESS_NEAR 256.0		// full detail within this distance
#endif
#ifndef TESS_FAR
#define TESS_FAR 2048.0		// no tessellation or displacement beyond this distance
#endif
#define TESS_MAX_FACTOR 63.0	// fractional_odd's maximum

// Read in the LS (bb-linker only, see above).
float tessSpacing;
float tessNear;
float tessFar;
// Read in the DS.
float tessDisplace;
float tessMid;
float tessDebug;
float tessWorldScale;
float tessMask;
float tessWorldAxis;
float tessAnchor;
float tessAnchorFade;
float tessDecalLift;

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

// Object space, normals decoded. Indices/weights ride along so the DS can skin each corner.
struct ControlPoint
{
	float3 				Position    				: POSITION;
	float4 				Colour      				: COLOR;
	float2 				TexCoord    				: TEXCOORD0;
	float3 				Normal      				: NORMAL;
	float4 				Tangent     				: TANGENT;	// xyz decoded, w = bitangent sign
	float4              Weights                     : BLENDWEIGHT;
	uint4               Indices                     : BLENDINDICES;
	uint                Instance                    : TEXCOORD1;
	float3              Eye                         : TEXCOORD2;	// camera position, for the HS
	float3              Tess                        : TEXCOORD3;	// spacing, near, far
};

struct PatchConstants
{
	float 				Edge[3] 					: SV_TessFactor;
	float 				Inside 						: SV_InsideTessFactor;
};

// A material setting read in the LS, or the default when it is 0, out of range or NaN (see above).
float TessSetting(float v, float lo, float hi, float fallback)
{
	return (v >= lo && v <= hi) ? v : fallback;
}

ControlPoint ls_main(in VertexShaderInput IN, in uint instance : INSTANCE_SEMANTIC)
{
	ControlPoint OUT;
	OUT.Position   = IN.Position;
	OUT.Colour     = IN.Colour;
	OUT.TexCoord   = IN.TexCoord;
	OUT.Normal     = Utility_DecodeNormal(IN.Normal);
	OUT.Tangent    = float4(Utility_DecodeNormal(IN.Tangent.xyz), Utility_DecodeBiTangentSign(IN.Tangent.w));
	OUT.Weights    = IN.Weights;
	OUT.Indices    = IN.Indices;
	OUT.Instance   = instance;
	OUT.Eye        = TESS_EYE;
#ifdef TESS_SPACING_FORCE
	// Fixed density, ignoring the material (and any stale constants a stock-linked LS would read).
	OUT.Tess       = float3(TESS_SPACING_FORCE, TESS_NEAR, TESS_FAR);
#else
	OUT.Tess       = float3(TessSetting(tessSpacing, 0.5, 4096.0, TESS_SPACING),
	                        TessSetting(tessNear, 1.0, 65536.0, TESS_NEAR),
	                        TessSetting(tessFar, 1.0, 65536.0, TESS_FAR));
#endif
	return OUT;
}

// 1 within near of the camera, 0 at far and beyond.
float TessDetail(float3 p, float3 eye, float3 tess)
{
	return saturate((tess.z - distance(p, eye)) / max(tess.z - tess.y, 1.0));
}

// Cuts for the edge a-b: one per spacing units at full detail, down to 1 with distance.
float EdgeFactor(float3 a, float3 b, float3 eye, float3 tess)
{
	float cuts = distance(a, b) / tess.x;
	return clamp(lerp(1.0, cuts, TessDetail((a + b) * 0.5, eye, tess)), 1.0, TESS_MAX_FACTOR);
}

PatchConstants hs_constants(InputPatch<ControlPoint, 3> patch)
{
	float3 eye = patch[0].Eye, tess = patch[0].Tess;
	PatchConstants c;
	// SV_TessFactor[i] is the edge opposite corner i.
	c.Edge[0] = EdgeFactor(patch[1].Position, patch[2].Position, eye, tess);
	c.Edge[1] = EdgeFactor(patch[2].Position, patch[0].Position, eye, tess);
	c.Edge[2] = EdgeFactor(patch[0].Position, patch[1].Position, eye, tess);
	// The longest edge's: spreads vertices across long thin triangles (brush faces are often slivers).
	c.Inside  = max(c.Edge[0], max(c.Edge[1], c.Edge[2]));
	return c;
}

// fractional_odd: density changes smoothly with distance instead of popping a whole step. triangle_cw is BO3's
// front face.
[domain("tri")]
[partitioning("fractional_odd")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("hs_constants")]
ControlPoint hs_main(InputPatch<ControlPoint, 3> patch, uint id : SV_OutputControlPointID)
{
	return patch[id];
}

struct WorldCorner
{
	float3 Position;
	float3 Normal;
	float3 Tangent;
	float3 BiTangent;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float3 PrevPosition;
#endif
};

// What gbuffer_vs_lit_parallax.hlsl does to a vertex, up to world space.
WorldCorner ToWorld(ControlPoint cp)
{
	float3 pos = cp.Position;
	float3 nor = cp.Normal;
	float3 tan = cp.Tangent.xyz;
	// The SDK always skins in game (Utility_HasBones is true), which turns world vertices (no bone weights) into
	// NaNs. The prefix says whether there are bones: mc/ has USE_GPU_SKIN 1, wc/ (world) 0. (The tools check.)
#if USE_GPU_SKIN || TOOLSGFX
	Utility_SkinVertex(pos, nor, tan, cp.Indices, cp.Weights, cp.Instance);
#endif

	WorldCorner w;
	w.Position  = Transform_ObjectPositionToWorldSpace(pos, cp.Instance);
	w.Normal    = Transform_ObjectNormalToWorldSpace(nor, cp.Instance).xyz;
	w.Tangent   = Transform_ObjectNormalToWorldSpace(tan, cp.Instance).xyz;
	w.BiTangent = cross(w.Normal, w.Tangent) * cp.Tangent.w;
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float3 prev = cp.Position;
#if USE_GPU_SKIN
	Utility_SkinVertexMotionVector(prev, cp.Indices, cp.Weights, cp.Instance);
#endif
	w.PrevPosition = Transform_ObjectPositionToWorldSpaceMotionVector(prev, cp.Instance);
#endif
	return w;
}

// One generated vertex, before displacement.
struct TessSurface
{
	float3 Position;
	float3 Normal;
	float3 Tangent;
	float3 BiTangent;
	float2 TexCoord;	// for the pixel shader (box-mapped in world mode)
	float2 MeshTexCoord;	// the mesh's own UV and frame, untouched by world mode (decals keep these)
	float3 MeshTangent;
	float3 MeshBiTangent;
	float2 HeightCoord;	// where the displacement height is sampled
	float  HeightLodScale;	// texels per vertex spacing at mip 0, over the texture width (see TessHeightLod)
	float4 Colour;
	float  Detail;		// 1 up close, 0 at tessFar: scales the displacement
	float3 Direction;	// unit push direction
	int    Axis;		// world mode: the axis pushed along (0 X, 1 Y, 2 Z)
	float  Eps;		// a step about half the local vertex spacing, for normals from the displacement
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	float3 PrevPosition;
#endif
};

#define BARY(a, b, c) ((a) * bary.x + (b) * bary.y + (c) * bary.z)

// UVs on the world plane across axis a (0 X, 1 Y, 2 Z), and that plane's U and V directions.
float2 PlaneUV(float3 p, int a)
{
	return a == 0 ? p.yz : (a == 1 ? p.xz : p.xy);
}

void PlaneAxes(int a, out float3 u, out float3 v)
{
	u = a == 0 ? float3(0, 1, 0) : float3(1, 0, 0);
	v = a == 2 ? float3(0, 1, 0) : float3(0, 0, 1);
}

int DominantAxis(float3 n)
{
	float3 m = abs(n);
	return (m.x >= m.y && m.x >= m.z) ? 0 : (m.y >= m.z ? 1 : 2);
}

TessSurface TessInterpolate(float3 bary, const OutputPatch<ControlPoint, 3> patch)
{
	WorldCorner w0 = ToWorld(patch[0]);
	WorldCorner w1 = ToWorld(patch[1]);
	WorldCorner w2 = ToWorld(patch[2]);

	TessSurface s;
	s.Position  = BARY(w0.Position, w1.Position, w2.Position);
	s.Normal    = BARY(w0.Normal, w1.Normal, w2.Normal);
	s.Tangent   = BARY(w0.Tangent, w1.Tangent, w2.Tangent);
	s.BiTangent = BARY(w0.BiTangent, w1.BiTangent, w2.BiTangent);
	s.TexCoord  = BARY(patch[0].TexCoord, patch[1].TexCoord, patch[2].TexCoord);
	s.Colour    = BARY(patch[0].Colour, patch[1].Colour, patch[2].Colour);
	s.Detail    = TessDetail(s.Position, TESS_EYE, patch[0].Tess);
	s.MeshTexCoord = s.TexCoord;
	s.MeshTangent = s.Tangent;
	s.MeshBiTangent = s.BiTangent;
	s.Direction = normalize(s.Normal);
#if GENERATE_MOTION_VECTOR && !TOOLSGFX
	s.PrevPosition = BARY(w0.PrevPosition, w1.PrevPosition, w2.PrevPosition);
#endif
	// Debug 3: alpha ramps 1 -> 0 -> 1 every 256 units along world X (handed on, so the PS blends the same way).
	if (tessDebug > 2.5)
		s.Colour.a = saturate(abs(frac(s.Position.x / 256.0) * 2.0 - 1.0) * 1.6 - 0.3);

	s.Axis = 2;
	s.HeightCoord = s.TexCoord;
	float unitsPerUV;
	if (tessWorldScale > 0)
	{
		// World mode: height from the plane across the axis, pushed along it.
		float sel = abs(tessWorldAxis);
		int a = (sel > 0.5 && sel < 1.5) ? 0 : ((sel > 1.5 && sel < 2.5) ? 1 : 2);
		s.Axis = a;
		s.Direction = (a == 0 ? float3(1, 0, 0) : (a == 1 ? float3(0, 1, 0) : float3(0, 0, 1))) * (tessWorldAxis < 0 ? -1.0 : 1.0);
		s.HeightCoord = PlaneUV(s.Position, a) / tessWorldScale;
		// Box mapping for the texture: the plane this face faces most (constant per triangle), and a tangent frame
		// that matches it.
		int b = DominantAxis(cross(w1.Position - w0.Position, w2.Position - w0.Position));
		s.TexCoord = PlaneUV(s.Position, b) / tessWorldScale;
		float3 n = normalize(s.Normal), u, v;
		PlaneAxes(b, u, v);
		s.Tangent   = normalize(u - n * dot(u, n) + 1e-5);
		s.BiTangent = normalize(v - n * dot(v, n) - s.Tangent * dot(v, s.Tangent) + 1e-5);
		unitsPerUV  = tessWorldScale;
	}
	else
	{
		// Mesh mode: world units per UV from the patch (one planar-mapped face shares it; hard edges split anyway).
		float wl = distance(w0.Position, w1.Position) + distance(w1.Position, w2.Position) + distance(w2.Position, w0.Position);
		float ul = distance(patch[0].TexCoord, patch[1].TexCoord) + distance(patch[1].TexCoord, patch[2].TexCoord) + distance(patch[2].TexCoord, patch[0].TexCoord);
		unitsPerUV = wl / max(ul, 1e-5);
	}
	// Local vertex spacing from the setting and the distance falloff (position only, so shared vertices agree).
	float spacing = patch[0].Tess.x / max(s.Detail, 1.0 / 64.0);
	s.HeightLodScale = spacing / max(unitsPerUV, 1e-3);
	s.Eps = max(spacing * 0.5, 0.25);
	return s;
}

// The mip of a texture texWidth texels wide whose texels match the local vertex spacing.
float TessHeightLod(TessSurface s, float texWidth)
{
	return log2(max(s.HeightLodScale * texWidth, 1.0));
}

// A height map sampled at the displacement coordinate and the matching mip (red channel, 0..1).
float TessSampleHeight(Texture2D<float4> tex, SamplerState smp, TessSurface s)
{
	uint w, h;
	tex.GetDimensions(w, h);
	return tex.SampleLevel(smp, s.HeightCoord, TessHeightLod(s, (float)max(w, h))).r;
}

// How far to push for a height in 0..1 (white = high, as in the parallax PS).
float TessAmount(TessSurface s, float height)
{
	if (tessDisplace == 0)
		return 0;
	// Vertex alpha as a displacement scale (tessMask): 1: 0..1 (0 flattens), 2: -1..1 (0.5 flat, 0 inverts),
	// 3: 0..2 (0.5 as is, 1 doubles it).
	float a = s.Colour.a;
	float mode = tessMask;
#if BLEND_RGB_LAYERS
	// The RGB blend techsets (vertex colour picks the layers): alpha always scales the height, 0..1 unless set.
	if (mode < 0.5)
		mode = 1.0;
#endif
	float mask = mode < 0.5 ? 1.0 : (mode < 1.5 ? a : (mode < 2.5 ? a * 2.0 - 1.0 : a * 2.0));
	// Anchor plane (world mode): 0 at the plane, full tessAnchorFade units away from it.
	if (tessWorldScale > 0 && tessAnchorFade > 0)
		mask *= saturate(abs(dot(s.Position, abs(s.Direction)) - tessAnchor) / tessAnchorFade);
	return (height - tessMid) * tessDisplace * s.Detail * mask;
}

// World mode: the displaced surface's normal. The caller evaluates the displacement amount at the vertex (d0) and at
// a step of s.Eps along the tangent and bitangent (surfaces from TessShift); the normal is the cross product of
// the displaced tangent directions. Elsewhere (mesh mode, or no displacement) the face normal stands.
bool TessHasNormal()
{
	return tessWorldScale > 0 && tessDisplace != 0;
}

TessSurface TessShift(TessSurface s, float3 d)
{
	s.Position += d;
	s.HeightCoord = PlaneUV(s.Position, s.Axis) / tessWorldScale;
	return s;
}

float3 TessDisplacedNormal(TessSurface s, float d0, float dT, float dB)
{
	float3 pt = s.Tangent + s.Direction * ((dT - d0) / s.Eps);
	float3 pb = s.BiTangent + s.Direction * ((dB - d0) / s.Eps);
	float3 n = normalize(cross(pt, pb));
	return dot(n, s.Normal) < 0 ? -n : n;
}

// A tangent frame for the normal n, as close to the surface's own tangents as it can be.
void TessReframe(float3 n, float3 t0, float3 b0, out float3 t, out float3 b)
{
	t = normalize(t0 - n * dot(t0, n));
	b = cross(n, t);
	b = dot(b, b0) < 0 ? -b : b;
}

// The vertex colour for the pixel shader, which multiplies the albedo by it: a mesh nobody painted (all zero) is white.
float3 TessVertexColour(TessSurface s)
{
	return dot(s.Colour.xyz, 1.0) <= 0 ? float3(1, 1, 1) : s.Colour.xyz;
}

// Debug tints (tessDebug 1: random per generated vertex; 2: heat map, red = 1, green = 16, blue = 32+).
float3 TessDebugTint(float3 bary, PatchConstants factors)
{
	if (tessDebug > 2.5)
		return 1;
	if (tessDebug > 1.5)
	{
		float t = saturate((factors.Inside - 1.0) / 31.0);
		return t < 0.5 ? lerp(float3(1, 0, 0), float3(0, 1, 0), t * 2) : lerp(float3(0, 1, 0), float3(0, 0, 1), t * 2 - 1);
	}
	if (tessDebug > 0)
	{
		float3 k = round(bary * factors.Inside);
		return frac(sin(dot(k, float3(12.9898, 78.233, 37.719))) * float3(43758.5453, 28001.8384, 50849.4141));
	}
	return 1;
}

#endif // BLAK_TESS_COMMON_H
