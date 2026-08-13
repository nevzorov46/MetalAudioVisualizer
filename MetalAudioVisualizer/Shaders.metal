#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;
    float rayT;
    float isDisk;
    
};

struct Uniforms {
    float time;
    float bass;
    float drums;
    float vocals;
    float other;
    float aspectRatio;
    float spikeCount;
};

vertex VertexOut vertexShader(const constant float2 *vertexArray [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]],
                              constant int &mode [[buffer(2)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    float2 v = vertexArray[vid];
    out.localPos = v;
    
    float overall = (u.bass + u.drums + u.vocals + u.other) / 4.0;
    float diskScale = 0.25 + overall * 0.04;
    
    if (mode == 0) {
        out.position = float4(v.x * diskScale, v.y * diskScale / u.aspectRatio, 0, 1);
        float3 magentaTop = float3(0.02, 0.02, 0.025);
        float3 maroonBottom = float3(0.05, 0.05, 0.055);
        
        float gradientMix = (v.y + 1.0) * 0.5;
        float3 diskColor = mix(maroonBottom, magentaTop, gradientMix);
        
        out.color = float4(diskColor, 1.0);
        out.isDisk = 1.0;
    } else {
        int spikeIndex = int(vid) / 4;
        bool isOuter = (vid % 4 >= 2);
        out.rayT = isOuter ? 1.0 : 0.0;
        out.isDisk = 0.0;
        int numSpikes = int(u.spikeCount);
        int sector = (spikeIndex * 4) / numSpikes; // 0..3
        
        float level = 0.0;
        float3 color = float3(1.0);
        if (sector == 0) { level = u.bass;   color = float3(0.15, 0.25, 0.55); }  // blue
        if (sector == 1) { level = u.drums;  color = float3(0.85, 0.75, 0.55); }  // yellow
        if (sector == 2) { level = u.vocals; color = float3(0.55, 0.1, 0.25); }   // red
        if (sector == 3) { level = u.other;  color = float3(0.08, 0.35, 0.28); }  // green
        
        // Rotation
        float rotation = u.time * 0.1;
        float2 rotated = float2(
                                v.x * cos(rotation) - v.y * sin(rotation),
                                v.x * sin(rotation) + v.y * cos(rotation)
                                );
        
        float innerRadius = diskScale;
        float spikeLength = level * 1.3;
        float scale = isOuter ? (innerRadius + spikeLength) : innerRadius;
        out.position = float4(rotated.x * scale, rotated.y * scale / u.aspectRatio, 0, 1);
        out.color = float4(color, 1.0);
    }
    
    return out;
}

fragment float4 fragmentShader(
                               VertexOut in [[stage_in]],
                               constant Uniforms& u [[buffer(0)]]
                               )
{
    float3 color = in.color.rgb;
    
    float overall =
    (u.bass + u.drums + u.vocals + u.other) * 0.25;
    
    float dist = length(in.localPos);
    
    float core = smoothstep(0.65, 0.0, dist);
    
    float glowStrength = min(overall, 0.6);
    color += core * glowStrength * float3(0.55, 0.55, 0.6) * 0.15;
    
    
    if (in.isDisk > 0.5) {
        float edgeWidth = 0.03;
        float ring = smoothstep(1.0, 1.0 - edgeWidth, dist) - smoothstep(1.0 - edgeWidth, 1.0 - edgeWidth * 2.0, dist);
        color += ring * float3(0.15, 0.015, 0.04);
    }
    
    float fade = exp(-in.rayT * 2.5);
    
    color *= fade;
    
    return float4(color, fade);
}
