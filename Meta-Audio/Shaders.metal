#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float time;
    float bass;
    float drums;
    float vocals;
    float other;
};

vertex VertexOut vertexShader(const constant float2 *vertexArray [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]],
                              constant int &mode [[buffer(2)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    float2 v = vertexArray[vid];
    
    float overall = (u.bass + u.drums + u.vocals + u.other) / 4.0;
    float diskScale = 0.3 + overall * 0.06;   // маленький — только для диска
//    float spikeBaseScale = 0.35 + overall * 0.15; // прежний размер — для шипов
    
    if (mode == 0) {
        // Заполненный диск — просто масштабируется целиком
        out.position = float4(v.x * diskScale, v.y * diskScale / 2.16, 0, 1);
        
        float3 magentaTop = float3(0.16, 0.17, 0.19);
        float3 maroonBottom = float3(0.02, 0.02, 0.03);
        
        float gradientMix = (v.y + 1.0) * 0.5; // v.y от -1..1 → 0..1
        float3 diskColor = mix(maroonBottom, magentaTop, gradientMix);
        diskColor = clamp(diskColor + overall * float3(0.08, 0.025, 0.25), float3(0.0), float3(1.0));
        
        out.color = float4(diskColor, 1.0);
    } else {
        // Шипы: определяем сектор по индексу вершины
        int spikeIndex = int(vid) / 4;
        bool isOuter = (vid % 4 >= 2);  // первые 2 — inner, последние 2 — outer
        
        int numSpikes = 120;
        int sector = (spikeIndex * 4) / numSpikes; // 0..3
        
        float level = 0.0;
        float3 color = float3(1.0);
        if (sector == 0) { level = u.bass;   color = float3(0.25, 0.35, 0.95); }  // сине-фиолетовый
        if (sector == 1) { level = u.drums;  color = float3(1.0, 0.98, 0.85); } // янтарный
        if (sector == 2) { level = u.vocals; color = float3(1.0, 0.2, 0.45); }   // малиновый
        if (sector == 3) { level = u.other;  color = float3(0.15, 0.9, 0.6); }   // бирюзово-зелёный
        
        // Лёгкое вращение всего круга со временем — наш собственный штрих
        float rotation = u.time * 0.1;
        float2 rotated = float2(
                                v.x * cos(rotation) - v.y * sin(rotation),
                                v.x * sin(rotation) + v.y * cos(rotation)
                                );
        
        float innerRadius = diskScale; // шип стартует ровно с края диска
        float spikeLength = level * 1.5; // насколько далеко шип "выстреливает" — подбери множитель под вкус
        float scale = isOuter ? (innerRadius + spikeLength) : innerRadius;
        out.position = float4(rotated.x * scale, rotated.y * scale / 2.16, 0, 1);
        out.color = float4(color, isOuter ? 1.0 : 1.0);
    }
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
}
