Shader "Unlit/sdf"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("_Color", Color) = (0.5,1,0.5,1)
        _BackgroundColor ("_BackgroundColor", Color) = (1,1,1,1)
        _xScale ("_xScale", float) = 1.0
        _yScale ("_yScale", float) = 1.0
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
            float _xScale;
            float _yScale;

            // 渲染函数（抗锯齿）
            float4 renderSimple(float d, float3 color) 
            {
                float anti = fwidth(d) * 1.0;
                return float4(color, 1.0 - smoothstep(-anti, anti, d));
            }

            // 渲染函数（包含描边，抗锯齿）；stroke 描边大小
            float4 render(float d, float3 color, float stroke) 
            {
                float anti = fwidth(d) * 1.0;
                // 1.0 - smoothstep(-anti, anti, d)  d 从 -anti 到 anti, 由 1 缓慢下降到 0 
                float4 colorLayer = float4(color, 1.0 - smoothstep(-anti, anti, d));
                if (stroke < 0.000001) {
                    return colorLayer;
                }
                // 1.0 - smoothstep(-anti, anti, d - stroke) 相当于上式往右边平移
                float4 strokeLayer = float4(float3(0.05, 0.05, 0.05), 1.0 - smoothstep(-anti, anti, d - stroke));
                // 往右边平移多出来的图形部分涂上 strokeLayer
                return float4(lerp(strokeLayer.rgb, colorLayer.rgb, colorLayer.a), strokeLayer.a);
            }

            // 外发光
            float4 outerGlow(float dist_f_, float4 color_v4_, float4 input_color_v4_, float radius_f_) {
                // dist_f_ > radius_f_ 结果为 0
                // dist_f_ < 0 结果为 1
                // dist_f_ > 0 && dist_f_ < radius_f_ 则 dist_f_ 越大 a_f 越小，范围 0 ~ 1
                float a_f = abs(clamp(dist_f_ / radius_f_, 0.0, 1.0) - 1.0);
                // pow：平滑 a_f
                // max and min：防止在物体内部渲染
                float b_f = min(max(0.0, dist_f_), pow(a_f, 5.0));
                return color_v4_ + input_color_v4_ * b_f;
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


            // 动画 ：融合 
            // k_f 越大, 粘合处越多
            float smooth_merge(float dist_f_, float dist2_f_, float k_f) {
                // k_f 如果不超过 abs(dist_f_ - dist2_f_)，那么 0.5 + 0.5 * (dist2_f_ - dist_f_) / k_f 大于1或小于0， 都是无效值（h_f = 0 或 1）
                // 当 dist2_f_ 与 dist_f_ 差距较小( < k_f )时，属于有效范围， h_f 在 [0, 1]; dist2_f_ 较大, h_f > 0.5, 较小则 h_f < 0.5;
                // 当 dist2_f_ 与 dist_f_ 相等,  h_f = 0.5
                float h_f = clamp(0.5 + 0.5 * (dist2_f_ - dist_f_) / k_f, 0.0, 1.0);
                // 假设 k_f = 0, dist_f_ = 2, dist2_f_ = 1，则 h_f = 0, lerp(...) = dist2_f_, k_f * h_f * (1.0 - h_f) = 0，结果为 dist2_f_
                // 假设 k_f = 0, dist_f_ = 1, dist2_f_ = 2，则 h_f = 1, lerp(...) = dist_f_, k_f * h_f * (1.0 - h_f) = 0，结果为 dist_f_
                // 如果 k_f  为无效值，那么返回结果将 = min(dist_f_, dist2_f_)，和 merge 结果相同
                // 如果 k_f 为有效值，那么将返回比 min(dist_f_, dist2_f_) 还要小的值， k_f  越大，结果越小
                return lerp(dist2_f_, dist_f_, h_f) - k_f * h_f * (1.0 - h_f);
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
                // 将 uv 规范为相同的比例, 以 u 为 1
                float2 scalePos = i.uv;
                scalePos.y = scalePos.y * _yScale / _xScale;

                // == 基础图形 屏幕空间 ==
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

                // == 集合运算 屏幕空间 ==
                // float circle = sdfCircle(pixelPos, float2(0.2, 0.5) * _ScreenParams.xy, 100);
                // float circle2 = sdfCircle(pixelPos, float2(0.5, 0.5) * _ScreenParams.xy, 100);
                // float circle3 = sdfCircle(pixelPos, float2(0.8, 0.5) * _ScreenParams.xy, 100);

                // float box = sdfBox(pixelPos, float2(0.2, 0.5) * _ScreenParams.xy, 120, 70);
                // float box2 = sdfBox(pixelPos, float2(0.5, 0.5) * _ScreenParams.xy, 120, 70);
                // float box3 = sdfBox(pixelPos, float2(0.8, 0.5) * _ScreenParams.xy, 120, 70);

                // float unionResult = sdfUnion(circle, box);
                // float diffResult = sdfDifference(circle2, box2);
                // float intersectResult = sdfIntersection(circle3, box3);

                // float4 unionLayer = render(unionResult, float3(0.91, 0.12, 0.39), fwidth(unionResult) * 2.0);
                // float4 diffLayer = render(diffResult, float3(0.3, 0.69, 0.31), fwidth(diffResult) * 2.0);
                // float4 intersectLayer = render(intersectResult, float3(1, 0.76, 0.03), fwidth(intersectResult) * 2.0);

                // float4 col = lerp(_BackgroundColor, unionLayer, unionLayer.a);
                // col *= lerp(_BackgroundColor, diffLayer, diffLayer.a);
                // col *= lerp(_BackgroundColor, intersectLayer, intersectLayer.a);

                // == 集合运算 ==

                // == 动作：融合 ==
                float circle = sdfCircle(scalePos, float2(0.4 + 0.2 * _SinTime.w , 0.33), 0.1);
                float circle2 = sdfCircle(scalePos, float2(0.6, 0.33), 0.1);
                float unionResult = smooth_merge(circle2 , circle, 0.15);
                float4 unionLayer = render(unionResult, _Color, 0);

                float point1 = sdfCircle(scalePos, float2(0.45, 0.33), 0.002);
                float4 unionLayer2 = render(point1, float3(0.3, 0.69, 0.31), fwidth(point1) * 2.0);

                float4 col = lerp(_BackgroundColor, unionLayer, unionLayer.a);
                col *= lerp(_BackgroundColor, unionLayer2, unionLayer2.a);
                // == 动作：融合 ==
                

                return col;
            }

            ENDCG
        }
    }
}
