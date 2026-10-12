#ifndef __COMMON_TOOLSGFX_STRUCT_INCLUDED__
#define __COMMON_TOOLSGFX_STRUCT_INCLUDED__

// The following structures and data were obtained from shaders included in the Black Ops III Mod Tools

struct CodeSceneTransforms
{
	row_major float4x4 					wldToCamMatrix;
	row_major float4x4 					camToOffMatrix;
	row_major float4x4 					offToCamMatrix;
	row_major float4x4 					camToClpMatrix;
	row_major float4x4 					camToWldMatrix;
	row_major float4x4 					wldToClpMatrix;
	row_major float4x4 					offToClpMatrix;
	row_major float4x4 					clpToCamMatrix;
};

struct CoreFogConstants
{
	float4 								fogColor;
	float4 								sunFogColor;
	float 								K0;
	float 								skyK0;
	float 								expMul;
	float 								expAdd;
	float 								heightFalloff;
	float 								skyHeightFalloff;
	float 								K0b;
	float 								padding0;
	float 								skyK0b;
	float3 								wldSunFogDir;
	float2 								sunFogAngles;
	float 								atmospheresunstrength;
	float 								atmosphereMieSchlickK;
	float2 								atmosphereskyfogdensityatcamera;
	float 								atmosphereExtinctionIntensity;
	float 								atmosphereInScatterIntensity;
	float3 								atmosphereRayleighDensity;
	float 								atmospherehazebasedist;
	float3 								atmosphereMieDensity;
	float 								atmospherehazefadedist;
	float3 								atmosphereTotalDensity;
	float 								worldfogskysize;
	float3 								atmosphereInScatterIntensityOverTotalDensity;
	float 								blendAmount;
	float2 								atmosphereskyfogheightdensityscale;
	float2 								atmospherefogdistanceoffset;
	float2 								atmospherefogdistancedensityscale;
	float2 								atmospherefogheightdensityscale;
	float2 								atmospherefogdensityatcamera;
	float2 								padding1;
};

struct SSTConstants
{
	float2 								dimensionInTiles;
	float 								inchesPerTexel;
	float 								spanInInches;
};

struct SSTLightingConstants
{
	SSTConstants 						constants;
	row_major float4x4 					offToPinTransform;
	float 								coordScale;
	uint 								rootOffset;
	uint2 								pad0;
};

struct CoreSunConstants
{
	float3 								wldDir;
	float 								splitDepthOffset;
	float3 								color;
	float 								specScale;
	float 								globalProbeExposure;
	float3 								avgGlobalProbeColor;
	float4 								splitPinTransform[3];
	uint 								sunCookieIndex;
	float 								sunCookieIntensity;
	float 								sunVolumetricCookieIntensity;
	uint 								toolsGfxDisableSunShadow;
	float4 								sunCookieTransform[2];
	float 								intensity;
	int 								splitArrayOffset;
	float2 								pad0;
	SSTLightingConstants 				sstLightingConstants;
};

struct CoreGlobalProbePack
{
	uint4                               data[3];
};

struct CoreWeatherConsts
{
	float                               rain;
	float                               windSpeed;
	float                               windDirSin;
	float                               windDirCos;
	float                               weatherTile;
	float3                              weatherVector;
	float3                              weatherVector2;
	float                               padding0;
	float3                              weatherTint;
	float                               padding1;
	float3                              weatherTint2;
	float                               padding2;
};

struct TriDensitySettings 
{
	uint4                               flags;
	float4                              params;
};

struct ShaderDebugConstants {
	float4                              debugTunable0;
	float4                              debugTunable1;
	float4                              debugTunable2;
	float4                              debugTunable3;
	float                               debugSlider0;
	float                               debugSlider1;
	float                               debugSlider2;
	float                               debugSlider3;
	uint                                debugToggle0;
	uint                                debugToggle1;
	uint                                debugToggle2;
	uint                                debugToggle3;
};

struct CodeSceneConsts
{
	CodeSceneTransforms                 transforms;
	CoreFogConstants                    fog;
	CoreSunConstants                    sun;
	CoreGlobalProbePack                 globalProbe;
	CoreWeatherConsts                   weather;
	TriDensitySettings                  triDensity;
	SSTLightingConstants                outdoorOcclusionTreeConstants;
	float4                              outdoorPinToWorldZ;
	ShaderDebugConstants                shaderDebugConstants;
	float3                              wldCameraPosition;
	float                               padding1;
	float4                              viewSpaceScaleBias;
	uint2                               renderTargetSize;
	float2                              renderTargetInvSize;
	float                               nearClip;
	float                               farClipScale;
	float                               time;
	float                               siegeTime;
	float                               exposure;
	float                               invExposure;
	float                               exposureClamped;
	float                               padding2;
	uint                                numLights;
	uint                                numProbes;
	uint                                numShadowedLights;
	uint                                numOverrideProbes;
	uint                                lightingMode;
	uint                                numLitFogVolumes;
	uint                                numComputeSprites;
	uint                                padding3;
	float2                              gSpotShadowResolutionAndRcp;
	uint                                computeSpritesDebug;
	uint                                numComputeLmaps;
	float2                              skyRotation;
	float                               skySize;
	float                               skyTransition;
	uint                                forceViewToNormal;
	uint                                numForwardDecals;
	uint                                numAttenuationVolumes;
	uint                                fullHDR;
	float4                              extraClipPlane0;
	float4                              extraClipPlane1;
};

struct CodeObjectConsts
{
	row_major float4x4                  worldMatrix;
	float4                              customFloat4s[7];
	int4                                customInt4s;
	uint                                hasBones;
	uint                                hasSiegeAnim;
	float                               siegeAnimOffset;
	float                               sortDepth;
};

struct CodeObjectBonesConst
{
	row_major float3x4                  objMatrixT;
	float4                              extra;
};

#endif // __COMMON_TOOLSGFX_STRUCT_INCLUDED__