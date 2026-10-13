#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <metal_stdlib>

/// Output of `fullscreenVertex`, the input of every fragment shader in the app.
struct FullscreenOut {
    metal::float4 position [[position]];
    /// 0...1 across the target, origin in the top-left corner.
    metal::float2 uv;
};

/// Cheap repeatable pseudo-random value in 0...1 for a 2D seed.
static inline float hash(metal::float2 seed) {
    return metal::fract(metal::sin(metal::dot(seed, metal::float2(12.9898, 78.233))) * 43758.5453);
}

#endif
