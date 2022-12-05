Shader "Unlit/sdf"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("_Color", Color) = (0.5,1,0.5,1)
        _BackgroundColor ("_BackgroundColor", Color) = (1,1,1,1)
        _StrokeColor ("_StrokeColor", Color) = (0.5,0.5,0.5,1)
        _ShadowColor ("_ShadowColor", Color) = (0.1,0.1,0.1,1)
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

            #define max_shadow_step 9999

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
            fixed4 _StrokeColor;
            fixed4 _BackgroundColor;
            fixed4 _ShadowColor;
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
                float4 strokeLayer = float4(_StrokeColor.xyz, 1.0 - smoothstep(-anti, anti, d - stroke));
                // 往右边平移多出来的图形部分涂上 strokeLayer
                return float4(lerp(strokeLayer.rgb, colorLayer.rgb, colorLayer.a), strokeLayer.a);
            }

            // 渲染函数（外发光）； color：内部颜色；outer_color：外发光颜色；radius_f_：外发光半径
            float4 outerGlow(float dist_f_, float3 color, float3 outer_color, float radius_f_) {
                // dist_f_ > radius_f_ 结果为 0
                // dist_f_ < 0 结果为 1
                // dist_f_ > 0 && dist_f_ < radius_f_ 则 dist_f_ 越大 a_f 越小，范围 0 ~ 1
                float a_f = abs(clamp(dist_f_ / radius_f_, 0.0, 1.0) - 1.0);

                float anti = fwidth(dist_f_) * 1.0;
                float4 colorLayer = float4(color, 1.0 - smoothstep(-anti, anti, dist_f_));
                float4 outerLayer = float4(outer_color, pow(a_f, 3.0));
                return float4(lerp(outerLayer.rgb, colorLayer.rgb, colorLayer.a), min(outerLayer.a + colorLayer.a, 1.0));
            }

            // 圆形 
            float sdfCircle(float2 coord, float2 center, float radius)
            {
                float2 offset = coord - center;
                return sqrt((offset.x * offset.x) + (offset.y * offset.y)) - radius;
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

            // 变换
            // 平移
            float2 translate(float2 render_v2_, float2 move_v2_) {
                return render_v2_ - move_v2_;
            }
            // 逆时针旋转 center_v2_ 旋转中心 radian_f_ 旋转角
            float2 rotate_ccw(float2 render_v2_, float2 center_v2_, float radian_f_) {
                float2x2 m = float2x2(cos(radian_f_), sin(radian_f_), -sin(radian_f_), cos(radian_f_));
                return mul(m, render_v2_ - center_v2_) + center_v2_;
            }
            // 顺时针旋转
            float2 rotate_cw(float2 render_v2_, float2 center_v2_, float radian_f_) {
                float2x2 m = float2x2(cos(radian_f_), -sin(radian_f_), sin(radian_f_), cos(radian_f_));
                return mul(m, render_v2_ - center_v2_) + center_v2_;	
            }

            // 场景（查询sdf的值）
            float scene_dist(float2 scalePos){
                float2 circlePos = scalePos;
                circlePos = translate(circlePos, float2(0, 0.06 * _SinTime.z));
                float circle = sdfCircle(circlePos, float2(0.8, 0.43), 0.02);

                float2 boxPos = scalePos;
                boxPos = translate(boxPos, float2(0.2 * _SinTime.w, 0));
                boxPos = rotate_cw(boxPos, float2(0.6, 0.18), _Time.z);
                float box = sdfBox(boxPos, float2(0.6, 0.18), 0.05, 0.05);
                
                float circle1 = sdfCircle(scalePos, float2(0.5 + abs(0.1 * _CosTime.y), 0.48), 0.05);
                float circle2 = sdfCircle(scalePos, float2(0.5 - abs(0.1 * _CosTime.y), 0.48), 0.05);
                float smoothResult = smooth_merge(circle1 , circle2, 0.09);

                float2 boxPos2 = scalePos;
                boxPos2 = rotate_ccw(boxPos2, float2(0.8, 0.2), _Time.w);
                float box2 = sdfBox(boxPos2, float2(0.8, 0.2), 0.1, 0.02);

                float unionResult = sdfUnion(circle, box);
                unionResult = sdfUnion(unionResult, box2);
                unionResult = sdfUnion(unionResult, smoothResult);
                return unionResult;
            }
            
            // 硬阴影
            float hard_shadow(float2 render_v2_, float2 light_v2_) {
                // 当前渲染位置到光源位置的方向向量
                float2 render_to_light_dir_v2 = normalize(light_v2_ - render_v2_);
                // 渲染位置至光源位置距离
                float render_to_light_dist_f = length(render_v2_ - light_v2_);
                // 行走距离
                float travel_dist_f = 0.001;

                for (int k_i = 0; k_i < max_shadow_step; ++k_i) {
                    // 渲染点到场景的距离
                    float dist_f = scene_dist(render_v2_ + render_to_light_dir_v2 * travel_dist_f);
                    // 小于0表示在物体内部
                    if (dist_f < 0.0) {
                        return 0.0;
                    }
                    // abs：避免往回走
                    // max 避免渲染点距离物理表面过近导致极小耗尽遍历次数，所以有可能会跳过物体距离小于 极限值 的阴影绘制
                    // 极限值 影响阴影精度
                    travel_dist_f += max(0.001, abs(dist_f));
                    // travel_dist_f += abs(dist_f); 精确的阴影

                    // 渲染点的距离超过光源点
                    if (travel_dist_f > render_to_light_dist_f) {
                        return 1.0;
                    }
                }
                return 0.0;
            }

            // 软阴影
            float soft_shadow(float2 render_v2_, float2 light_v2_, float hard_f_) {
                // 当前渲染位置到光源位置的方向向量
                float2 render_to_light_dir_v2 = normalize(light_v2_ - render_v2_);
                // 渲染位置至光源位置距离
                float render_to_light_dist_f = length(render_v2_ - light_v2_);
                // 可见光的一部分，从一个半径开始（最后添加下半部分）；
                float brightness_f = hard_f_ * render_to_light_dist_f;
                // 行走距离
                float travel_dist_f = 0.0001;

                for (int k_i = 0; k_i < max_shadow_step; ++k_i) {
                    // 当前位置到场景的距离
                    float dist_f = scene_dist(render_v2_ + render_to_light_dir_v2 * travel_dist_f);

                    // 渲染点在物体内部
                    if (dist_f < -hard_f_) {
                        return 0.0;
                    }

                    // dist_f 不变，brightness_f 越小，在越靠近光源和物体时 brightness_f 越小
                    brightness_f = min(brightness_f, dist_f / travel_dist_f);

                    // max 避免渲染点距离物理表面过近导致极小耗尽遍历次数，所以有可能会跳过物体距离小于1.0的阴影绘制
                    // abs 避免朝回走
                    travel_dist_f += max(0.0001, abs(dist_f));

                    // 渲染点的距离超过光源点
                    if (travel_dist_f > render_to_light_dist_f) {
                        break;
                    }
                }

                // brightness_f * render_to_light_dist_f 根据距离平滑, 离光源越近越小，消除波纹线
                // 放大阴影，hard_f 越大结果越小则阴影越大, hard_f_ / (2.0 * hard_f_) 使结果趋近于0.5，用于平滑过渡
                brightness_f = clamp((brightness_f * render_to_light_dist_f + hard_f_) / (2.0 * hard_f_), 0.0, 1.0);
                // brightness_f = clamp((brightness_f + hard_f_) / (2.0 * hard_f_), 0.0, 1.0);
                brightness_f = smoothstep(0.0, 1.0, brightness_f);
                return brightness_f;
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
                // 将 uv 规范为相同的比例, 以 u 为 1
                float2 scalePos = i.uv;
                scalePos.y = scalePos.y * _yScale / _xScale;

                // 光源位置
                float2 lightPos = float2(0.5 - 0.05 * _SinTime.w, 0.33);
                float lightCircle = sdfCircle(scalePos, lightPos, 0.02);
                float4 lightLayer = outerGlow(lightCircle, float3(0.99, 0.8, 0.3), float3(0.99, 0.79, 0.19), 0.8);
                
                // 场景
                float unionResult = scene_dist(scalePos);
                float4 unionLayer = render(unionResult, _Color, fwidth(unionResult) * 0.5);

                // 阴影
                // float shadowValue = 1.0 - hard_shadow(scalePos, lightPos);
                float shadowValue = 1.0 - soft_shadow(scalePos, lightPos, 0.02);

                float4 col = lerp(_BackgroundColor, lightLayer, lightLayer.a);
                col = lerp(col, _ShadowColor, shadowValue);
                col = lerp(col, unionLayer, unionLayer.a);
                
                return col;
            }

            ENDCG
        }
    }
}
