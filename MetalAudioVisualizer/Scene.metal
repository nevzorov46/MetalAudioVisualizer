#include <metal_stdlib>
#include "ShaderCommon.h"
using namespace metal;

/// Matches `SceneUniforms` in `Renderer.swift` — keep the field order in sync.
struct SceneUniforms {
    float2 resolution;  // target size in pixels
    float time;         // seconds since launch
    float bandCount;    // bands per stem
    float4 levels;      // average level of each stem
    float4 beatAges;    // seconds since each of the last four drum hits
    float flow;         // distance the background dust has drifted
};

// MARK: - Look

constant int kStemCount = 4;

// Linear-light stem colors, in stacking order from the core outward
// (see `AudioAnalyzer.Stem`): other, bass, vocals, drums.
constant float3 kStemColors[kStemCount] = {
    float3(0.00, 0.72, 0.55),
    float3(0.05, 0.12, 1.00),
    float3(1.00, 0.02, 0.22),
    float3(1.00, 0.30, 0.02),
};

constant float kCoreRadius = 0.25;
constant float kCorePulse = 0.35;       // how much the core swells with loudness
constant float kRingGap = 0.035;        // space between the core and the rays

constant float kRayScale = 0.46;        // ray length for a full-scale band
constant float kRayHalfWidth = 0.004;
constant float kRayBlend = 0.012;       // softness of the seam between two stems
constant float kRayBaseGlow = 1.5;      // HDR brightness at the base of a ray...
constant float kRayTipGlow = 0.9;       // ...and at its tip

constant float kPearlRadius = 0.005;    // dot floating past the end of each ray
constant float kPearlGap = 0.014;
constant float3 kPearlColor = float3(0.9, 0.95, 1.0);

constant float kWaveSpeed = 0.85;
constant float kWaveWidth = 0.004;
constant float kWaveDecay = 3.6;
constant float kWaveGlow = 0.3;

constant float3 kBackgroundInner = float3(0.005, 0.006, 0.014);
constant float3 kBackgroundOuter = float3(0.001, 0.001, 0.003);
constant float3 kCoreColor = float3(0.004, 0.004, 0.008);

constant int kDustLayers = 3;
constant float3 kDustColor = float3(0.30, 0.36, 0.55);

// MARK: - Layers

/// Deep gradient with a faint haze in the color of whatever is playing.
static float3 background(float radius, float3 mood, float energy) {
    float3 base = mix(kBackgroundInner, kBackgroundOuter, smoothstep(0.0, 1.8, radius));
    return base + mood * energy * 0.08 * exp(-radius * 2.2);
}

/// Sparse specks drifting outward from the core, for a sense of depth.
/// Each layer splits the circle into lanes with one speck travelling along each.
static float3 dust(float2 p, float pixel, float flow, float time) {
    float turn = atan2(p.y, p.x) / (2.0 * M_PI_F) + 0.5;
    float3 result = float3(0.0);

    for (int layer = 0; layer < kDustLayers; layer++) {
        float lanes = 23.0 + 17.0 * float(layer);
        float lane = floor(turn * lanes);
        float seed = hash(float2(lane, 7.3 * float(layer)));

        float travel = fract(seed * 13.7 + flow * mix(0.4, 1.0, hash(float2(seed, 3.1))));
        float speckAngle = ((lane + mix(0.2, 0.8, hash(float2(seed, 9.7)))) / lanes - 0.5) * 2.0 * M_PI_F;
        float2 center = mix(0.3, 2.4, travel) * float2(cos(speckAngle), sin(speckAngle));

        float size = pixel * mix(0.8, 1.8, hash(float2(seed, 5.5)));
        float speck = 1.0 - smoothstep(size * 0.5, size * 1.5, length(p - center));
        float fade = smoothstep(0.0, 0.15, travel) * (1.0 - smoothstep(0.6, 1.0, travel));
        float twinkle = 0.6 + 0.4 * sin(time * (1.0 + 3.0 * seed) + seed * 40.0);
        result += kDustColor * speck * fade * twinkle;
    }
    return result;
}

/// Thin rings that burst out of the core on every drum hit.
static float3 shockwaves(float radius, float coreRadius, float4 ages, float3 tint) {
    float3 result = float3(0.0);
    for (int wave = 0; wave < 4; wave++) {
        float age = ages[wave];
        float waveRadius = coreRadius + age * kWaveSpeed;
        float width = kWaveWidth * (1.0 + age * 4.0);
        float falloff = (radius - waveRadius) / width;
        result += tint * kWaveGlow * exp(-falloff * falloff) * exp(-age * kWaveDecay);
    }
    return result;
}

/// The spectrum ring. Every ray is one frequency band; the four stems are
/// stacked end to end along it, so a ray's colors show the mix at that pitch.
static float3 rays(float2 p, float radius, float innerRadius, float pixel,
                   float bandCount, constant float *spectrum) {
    // Mirrored left/right: low frequencies at the bottom, highs at the top.
    float angle = abs(atan2(p.x, -p.y));
    float cell = M_PI_F / bandCount;
    float band = min(floor(angle / cell), bandCount - 1.0);
    float offset = angle - (band + 0.5) * cell;
    float2 local = radius * float2(sin(offset), cos(offset));  // x across the ray, y along it

    float ends[kStemCount];
    float total = 0.0;
    for (int stem = 0; stem < kStemCount; stem++) {
        total += spectrum[stem * int(bandCount) + int(band)] * kRayScale;
        ends[stem] = total;
    }

    // Capsule from the inner radius to the tip.
    float tip = innerRadius + total;
    float nearest = clamp(local.y, innerRadius, tip);
    float distance = length(float2(local.x, local.y - nearest));
    float body = 1.0 - smoothstep(kRayHalfWidth - pixel, kRayHalfWidth + pixel, distance);

    float along = local.y - innerRadius;
    float3 tint = float3(0.0);
    float start = 0.0;
    for (int stem = 0; stem < kStemCount; stem++) {
        float weight = saturate((along - start) / kRayBlend + 0.5)
                     - saturate((along - ends[stem]) / kRayBlend + 0.5);
        tint += kStemColors[stem] * weight;
        start = ends[stem];
    }
    float glow = mix(kRayBaseGlow, kRayTipGlow, saturate(along / max(total, 0.001)));

    float2 pearlCenter = float2(0.0, tip + kPearlGap);
    float pearl = 1.0 - smoothstep(kPearlRadius - pixel, kPearlRadius + pixel,
                                   length(local - pearlCenter));

    return tint * glow * body + kPearlColor * pearl;
}

/// The core: a dark glass sphere whose rim picks up the color of the mix.
static float3 core(float3 behind, float2 p, float radius, float coreRadius, float pixel,
                   float3 mood, float energy, float bass) {
    float2 q = p / coreRadius;
    float height = sqrt(saturate(1.0 - dot(q, q)));
    float3 normal = float3(q, height);

    float rim = pow(1.0 - height, 2.5);
    float highlight = pow(saturate(dot(normal, normalize(float3(-0.45, 0.65, 0.6)))), 24.0);

    float3 glass = kCoreColor * (0.35 + 0.65 * height);
    glass += mood * rim * (0.08 + energy * 1.2);
    glass += float3(0.03) * highlight;
    glass += kStemColors[1] * bass * 0.12 * exp(-dot(q, q) * 4.0);

    float mask = 1.0 - smoothstep(-pixel, pixel, radius - coreRadius);
    float3 color = mix(behind, glass, mask);

    float edge = (radius - coreRadius) / (pixel * 1.5);
    return color + mood * exp(-edge * edge) * (0.5 + energy * 3.0);
}

// MARK: - Scene

fragment float4 sceneFragment(FullscreenOut in [[stage_in]],
                              constant SceneUniforms &u [[buffer(0)]],
                              constant float *spectrum [[buffer(1)]]) {
    // Aspect-correct space: the short side of the screen spans -1...1, +y is up.
    float shortSide = min(u.resolution.x, u.resolution.y);
    float2 p = (in.uv * 2.0 - 1.0) * u.resolution / shortSide;
    p.y = -p.y;
    float pixel = 2.0 / shortSide;
    float radius = length(p);

    // How loud the mix is, and the blended color of the stems that are playing.
    float energy = dot(u.levels, float4(0.25));
    float3 mood = float3(0.0);
    for (int stem = 0; stem < kStemCount; stem++) {
        mood += kStemColors[stem] * u.levels[stem];
    }
    mood = mix(float3(0.25, 0.3, 0.45), mood / max(energy * 4.0, 0.001), saturate(energy * 12.0));

    float coreRadius = kCoreRadius * (1.0 + kCorePulse * energy);
    float innerRadius = coreRadius + kRingGap;

    float3 color = background(radius, mood, energy);
    color += dust(p, pixel, u.flow, u.time);
    color += shockwaves(radius, coreRadius, u.beatAges, mix(mood, float3(1.0), 0.5));
    color += rays(p, radius, innerRadius, pixel, u.bandCount, spectrum);
    color = core(color, p, radius, coreRadius, pixel, mood, energy, u.levels[1]);

    return float4(color, 1.0);
}
