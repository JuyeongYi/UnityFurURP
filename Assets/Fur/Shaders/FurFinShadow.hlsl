#ifndef FUR_FIN_SHADOW_HLSL
#define FUR_FIN_SHADOW_HLSL

#include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"
#include "./FurFinParam.hlsl"
#include "./FurCommon.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 vertex : SV_POSITION;
    float2 uv : TEXCOORD0;
    float fogCoord : TEXCOORD1;
    float2 finUv : TEXCOORD2;
};

Attributes vert(Attributes input)
{
    return input;
}

void AppendFinVertex(
    inout TriangleStream<Varyings> stream, 
    float2 uv, 
    float3 posOS, 
    float3 normalWS,
    float2 finUv)
{
    Varyings output;

#ifdef SHADOW_CASTER_PASS
    float3 posWS = TransformObjectToWorld(posOS);
    output.vertex = GetShadowPositionHClip(posWS, normalWS);
#else
    output.vertex = TransformObjectToHClip(posOS);
#endif
    output.uv = uv;
    output.fogCoord = ComputeFogFactor(output.vertex.z);
    output.finUv = finUv;

    stream.Append(output);
}

void AppendFinVertices(
    inout TriangleStream<Varyings> stream,
    Attributes input0,
    Attributes input1,
    Attributes input2,
    float3 normalOS)
{
    float3 posOS0 = input0.positionOS.xyz;
    float3 lineOS01 = input1.positionOS.xyz - posOS0;
    float3 lineOS02 = input2.positionOS.xyz - posOS0;
    float3 posOS3 = posOS0 + (lineOS01 + lineOS02) / 2;

    float2 uv0 = TRANSFORM_TEX(input0.uv, _BaseMap);
    float2 uv12 = (TRANSFORM_TEX(input1.uv, _BaseMap) + TRANSFORM_TEX(input2.uv, _BaseMap)) / 2;
    float uvOffset = length(uv0);
    float uvXScale = length(uv0 - uv12) * _Density;
    float3 normalWS = TransformObjectToWorldNormal(normalOS);

    AppendFinVertex(stream, uv0, posOS0, normalWS, float2(uvOffset, 0.0));
    AppendFinVertex(stream, uv12, posOS3, normalWS, float2(uvOffset + uvXScale, 0.0));

    float3 posWS = TransformObjectToWorld(posOS0);
    float finStep = _FinLength / _FinJointNum;
    float3 windAngle = _Time.w * _WindFreq.xyz;
    float3 windMoveWS = _WindMove.xyz * sin(windAngle + posWS * _WindMove.w);
    float3 baseMoveWS = _BaseMove.xyz;

    [loop] for (int i = 1; i <= _FinJointNum; ++i)
    {
        float finFactor = (float)i / _FinJointNum;
        float moveFactor = pow(abs(finFactor), _BaseMove.w);
        float3 moveWS = SafeNormalize(normalWS + (baseMoveWS + windMoveWS) * moveFactor) * finStep;
        float3 moveOS = TransformWorldToObjectDir(moveWS, false);
        posOS0 += moveOS;
        posOS3 += moveOS;
        AppendFinVertex(stream, uv0, posOS0, normalWS, float2(uvOffset, finFactor));
        AppendFinVertex(stream, uv12, posOS3, normalWS, float2(uvOffset + uvXScale, finFactor));
    }
    stream.RestartStrip();
}

[maxvertexcount(75)]
void geom(triangle Attributes input[3], inout TriangleStream<Varyings> stream)
{
#ifdef DRAW_ORIG_POLYGON
    for (int i = 0; i < 3; ++i)
    {
        Varyings output;
        output.vertex = TransformObjectToHClip(input[i].positionOS.xyz);
        output.uv = TRANSFORM_TEX(input[i].uv, _BaseMap);
        output.fogCoord = ComputeFogFactor(output.vertex.z);
        output.finUv = float2(-1.0, -1.0);
        stream.Append(output);
    }
    stream.RestartStrip();
#endif

    float3 lineOS01 = (input[1].positionOS - input[0].positionOS).xyz;
    float3 lineOS02 = (input[2].positionOS - input[0].positionOS).xyz;
    float3 normalOS = normalize(cross(lineOS01, lineOS02));
    float3 centerOS = (input[0].positionOS + input[1].positionOS + input[2].positionOS).xyz / 3;
    float3 viewDirOS = GetViewDirectionOS(centerOS);
    float eyeDotN = dot(viewDirOS, normalOS);
    if (abs(eyeDotN) > _FaceViewProdThresh) return;

    normalOS += rand3(input[0].uv) * _RandomDirection;
    normalOS = normalize(normalOS);

    AppendFinVertices(stream, input[0], input[1], input[2], normalOS);
#ifdef APPEND_MORE_FINS
    AppendFinVertices(stream, input[2], input[0], input[1], normalOS);
    AppendFinVertices(stream, input[1], input[2], input[0], normalOS);
#endif
}

void frag(
    Varyings input, 
    out float4 outColor : SV_Target, 
    out float outDepth : SV_Depth)
{
    float4 furColor = SAMPLE_TEXTURE2D(_FurMap, sampler_FurMap, input.finUv);
    float alpha = furColor.a;
    if (alpha < _AlphaCutout) discard;

    outColor = outDepth = input.vertex.z / input.vertex.w;
}

#endif
