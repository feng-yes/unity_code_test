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

            // 圆环  空洞半径 = radius1 - radius2
            float sdfTorus(float2 coord, float2 center, float radius1, float radius2)
            {
                float2 offset = coord - center;
                return abs(sqrt((offset.x * offset.x) + (offset.y * offset.y)) - radius1) - radius2;
            }

            // 椭圆 参考椭圆方程
            float sdfEclipse(float2 coord, float2 center, float a, float b)
            {
                float a2 = a * a;
                float b2 = b * b;
                return (b2 * (coord.x - center.x) * (coord.x - center.x) +
                    a2 * (coord.y - center.y) * (coord.y - center.y) - a2 * b2) / (a2 * b2);
            }

            // 矩形
            float sdfBox(float2 coord, float2 center, float width, float height)
            {
                float2 d = abs(coord - center) - float2(width, height);
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
            }

            // 圆角矩形
            float sdfRoundBox(float2 coord, float2 center, float width, float height, float r)
            {
                float2 d = abs(coord - center) - float2(width, height);
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
            }

            // 并集
            float sdfUnion(const float a, const float b) {
                return min(a, b);
            }

            // 只有a没有b的部分
            float sdfDifference(const float a, const float b) {
                return max(a, -b);
            }

            // 交集
            float sdfIntersection(const float a, const float b) {
                return max(a, b);
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

                // == 基础图形 ==
                /*float Circle = sdfCircle(pixelPos, float2(0.6, 0.75) * _ScreenParams.xy, 50);
                float torus = sdfTorus(pixelPos, float2(0.2, 0.5) * _ScreenParams.xy, 50, 30);
                float eclipse = sdfEclipse(pixelPos, float2(0.4, 0.5) * _ScreenParams.xy, 100, 50);
                float box = sdfBox(pixelPos, float2(0.6, 0.5) * _ScreenParams.xy, 70, 50);
                float roundBox = sdfRoundBox(pixelPos, float2(0.8, 0.5) * _ScreenParams.xy, 70, 40, 10);

                float4 layer1 = render(Circle, _Color, fwidth(Circle) * 2.0);
                float4 torusLayer = render(torus, _Color, fwidth(torus) * 2.0);
                float4 eclipseLayer = render(eclipse, float3(0.91, 0.12, 0.39), fwidth(eclipse) * 2.0);
                float4 boxLayer = render(box, float3(0.3, 0.69, 0.31), fwidth(box) * 2.0);
                float4 roundBoxLayer = render(roundBox, float3(1, 0.76, 0.03), fwidth(roundBox) * 2.0);

                float4 col = lerp(_BackgroundColor, layer1, layer1.a);
                col *= lerp(_BackgroundColor, torusLayer, torusLayer.a);
                col *= lerp(_BackgroundColor, eclipseLayer, eclipseLayer.a);
                col *= lerp(_BackgroundColor, boxLayer, boxLayer.a);
                col *= lerp(_BackgroundColor, roundBoxLayer, roundBoxLayer.a);*/
                // == 基础图形 ==

                // == 集合运算 ==
                float circle = sdfCircle(pixelPos, float2(0.2, 0.5) * _ScreenParams.xy, 100);
                float circle2 = sdfCircle(pixelPos, float2(0.5, 0.5) * _ScreenParams.xy, 100);
                float circle3 = sdfCircle(pixelPos, float2(0.8, 0.5) * _ScreenParams.xy, 100);

                float box = sdfBox(pixelPos, float2(0.2, 0.5) * _ScreenParams.xy, 120, 70);
                float box2 = sdfBox(pixelPos, float2(0.5, 0.5) * _ScreenParams.xy, 120, 70);
                float box3 = sdfBox(pixelPos, float2(0.8, 0.5) * _ScreenParams.xy, 120, 70);

                float unionResult = sdfUnion(circle, box);
                float diffResult = sdfDifference(circle2, box2);
                float intersectResult = sdfIntersection(circle3, box3);

                float4 unionLayer = render(unionResult, float3(0.91, 0.12, 0.39), fwidth(unionResult) * 2.0);
                float4 diffLayer = render(diffResult, float3(0.3, 0.69, 0.31), fwidth(diffResult) * 2.0);
                float4 intersectLayer = render(intersectResult, float3(1, 0.76, 0.03), fwidth(intersectResult) * 2.0);

                float4 col = lerp(_BackgroundColor, unionLayer, unionLayer.a);
                col *= lerp(_BackgroundColor, diffLayer, diffLayer.a);
                col *= lerp(_BackgroundColor, intersectLayer, intersectLayer.a);
                // == 集合运算 ==

                return col;
            }
            ENDCG
        }
    }
}
