Shader "Custom/ToonShader"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}

        _OutlineWidth("Outline Width", Range(0.01, 1)) = 0.01
        _OutLineColor("OutLine Color", Color) = (0.5,0.5,0.5,1)

            //������ʼ
        _RampStart("RampStart", Range(0.1, 1)) = 0.3
            //�����С
        _RampSize("RampSize", Range(0, 1)) = 0.1
            //�������
        [IntRange]
        _RampStep("RampStep", Range(1,10)) = 1
            //������Ͷ�
        _RampSmooth("RampSmooth", Range(0.01, 1)) = 0.1
            //����
        _DarkColor("DarkColor", Color) = (0.4, 0.4, 0.4, 1)
            //����
        _LightColor("LightColor", Color) = (0.8, 0.8, 0.8, 1)

            //�����
        _SpecPow("SpecPow", Range(0, 1)) = 0.1
            //�߹�
        _SpecularColor("SpecularColor", Color) = (1.0, 1.0, 1.0, 1)
            //�߹�ǿ��
        _SpecIntensity("SpecIntensity", Range(0, 1)) = 0
            //�߹���Ͷ�
        _SpecSmooth("SpecSmooth", Range(0, 0.5)) = 0.1

            //��Ե��
        _RimColor("RimColor", Color) = (1.0, 1.0, 1.0, 1)
            //��Ե����ֵ
        _RimThreshold("RimThreshold", Range(0, 1)) = 0.45
            //��Ե����Ͷ�
        _RimSmooth("RimSmooth", Range(0, 0.5)) = 0.1
    }
        SubShader
        {
            Tags { "RenderType" = "Opaque" }
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
                    float3 normal: NORMAL;  // ���������Ҫ�õ�ģ�ͷ���
                };

                struct v2f
                {
                    float2 uv : TEXCOORD0;
                    float4 vertex : SV_POSITION;
                    // ���������Ҫ�õ����ߺ�����λ��
                    float3 worldNormal: TEXCOORD1;
                    float3 worldPos:TEXCOORD2;
                };

                sampler2D _MainTex;
                float4 _MainTex_ST;
                float _RampStart;
                float _RampSize;
                float _RampStep;
                float _RampSmooth;
                float3 _DarkColor;
                float3 _LightColor;

                float _SpecPow;
                float3 _SpecularColor;
                float _SpecIntensity;
                float _SpecSmooth;

                float3 _RimColor;
                float _RimThreshold;
                float _RimSmooth;

                float linearstep(float min, float max, float t)
                {
                    return saturate((t - min) / (max - min));
                }

                v2f vert(appdata v)
                {
                    v2f o;
                    o.vertex = UnityObjectToClipPos(v.vertex);
                    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                    // ���´�����Щ����
                    o.worldNormal = normalize(UnityObjectToWorldNormal(v.normal));
                    o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                    return o;
                }

                fixed4 frag(v2f i) : SV_Target
                {
                    // sample the texture
                    fixed4 col = tex2D(_MainTex, i.uv);

                //------------------------ ������ ------------------------
                // �õ����㷨��
                float3 normal = normalize(i.worldNormal);
                // �õ����շ���
                float3 worldLightDir = UnityWorldSpaceLightDir(i.worldPos);
                // NoL���������ܵ�������С
                float NoL = dot(i.worldNormal, worldLightDir);
                // ����half-lambert����ֵ
                float halfLambert = NoL * 0.5 + 0.5;

                //------------------------ �߹� ------------------------
                // �õ�������
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
                // ����half����, ʹ��Blinn-phone����߹�
                float3 halfDir = normalize(viewDir + worldLightDir);
                // ����NoH���ڼ���߹�
                float NoH = dot(normal, halfDir);
                // ����߹�����ֵ
                float blinnPhone = pow(max(0, NoH), _SpecPow * 128.0);
                // ����߹�ɫ��
                float3 specularColor = smoothstep(0.7 - _SpecSmooth / 2, 0.7 + _SpecSmooth / 2, blinnPhone)
                                        * _SpecularColor * _SpecIntensity;

                //------------------------ ��Ե�� ------------------------
                // ����NoV���ڼ����Ե��
                float NoV = dot(i.worldNormal, viewDir);
                // �����Ե������ֵ
                float rim = (1 - max(0, NoV)) * NoL;
                // �����Ե����ɫ
                float3 rimColor = smoothstep(_RimThreshold - _RimSmooth / 2, _RimThreshold + _RimSmooth / 2, rim) * _RimColor;

                //------------------------ ɫ�� ------------------------
                // ͨ������ֵ��������ramp
                float ramp = linearstep(_RampStart, _RampStart + _RampSize, halfLambert);
                float step = ramp * _RampStep;  // ʹÿ��ɫ�״�СΪ1, �������
                float gridStep = floor(step);   // �õ���ǰ������ɫ��
                float smoothStep = smoothstep(gridStep, gridStep + _RampSmooth, step) + gridStep;
                ramp = smoothStep / _RampStep;  // �ص�ԭ���Ŀռ�
                // �õ����յ�rampɫ��
                float3 rampColor = lerp(_DarkColor, _LightColor, ramp);
                rampColor *= col;

                // �����ɫ
                float3 finalColor = saturate(rampColor + specularColor + rimColor);
                return float4(finalColor,1);
            }
            ENDCG
        }

        Pass
        {
            Cull Front
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                // ����
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            // �������
            float _OutlineWidth;
            // ������ɫ
            float4 _OutLineColor;

            v2f vert(appdata v)
            {
                v2f o;
                float4 newVertex = float4(v.vertex.xyz + normalize(v.normal) * _OutlineWidth * 0.05,1);
                o.vertex = UnityObjectToClipPos(newVertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                return _OutLineColor;
            }
            ENDCG
        }
        }
            fallback"Diffuse"
}