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

                //原投射方向即为光源方向的反方向
                float3 shadowDir = -lightDirection;
                //若该法线不符合投射条件则该顶点留在原地,符合则视为近法线
                float3 worldTangent = TransformObjectToWorldDir(v.tangent.xyz);
                //视为远法线,extrusion是COLOR里存的法线,此处未修改源码的变量名
                float3 anotherTangent = TransformObjectToWorldDir(v.extrusion.xyz);
                //计算dot(近法线,光照方向),结果>0的要投射阴影,sharedShadowTest值为1. 其余情况sharedShadowTest值为0,即该点留在原地不投射.
                float sharedShadowTest = saturate(ceil(dot(lightDirection, worldTangent)));

                //如果近法线符合投射条件
                if (sharedShadowTest > 0)
                {
                    //两条法线的半角向量
                    float3 halfwayOfTangents = normalize(worldTangent + anotherTangent);
                    //光源方向叉乘近法线
                    float lightTangentCrossProduct = lightDirection.x * worldTangent.y - lightDirection.y * worldTangent.x;
                    //光源方向叉乘远法线
                    float lightAnotherTangentCrossProduct = lightDirection.x * anotherTangent.y - lightDirection.y * anotherTangent.x;

                    float rotatedDirectionX, rotatedDirectionY;
                    if (sign(lightTangentCrossProduct) == sign(lightAnotherTangentCrossProduct))
                    {
                        //两条法线在光源方向同侧的情况
                        //左手系,二维向量叉乘为正是逆时针
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
                        //两条法线在光源方向异侧的情况
                        if (dot(halfwayOfTangents.xy, lightDirection.xy) > 0)
                        {
                            //两法线的半角向量与光源方向夹角小于90度时,投射方向的旋转方向与从光转到法线的旋转方向相反
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
                            //两法线的半角向量与光源方向夹角大于90度时,投射方向的旋转方向与从光转到法线的旋转方向相同
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

                //背离光源的点向计算得到的旋转后的光源反方向投射,面朝光源的点留在原地
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
