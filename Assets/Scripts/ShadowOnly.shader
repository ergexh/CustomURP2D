Shader "Custom/ShadowOnly"
{
    Properties
    {
        _ShadowAlpha("ShadowAlpha", Range(0,1)) = 0
    }
        SubShader
        {
            Tags { "Queue" = "Transparent" "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Pass
            {
                Tags {"LightMode" = "Universal2D"}
                HLSLPROGRAM

                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

                #pragma vertex vert
                #pragma fragment frag

                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE


                CBUFFER_START(UnityPerMaterial)
                float _ShadowAlpha;
                half4 _MainTex_ST;
                CBUFFER_END


                struct a2v
                {
                    float4 vertex: POSITION;
                    float2 uv:     TEXCOORD0;
                };

                struct v2f
                {
                    float4 pos:        SV_POSITION;
                    float3 worldPos:   TEXCOORD0;
                    float2 uv:         TEXCOORD2;
                };

                v2f vert(a2v v)
                {
                    v2f o;
                    o.pos = TransformObjectToHClip(v.vertex.xyz);
                    o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                    return o;
                }

                half4 frag(v2f i) : SV_TARGET
                {
                    Light light = GetMainLight(TransformWorldToShadowCoord(i.worldPos));
                    half atten = light.shadowAttenuation;
                    if (atten < 1) return half4(0, 0, 0, _ShadowAlpha);
                    else discard;
                    return half4(0, 0, 0, 0);
                }
                ENDHLSL
            }
        }
}