#include <metal_stdlib>
using namespace metal;

struct WatermarkUniforms {
    float opacity;
    uint stripeWidth;
    uint stripeSpacing;
};

kernel void watermark_diagonal_stripes(
    texture2d<half, access::read_write> image [[texture(0)]],
    constant WatermarkUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    const uint w = image.get_width();
    const uint h = image.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    const float op = clamp(u.opacity, 0.0f, 1.0f);
    const uint spacing = max(u.stripeSpacing, 1u);
    const uint widthPx = min(u.stripeWidth, spacing);

    const uint d = gid.x + gid.y;
    const bool inStripe = (d % spacing) < widthPx;

    half4 px = image.read(gid);
    if (inStripe) {
        // Darken stripes in linear space without clamping highlights.
        const float strength = 0.35f;
        const float factor = 1.0f - (op * strength);
        px.rgb = px.rgb * half(factor);
    }
    image.write(px, gid);
}
