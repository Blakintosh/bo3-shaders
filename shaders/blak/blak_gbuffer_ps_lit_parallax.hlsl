#define PC
#include "blak/blak_common.h"

float4 	flagParams;
float4 	colorObjMin;
float4 	colorObjMax;
float 	colorObjMinBaseBlend;
float 	colorObjMaxBaseBlend;
float2 	uvScroll;
float4 	detailScale;
float4 	detailScale1;
float4 	detailScale2;
float4 	detailScale3;
float4 	alphaRevealParms;
float4 	colorDetailScale;
float3 	specColorTint;
float 	baseNormalHeight;
float2 	glossRange;
float 	detailScaleHeight;
float 	emissiveFalloffPower;
float 	scriptController1;
float3 colorTint;
float tessSize;
#if TOOLSGFX
float cg00_x;
float cg00_y;
#endif

// Data our vertex shader sends to the pixel shader
// including screen position, transformed normals, etc.
// This should work for most GBuffer shaders, but some
// (especially forward rendering materials) might expect
// different values passed to them (for example the red dot material)
struct PixelShaderInput
{
	float4 				Position    		  		: SV_POSITION;
    float3              Colour                      : COLOR0;
	float 				Alpha      	    	  		: COLOR1;
	float2 				TexCoord       				: TEXCOORD0;
	float3 				Normal      		  		: TEXCOORD1;
	float3 				Tangent     		  		: TEXCOORD2;
	float3 				BiTangent   		  		: TEXCOORD3;
    float4              PixelPosition               : TEXCOORD4;
    float3              TangentViewPos              : TEXCOORD5;
    float3              TangentPixelPos             : TEXCOORD6;
    uint                IsFrontFace                 : SV_IsFrontFace;
};

// PixelShaderGBufferOutput from Common.hlsl

SamplerState colorSampler : register(s0);
SamplerState normalSampler : register(s1);
SamplerState specColorSampler : register(s2);
SamplerState aoSampler : register(s3);
Texture2D<float4> colorMap : register(t0);
Texture2D<float4> normalMap : register(t1);
Texture2D<float4> specColorMap : register(t2);
Texture2D<float4> glossMap : register(t3);
Texture2D<float4> aoMap : register(t4);
Texture2D<float4> heightMap : register(t5);


#include "blak/tess_triplanar.h"

// 3Dmigoto declarations
#define cmp -
Texture1D<float4> IniParams : register(t120);
Texture2D<float4> StereoParams : register(t125);

// Returns the reciprocal square root of the dot product of a float3 vector twice
float DotRsqrt(float3 input)
{
    float Val = dot(input, input);
    
    return rsqrt(Val);
}

float2 ParallaxMapping(float2 texCoords, float3 viewDir)
{ 
    // number of depth layers
#if TOOLSGFX
    float maxLayers = cg00_x;
    float minLayers = maxLayers / 4;
    float numLayers = lerp(maxLayers, minLayers, max(dot(float3(0.0, 0.0, 1.0), viewDir), 0.0)); 
#else
    const float numLayers = 128;
#endif

#if TOOLSGFX
    float maxSamples = cg00_y;
#else
    float maxSamples = 512;
#endif
    // calculate the size of each layer
    float layerDepth = 1.0 / numLayers;
    // depth of current layer
    float currentLayerDepth = 0.0;
    // the amount to shift the texture coordinates per layer (from vector P)
    float2 P = viewDir.xy * tessSize; 
    float2 deltaTexCoords = P / numLayers;   

    // get initial values
    float2  currentTexCoords     = texCoords;
    float currentDepthMapValue = 1 - heightMap.Sample(aoSampler, currentTexCoords).r;
    
    while(maxSamples && currentLayerDepth < currentDepthMapValue)
    {
        // shift texture coordinates along direction of P
        currentTexCoords -= deltaTexCoords;
        // get depthmap value at current texture coordinates
#if TOOLSGFX
        currentDepthMapValue = 1 - heightMap.SampleLevel(aoSampler, currentTexCoords, 0).r;
#else
        currentDepthMapValue = 1 - heightMap.Sample(aoSampler, currentTexCoords).r;
#endif
        // get depth of next layer
        currentLayerDepth += layerDepth;  
        maxSamples--;
    }

#if TOOLSGFX
    // get texture coordinates before collision (reverse operations)
    float2 prevTexCoords = currentTexCoords + deltaTexCoords;

    // get depth after and before collision for linear interpolation
    float afterDepth  = currentDepthMapValue - currentLayerDepth;
    float beforeDepth = heightMap.Sample(aoSampler, currentTexCoords).r - currentLayerDepth + layerDepth;
    
    // interpolation of texture coordinates
    float weight = afterDepth / (afterDepth - beforeDepth);
    float2 finalTexCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);

    return finalTexCoords;
#else
    return currentTexCoords;
#endif
} 

PixelShaderGBufferOutput ps_main( in PixelShaderInput IN )
{
    PixelShaderGBufferOutput OUT;

    // -- Parallax --

    float3 viewDir   = normalize( IN.TangentViewPos - IN.TangentPixelPos );
    //float2 UpdatedTexCoord = IN.TexCoord;
    bool tri = IN.PixelPosition.w > 0;
    TriOut TR = (TriOut)0;
    float2 UpdatedTexCoord = IN.TexCoord;
    if (tri)
        TR = TriSample(IN.PixelPosition.xyz, IN.Normal, IN.Tangent, IN.BiTangent, IN.Alpha, baseNormalHeight, IN.PixelPosition.w);
    else
        UpdatedTexCoord = ParallaxMapping(IN.TexCoord, viewDir);

    //if(UpdatedTexCoord.x > 1.0 || UpdatedTexCoord.y > 1.0 || UpdatedTexCoord.x < 0.0 || UpdatedTexCoord.y < 0.0) discard;
    //eyeoffset
    //gScene.wldCameraPosition

    // -- GBUFFER ALBEDO (COLOR AND TINT) --

    // Get Albedo Tint
    float3 AlbedoTint = float3(-1,-1,-1) + colorTint.xyz;

    float4 AlbedoColor;
    if (tri)
        AlbedoColor = TR.albedo;
    else
        AlbedoColor = colorMap.Sample(colorSampler, UpdatedTexCoord.xy);

    // In non-Tint Mask shaders, the Alpha channel of colorMap is used as the tint mask.
    AlbedoTint = AlbedoColor.www * AlbedoTint + float3(1, 1, 1);

    // GBuffer output for Albedo
    OUT.Albedo.xyz = AlbedoTint * IN.Colour * AlbedoColor.xyz;
    OUT.Albedo.w = 1;

    // -- GBUFFER NORMALGLOSS (NORMAL AND GLOSS) --
    float4 r0,r1,r2,r3;

    if (tri)
    {
        r0.xy = TR.nxy;
        r0.z = TR.nz;
    }
    else
    {
        r0.xyz = normalMap.Sample(normalSampler, UpdatedTexCoord.xy).xyz;
        r0.xyz = float3(-0.5,-0.5,-0) + r0.xyz;
        r0.xyz = baseNormalHeight * r0.xyz + float3(0.5,0.5,0);
        r0.xy = r0.xy * float2(1.9921875,1.9921875) + float2(-1,-1);
        r0.z = r0.z * r0.z;
        r0.z = 0.333333343 * r0.z;
        r0.z = min(1, r0.z);
    }
    r0.w = dot(IN.BiTangent.xyz, IN.BiTangent.xyz);
    r0.w = rsqrt(r0.w);
    r1.xyz = IN.BiTangent.xyz * r0.www;
    r0.w = IN.IsFrontFace.x ? 1 : -1;
    r1.xyz = r1.xyz * r0.www;
    r1.xyz = r1.xyz * r0.yyy;
    r1.w = dot(IN.Tangent.xyz, IN.Tangent.xyz);
    r1.w = rsqrt(r1.w);
    r2.xyz = IN.Tangent.xyz * r1.www;
    r2.xyz = r2.xyz * r0.www;
    r1.xyz = r2.xyz * r0.xxx + r1.xyz;
    r0.x = dot(r0.xy, r0.xy);
    r0.x = 1 + -r0.x;
    r0.x = max(0, r0.x);
    r0.x = sqrt(r0.x);
    r0.y = dot(IN.Normal.xyz, IN.Normal.xyz);
    r0.y = rsqrt(r0.y);
    r2.xyz = IN.Normal.xyz * r0.yyy;
    r3.xyz = r2.xyz * r0.www;
    r1.xyz = r3.xyz * r0.xxx + r1.xyz;
    r0.x = r3.x + r3.y;
    r0.x = r2.z * r0.w + r0.x;
    r0.x = 0.5 * r0.x;
    r0.y = dot(r1.xyz, r1.xyz);
    r0.y = rsqrt(r0.y);
    r1.yzw = r1.xyz * r0.yyy;
    r3.yzw = float3(1,-1,-1) * r1.yzw;
    r3.x = 1;
    r1.x = 0;
    r2.xyz = r2.xyz * r0.www + -r0.xxx;
    r0.y = max(r2.y, r2.z);
    r0.y = max(r2.x, r0.y);
    r0.x = max(r0.x, r0.y);
    r0.y = cmp(r0.x == r2.x);
    r1.xyzw = r0.yyyy ? r3.xyzw : r1.xyzw;
    r3.yzw = float3(-1,1,-1) * r1.yzw;
    r3.x = 2;
    r0.w = 2 + r0.x;
    r0.x = r0.y ? r0.w : r0.x;
    r0.y = cmp(r0.x == r2.y);
    r1.xyzw = r0.yyyy ? r3.xyzw : r1.xyzw;
    r3.yzw = float3(-1,-1,1) * r1.yzw;
    r0.w = 2 + r0.x;
    r0.x = r0.y ? r0.w : r0.x;
    r0.x = cmp(r0.x == r2.z);
    r3.x = 3;
    r1.xyzw = r0.xxxx ? r3.xyzw : r1.xyzw;
    r0.x = r1.y + r1.z;
    r2.z = r0.x + r1.w;
    r2.x = -r1.z * 3 + r2.z;
    r2.y = r1.w + -r1.y;
    r0.x = (uint)r1.x;
    OUT.NormalGloss.w = 0.333333343 * r0.x;
    r0.xyw = float3(0.408248305,0.707106769,0.577350259) * r2.xyz;
    r0.w = 1 + abs(r0.w);
    r0.w = rsqrt(r0.w);
    r0.xy = r0.xy * r0.ww;
    OUT.NormalGloss.xy = r0.xy * float2(0.588235319,0.588235319) + float2(0.5,0.5);
    if (tri)
        r0.x = TR.gloss;
    else
        r0.x = glossMap.Sample(specColorSampler, UpdatedTexCoord.xy).x;
    r0.y = glossRange.y + -glossRange.x;
    r0.x = r0.x * r0.y + glossRange.x;
    r0.x = saturate(0.0588235296 * r0.x);
    r0.x = -17 * r0.x;
    r0.x = exp2(r0.x);
    r0.x = r0.z + r0.x;
    r0.x = log2(r0.x);
    r0.x = -0.0588235296 * r0.x;
    r0.x = max(0, r0.x);
    OUT.NormalGloss.z = r0.x * 0.49755621 + 0.00146627566;

    // -- GBUFFER REFLECTANCEOCCLUSION (SPECULAR AND AO) --
    uint2 Position = (uint2)IN.Position.xy;
    Position = (int2)Position & int2(1,1);
    Position.x = -((int)Position.y == (int)Position.x);
    float3 Spec;
    if (tri)
        Spec = TR.spec;
    else
        Spec = specColorMap.Sample(specColorSampler, UpdatedTexCoord.xy).xyz;
    float3 Coins;

    Coins.y = Spec.x + -Spec.z;
    float Fuck = Coins.y * 0.5 + Spec.z;
    Coins.z = Spec.y + -Fuck;
    Coins.x = Coins.z * 0.5 + Spec.x;
    float2 Output = Position.xx ? Coins.xy : Coins.xz;
    OUT.ReflectanceOcclusion.xy = Output.xy * float2(1,0.5) + float2(0,0.5);

    // AO
    if (tri)
        OUT.ReflectanceOcclusion.z = TR.ao;
    else
        OUT.ReflectanceOcclusion.z = aoMap.Sample(aoSampler, UpdatedTexCoord.xy).x;
    OUT.ReflectanceOcclusion.w = 0.333333343;
    return OUT;
}