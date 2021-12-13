Shader "Hidden/ShadowGroup2D"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}
        _ShadowStencilGroup("__ShadowStencilGroup", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Cull Off
        BlendOp Add
        Blend One One
        ZWrite Off

        Pass
        {
            Stencil
            {
                Ref [_ShadowStencilGroup]
                Comp NotEqual
                Pass Replace
                Fail Keep
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float3 vertex : POSITION;
                float4 tangent: TANGENT;
                float2 uv : TEXCOORD0;
                float4 extrusion : COLOR;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            uniform float3 _LightPos;
            uniform float  _ShadowRadius;
            uniform float4 _ClockwiseRotMatrix;
            uniform float4 _AntiClockwiseRotMatrix;

            Varyings vert (Attributes v)
            {
                Varyings o;
                float3 vertexWS = TransformObjectToWorld(v.vertex);  // This should be in world space
                float3 lightDir = _LightPos - vertexWS;
                lightDir.z = 0;

                // Start of code to see if this point should be extruded
                float3 lightDirection = normalize(lightDir);  

                //ԭͶ�䷽��Ϊ��Դ����ķ�����
                float3 shadowDir = -lightDirection;
                //���÷��߲�����Ͷ��������ö�������ԭ��,��������Ϊ������
                float3 worldTangent = TransformObjectToWorldDir(v.tangent.xyz);
                //��ΪԶ����,extrusion��COLOR���ķ���,�˴�δ�޸�Դ��ı�����
                float3 anotherTangent = TransformObjectToWorldDir(v.extrusion.xyz);
                //����dot(������,���շ���),���>0��ҪͶ����Ӱ,sharedShadowTestֵΪ1. �������sharedShadowTestֵΪ0,���õ�����ԭ�ز�Ͷ��.
                float sharedShadowTest = saturate(ceil(dot(lightDirection, worldTangent)));

                //��������߷���Ͷ������
                if (sharedShadowTest > 0)
                {
                    //�������ߵİ������
                    float3 halfwayOfTangents = normalize(worldTangent + anotherTangent);
                    //��Դ�����˽�����
                    float lightTangentCrossProduct = lightDirection.x * worldTangent.y - lightDirection.y * worldTangent.x;
                    //��Դ������Զ����
                    float lightAnotherTangentCrossProduct = lightDirection.x * anotherTangent.y - lightDirection.y * anotherTangent.x;

                    float rotatedDirectionX, rotatedDirectionY;
                    if (sign(lightTangentCrossProduct) == sign(lightAnotherTangentCrossProduct))
                    {
                        //���������ڹ�Դ����ͬ������
                        //����ϵ,��ά�������Ϊ������ʱ��
                        if (lightTangentCrossProduct > 0)
                        {
                            rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                            rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
                        }
                        else
                        {
                            rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                            rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
                        }
                    }
                    else
                    {
                        //���������ڹ�Դ�����������
                        if (dot(halfwayOfTangents.xy, lightDirection.xy) > 0)
                        {
                            //�����ߵİ���������Դ����н�С��90��ʱ,Ͷ�䷽�����ת������ӹ�ת�����ߵ���ת�����෴
                            if (lightTangentCrossProduct > 0)
                            {
                                rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                                rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
                            }
                            else
                            {
                                rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                                rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
                            }
                        }
                        else
                        {
                            //�����ߵİ���������Դ����нǴ���90��ʱ,Ͷ�䷽�����ת������ӹ�ת�����ߵ���ת������ͬ
                            if (lightTangentCrossProduct > 0)
                            {
                                rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                                rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
                            }
                            else
                            {
                                rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                                rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
                            }
                        }
                    }

                    shadowDir = float3(rotatedDirectionX, rotatedDirectionY, 0);
                }

                //�����Դ�ĵ������õ�����ת��Ĺ�Դ������Ͷ��,�泯��Դ�ĵ�����ԭ��
                float3 sharedShadowOffset = sharedShadowTest * _ShadowRadius * shadowDir;

                float3 position;
                position = vertexWS + sharedShadowOffset;
                o.vertex = TransformWorldToHClip(position);



                // RGB - R is shadow value (to support soft shadows), G is Self Shadow Mask, B is No Shadow Mask
                o.color = 1 - sharedShadowTest; // v.color;
                o.color.g = 0.5;
                o.color.b = 0;

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                return o;
            }

            float4 frag (Varyings i) : SV_Target
            {
                float4 main = tex2D(_MainTex, i.uv);
                float4 col = i.color;
                col.g = main.a * col.g;
                return col;
            }
            ENDHLSL
        }
        Pass
        {
            Stencil
            {
                Ref [_ShadowStencilGroup]
                Comp NotEqual
                Pass Replace
                Fail Keep
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.vertex = TransformObjectToHClip(v.vertex);

                // RGB - R is shadow value (to support soft shadows), G is Self Shadow Mask, B is No Shadow Mask
                o.color = 1; 
                o.color.g = 0.5;
                o.color.b = 1;

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                half4 main = tex2D(_MainTex, i.uv);
                half4 color = i.color;
                color.b = 1 - main.a;

                return color;
            }
            ENDHLSL
        }
    }
}
