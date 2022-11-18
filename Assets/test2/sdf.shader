Shader "Unlit/sdf"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("_Color", Color) = (0.5,1,0.5,1)
        _BackgroundColor ("_BackgroundColor", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f {
                float4 pos : SV_POSITION;
                float4 scrPos : TEXCOORD0;
                float2 uv : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            fixed4 _BackgroundColor;

            // 渲染函数
            float4 render(float d, float3 color, float stroke) 
            {
                float anti = fwidth(d) * 1.0;
                float4 colorLayer = float4(color, 1.0 - smoothstep(-anti, anti, d));
                if (stroke < 0.000001) {
                    return colorLayer;
                }

                float4 strokeLayer = float4(float3(0.05, 0.05, 0.05), 1.0 - smoothstep(-anti, anti, d - stroke));
                return float4(lerp(strokeLayer.rgb, colorLayer.rgb, colorLayer.a), strokeLayer.a);
            }

            // 圆形
            float sdfCircle(float2 coord, float2 center, float radius)
            {
                float2 offset = coord - center;
                return sqrt((offset.x * offset.x) + (offset.y * offset.y)) - radius;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.scrPos = ComputeScreenPos(o.pos);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float2 pixelPos = (i.scrPos.xy / i.scrPos.w)*_ScreenParams.xy;
                float a = sdfCircle(pixelPos, float2(0.5, 0.5)* _ScreenParams.xy, 100);
                float4 layer1 = render(a, _Color, fwidth(a) * 2.0);
                // return lerp(_BackgroundColor, layer1, layer1.a);
                return lerp(_BackgroundColor, layer1, layer1.a);
            }
            ENDCG
        }
    }
}
