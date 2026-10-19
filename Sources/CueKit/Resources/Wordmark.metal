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
