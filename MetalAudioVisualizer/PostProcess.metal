#include <metal_stdlib>
#include "ShaderCommon.h"
using namespace metal;

constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);

/// Share of each bloom level that carries into the next sharper one. Below 1
/// it keeps the glow tight around bright shapes instead of fogging the frame.
constant float kBloomSpread = 0.7;

/// One oversized triangle that covers the whole target, so no vertex buffer is needed.
vertex FullscreenOut fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);

    FullscreenOut out;
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(uv.x, 1.0 - uv.y);
    return out;
}

// MARK: - Bloom

/// Halves the resolution with a wide 13-tap filter. Unlike a plain box filter
/// it does not shimmer when thin bright shapes move between pixels.
fragment float4 downsampleFragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> source [[texture(0)]]) {
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = in.uv;

    float3 center = source.sample(linearSampler, uv).rgb;

    float3 inner = source.sample(linearSampler, uv + texel * float2(-1.0, -1.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 1.0, -1.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2(-1.0,  1.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 1.0,  1.0)).rgb;

    float3 edges = source.sample(linearSampler, uv + texel * float2( 0.0, -2.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2(-2.0,  0.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 2.0,  0.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 0.0,  2.0)).rgb;

    float3 corners = source.sample(linearSampler, uv + texel * float2(-2.0, -2.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2( 2.0, -2.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2(-2.0,  2.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2( 2.0,  2.0)).rgb;

    return float4(center * 0.125 + inner * 0.125 + edges * 0.0625 + corners * 0.03125, 1.0);
}

/// Doubles the resolution with a 3x3 tent filter. Drawn with additive blending,
/// so each level adds its glow on top of the sharper level below it.
fragment float4 upsampleFragment(FullscreenOut in [[stage_in]],
                                 texture2d<float> source [[texture(0)]]) {
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = in.uv;

    float3 center = source.sample(linearSampler, uv).rgb;

    float3 edges = source.sample(linearSampler, uv + texel * float2( 0.0, -1.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2(-1.0,  0.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 1.0,  0.0)).rgb
                 + source.sample(linearSampler, uv + texel * float2( 0.0,  1.0)).rgb;

    float3 corners = source.sample(linearSampler, uv + texel * float2(-1.0, -1.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2( 1.0, -1.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2(-1.0,  1.0)).rgb
                   + source.sample(linearSampler, uv + texel * float2( 1.0,  1.0)).rgb;

    return float4((center * 4.0 + edges * 2.0 + corners) / 16.0 * kBloomSpread, 1.0);
}

// MARK: - Composite

/// Matches `CompositeUniforms` in `Renderer.swift`.
struct CompositeUniforms {
    float bloomIntensity;
    float time;
};

/// ACES filmic curve (Narkowicz fit): rolls bright colors off toward white.
static float3 toneMap(float3 color) {
    return saturate((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14));
}

static float3 linearToSRGB(float3 color) {
    float3 low = color * 12.92;
    float3 high = 1.055 * pow(color, float3(1.0 / 2.4)) - 0.055;
    return select(high, low, color <= 0.0031308);
}

/// Adds the bloom to the scene and converts the HDR result for the display.
fragment float4 compositeFragment(FullscreenOut in [[stage_in]],
                                  texture2d<float> scene [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]],
                                  constant CompositeUniforms &u [[buffer(0)]]) {
    float3 color = scene.sample(linearSampler, in.uv).rgb;
    color += bloom.sample(linearSampler, in.uv).rgb * u.bloomIntensity;

    // Vignette: darken toward the corners to keep the eye on the center.
    float2 centered = in.uv - 0.5;
    color *= 1.0 - 0.9 * dot(centered, centered);

    color = linearToSRGB(toneMap(color));

    // Film grain. It also dithers the 8-bit output, which hides banding in the dark gradients.
    float2 seed = in.position.xy + fract(u.time) * 100.0;
    float grain = hash(seed) + hash(seed + 17.0) - 1.0;
    color += grain * (1.5 / 255.0);

    return float4(color, 1.0);
}
