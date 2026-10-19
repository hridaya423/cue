#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A soft light band leaning 30° that crosses the wordmark in `travel` seconds, once every `period`.
[[ stitchable ]] half4 wordmarkSweep(float2 p, half4 color, float2 size, float t, float period, float travel) {
    if (t < 0.0) return color;
    float k = fmod(t, period) / travel;
    if (k > 1.0) return color;
    float x = mix(-0.35, 1.35, k) * size.x;
    float d = p.x + (p.y - size.y * 0.5) * 0.58 - x;
    float w = size.x * 0.07;
    float band = exp(-d * d / (2.0 * w * w));
    return half4(mix(color.rgb, half3(color.a), half(band * 0.55)), color.a);
}

// Film grain over the cobalt field: hashed per pixel and re-seeded every frame, ±2.5% luminance.
[[ stitchable ]] half4 cobaltGrain(float2 p, half4 color, float2 size, float t) {
    float n = fract(sin(dot(p + fract(t * 7.0) * 97.0, float2(12.9898, 78.233))) * 43758.5453);
    return half4(color.rgb + half((n - 0.5) * 0.05) * color.a, color.a);
}
