//
//  TextureConversion.metal
//  MetaVisRender
//
//  Texture format conversion kernels for video export
//

#include <metal_stdlib>
using namespace metal;

// Rec.709 RGB to YUV conversion matrix (BT.709)
// CRITICAL: Metal matrices are COLUMN-major! Each half3() is a COLUMN not a row!
// For matrix * vector, we need: [Y_col, Cb_col, Cr_col]
constant half3x3 RGB_to_YUV_709 = half3x3(
    half3( 0.2126h, -0.1146h,  0.5000h),  // Column 0: [Y_r, Cb_r, Cr_r] coefficients for R
    half3( 0.7152h, -0.3854h, -0.4542h),  // Column 1: [Y_g, Cb_g, Cr_g] coefficients for G  
    half3( 0.0722h,  0.5000h, -0.0458h)   // Column 2: [Y_b, Cb_b, Cr_b] coefficients for B
);

// Rec.2020 RGB to YUV conversion matrix (BT.2020)
// Used for HDR content - wider color gamut
constant half3x3 RGB_to_YUV_2020 = half3x3(
    half3( 0.2627h,  0.6780h,  0.0593h),  // Y
    half3(-0.1396h, -0.3604h,  0.5000h),  // U (Cb)
    half3( 0.5000h, -0.4598h, -0.0402h)   // V (Cr)
);

// Rec.709 YUV to RGB conversion matrix (BT.709)
// Inverse of RGB_to_YUV_709
constant half3x3 YUV_to_RGB_709 = half3x3(
    half3(1.0h, 1.0h, 1.0h),        // Column 0: Y coeffs for R, G, B
    half3(0.0h, -0.1873h, 1.8556h), // Column 1: Cb coeffs for R, G, B
    half3(1.5748h, -0.4681h, 0.0h)  // Column 2: Cr coeffs for R, G, B
);

/// Zero-copy conversion from YUV 10-bit (Video Range) to RGBA 16-bit Float (Full Range)
/// Input: CVPixelBuffer Y/UV planes (r16Unorm/rg16Unorm for 10-bit)
/// Output: .rgba16Float
kernel void convert_yuv10_to_rgba16float(
    texture2d<half, access::read> input_y [[texture(0)]],
    texture2d<half, access::read> input_uv [[texture(1)]],
    texture2d<half, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Read Y (full resolution)
    half y = input_y.read(gid).r;
    
    // Read UV (subsampled 4:2:0)
    half2 uv = input_uv.read(gid / 2).rg;
    
    // Convert from Video Range to Full Range
    // Y: [16/255, 235/255] -> [0, 1]
    // UV: [16/255, 240/255] -> [-0.5, 0.5]
    
    const half y_scale = 255.0h / 219.0h;
    const half y_offset = 16.0h / 255.0h;
    const half uv_scale = 255.0h / 224.0h;
    const half uv_center = 128.0h / 255.0h;
    
    half y_full = (y - y_offset) * y_scale;
    half2 uv_full = (uv - uv_center) * uv_scale;
    
    half3 yuv = half3(y_full, uv_full.x, uv_full.y);
    
    // Convert YUV to RGB
    half3 rgb = YUV_to_RGB_709 * yuv;
    
    output.write(half4(rgb, 1.0h), gid);
}

/// Zero-copy conversion for CVPixelBuffer-backed textures (Apple Silicon Media Engine)
/// Writes directly to CVPixelBuffer texture planes - no CPU copies!
/// Input: .rgba16Float (gamma-encoded Rec.709 or Rec.2020, [0,1])
/// Output: CVPixelBuffer Y/UV planes (r16Unorm for 10-bit)
///
/// This is Option A: CVMetalTextureCache zero-copy path
/// Metal GPU → CVPixelBuffer (unified memory) → Media Engine → HEVC Main10
kernel void convert_rgba16float_to_yuv10_zerocopy(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output_y [[texture(1)]],    // CVPixelBuffer Y plane (r16Unorm)
    texture2d<half, access::write> output_uv [[texture(2)]],   // CVPixelBuffer UV plane (rg16Unorm)
    uint2 gid [[thread_position_in_grid]]
) {
    uint2 input_size = uint2(input.get_width(), input.get_height());
    
    // Process 2x2 blocks for 4:2:0 subsampling
    uint2 block_pos = gid * 2;
    
    if (block_pos.x >= input_size.x || block_pos.y >= input_size.y) {
        return;
    }
    
    // Read 2x2 block of RGB pixels
    half4 p00 = input.read(block_pos + uint2(0, 0));
    half4 p10 = input.read(min(block_pos + uint2(1, 0), input_size - 1));
    half4 p01 = input.read(min(block_pos + uint2(0, 1), input_size - 1));
    half4 p11 = input.read(min(block_pos + uint2(1, 1), input_size - 1));
    
    // Clamp to valid range [0,1]
    p00.xyz = clamp(p00.xyz, 0.0h, 1.0h);
    p10.xyz = clamp(p10.xyz, 0.0h, 1.0h);
    p01.xyz = clamp(p01.xyz, 0.0h, 1.0h);
    p11.xyz = clamp(p11.xyz, 0.0h, 1.0h);
    
    // Convert RGB to YUV using Rec.709 (BT.709) for SDR content
    half3 yuv00 = RGB_to_YUV_709 * p00.xyz;
    half3 yuv10 = RGB_to_YUV_709 * p10.xyz;
    half3 yuv01 = RGB_to_YUV_709 * p01.xyz;
    half3 yuv11 = RGB_to_YUV_709 * p11.xyz;
    
    // Convert from full range to video range (BT.709 limited range)
    // Y: [0, 1] → [16/255, 235/255]
    // UV: [-0.5, 0.5] → [16/255, 240/255] centered at 128/255
    const half y_scale = 219.0h/255.0h;      // (235-16)/255 = 0.858824
    const half y_offset = 16.0h/255.0h;      // 16/255 = 0.062745
    const half uv_scale = 224.0h/255.0h;     // (240-16)/255 = 0.878431
    const half uv_center = 128.0h/255.0h;    // 128/255 = 0.501961
    
    // Scale Y from [0,1] to [16/255, 235/255]
    yuv00.x = yuv00.x * y_scale + y_offset;
    yuv10.x = yuv10.x * y_scale + y_offset;
    yuv01.x = yuv01.x * y_scale + y_offset;
    yuv11.x = yuv11.x * y_scale + y_offset;
    
    // Scale UV from [-0.5,0.5] to [16/255, 240/255] centered at 128/255
    // Formula: UV_video = UV_full * scale + center
    yuv00.yz = yuv00.yz * uv_scale + uv_center;
    yuv10.yz = yuv10.yz * uv_scale + uv_center;
    yuv01.yz = yuv01.yz * uv_scale + uv_center;
    yuv11.yz = yuv11.yz * uv_scale + uv_center;
    
    // Clamp to valid video range [16/255, 240/255]
    yuv00 = clamp(yuv00, y_offset, 240.0h/255.0h);
    yuv10 = clamp(yuv10, y_offset, 240.0h/255.0h);
    yuv01 = clamp(yuv01, y_offset, 240.0h/255.0h);
    yuv11 = clamp(yuv11, y_offset, 240.0h/255.0h);
    
    // Write Y plane (full resolution) - normalized values [0,1]
    // VTCompressionSession will handle 10-bit encoding internally
    output_y.write(half4(yuv00.x, 0, 0, 0), block_pos + uint2(0, 0));
    if (block_pos.x + 1 < input_size.x) {
        output_y.write(half4(yuv10.x, 0, 0, 0), block_pos + uint2(1, 0));
    }
    if (block_pos.y + 1 < input_size.y) {
        output_y.write(half4(yuv01.x, 0, 0, 0), block_pos + uint2(0, 1));
    }
    if (block_pos.x + 1 < input_size.x && block_pos.y + 1 < input_size.y) {
        output_y.write(half4(yuv11.x, 0, 0, 0), block_pos + uint2(1, 1));
    }
    
    // Average UV channels for 4:2:0 subsampling
    half2 uv_avg = (yuv00.yz + yuv10.yz + yuv01.yz + yuv11.yz) * 0.25h;
    
    // Write UV plane - standard CbCr order
    output_uv.write(half4(uv_avg.x, uv_avg.y, 0, 0), gid);
}

/// Legacy conversion for CPU-copy path (kept for fallback)
/// Convert RGBA16Float to 10-bit YUV (4:2:0) for HEVC HDR encoding
/// Input: .rgba16Float (gamma-encoded Rec.709 or Rec.2020, [0,1] with HDR >1.0 clamped)
/// Output: Two r16Unorm textures (Y plane + UV plane as rg16Unorm)
/// 
/// This is the proper path for HDR video:
/// 16-bit float render → 10-bit YUV → HEVC Main10 → YouTube HDR / Apple TV
kernel void convert_rgba16float_to_yuv10(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output_y [[texture(1)]],    // Luma plane (r16Unorm)
    texture2d<half, access::write> output_uv [[texture(2)]],   // Chroma plane (rg16Unorm, U+V interleaved)
    uint2 gid [[thread_position_in_grid]]
) {
    uint2 input_size = uint2(input.get_width(), input.get_height());
    
    // Process 2x2 blocks for 4:2:0 subsampling
    uint2 block_pos = gid * 2;
    
    if (block_pos.x >= input_size.x || block_pos.y >= input_size.y) {
        return;
    }
    
    // Read 2x2 block of RGB pixels
    half4 p00 = input.read(block_pos + uint2(0, 0));
    half4 p10 = input.read(min(block_pos + uint2(1, 0), input_size - 1));
    half4 p01 = input.read(min(block_pos + uint2(0, 1), input_size - 1));
    half4 p11 = input.read(min(block_pos + uint2(1, 1), input_size - 1));
    
    // Clamp to valid range (input should already be gamma-encoded [0,1])
    p00.xyz = clamp(p00.xyz, 0.0h, 1.0h);
    p10.xyz = clamp(p10.xyz, 0.0h, 1.0h);
    p01.xyz = clamp(p01.xyz, 0.0h, 1.0h);
    p11.xyz = clamp(p11.xyz, 0.0h, 1.0h);
    
    // Convert RGB to YUV using Rec.2020 for HDR
    // (For SDR, use RGB_to_YUV_709 instead)
    half3 yuv00 = RGB_to_YUV_2020 * p00.xyz;
    half3 yuv10 = RGB_to_YUV_2020 * p10.xyz;
    half3 yuv01 = RGB_to_YUV_2020 * p01.xyz;
    half3 yuv11 = RGB_to_YUV_2020 * p11.xyz;
    
    // Remap from [-0.5, 0.5] to [0, 1] for UV channels
    // Y stays in [0, 1]
    yuv00.yz = yuv00.yz + 0.5h;
    yuv10.yz = yuv10.yz + 0.5h;
    yuv01.yz = yuv01.yz + 0.5h;
    yuv11.yz = yuv11.yz + 0.5h;
    
    // Clamp again after offset
    yuv00 = clamp(yuv00, 0.0h, 1.0h);
    yuv10 = clamp(yuv10, 0.0h, 1.0h);
    yuv01 = clamp(yuv01, 0.0h, 1.0h);
    yuv11 = clamp(yuv11, 0.0h, 1.0h);
    
    // Write Y plane (full resolution) - normalized values [0,1]
    // The .r16Unorm texture will quantize to 10-bit automatically
    output_y.write(half4(yuv00.x, 0, 0, 0), block_pos + uint2(0, 0));
    if (block_pos.x + 1 < input_size.x) {
        output_y.write(half4(yuv10.x, 0, 0, 0), block_pos + uint2(1, 0));
    }
    if (block_pos.y + 1 < input_size.y) {
        output_y.write(half4(yuv01.x, 0, 0, 0), block_pos + uint2(0, 1));
    }
    if (block_pos.x + 1 < input_size.x && block_pos.y + 1 < input_size.y) {
        output_y.write(half4(yuv11.x, 0, 0, 0), block_pos + uint2(1, 1));
    }
    
    // Average UV channels for 4:2:0 subsampling
    half2 uv_avg = (yuv00.yz + yuv10.yz + yuv01.yz + yuv11.yz) * 0.25h;
    
    // Write UV plane (half resolution) - normalized values [0,1]
    // U in red channel, V in green channel
    output_uv.write(half4(uv_avg.x, uv_avg.y, 0, 0), gid);
}

/// DEBUG: Read back Y plane patch to verify 10-bit quantization
/// Samples 16x16 patch from Y plane and writes raw uint16 values to buffer
/// Used to validate P010 packing (values should be multiples of 64)
kernel void debug_readback_y_plane(
    texture2d<half, access::read> input_y [[texture(0)]],
    device uint16_t* output [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Read 16x16 patch from top-left corner
    if (gid.x >= 16 || gid.y >= 16) {
        return;
    }
    
    // Read normalized value from r16Unorm texture
    half value = input_y.read(gid).r;
    
    // Convert back to uint16 storage value
    uint16_t storage = uint16_t(value * 65535.0h + 0.5h);
    
    // Write to buffer
    output[gid.y * 16 + gid.x] = storage;
}

/// Legacy 8-bit conversion for H.264 compatibility
/// Convert RGBA16Float texture to BGRA8Unorm
/// Input: .rgba16Float (half precision, gamma-encoded)
/// Output: .bgra8Unorm (8-bit, ready for CVPixelBuffer)
kernel void convert_rgba16float_to_bgra8(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    // Read 16-bit float color (assumed to be gamma-encoded [0,1])
    half4 color = input.read(gid);
    
    // Clamp to [0,1] for safety
    color = clamp(color, 0.0h, 1.0h);
    
    // Swizzle RGBA -> BGRA and write
    // Metal will handle the float->8bit conversion automatically
    half4 bgra = half4(color.z, color.y, color.x, color.w);
    
    output.write(bgra, gid);
}

/// Blue-noise dithered 8-bit conversion (Option C: eliminates banding)
/// Convert RGBA16Float texture to BGRA8Unorm with blue-noise dithering
/// Input: .rgba16Float (half precision, gamma-encoded)
/// Output: .bgra8Unorm (8-bit, banding-free)
kernel void convert_rgba16float_to_bgra8_dithered(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    texture2d<float, access::sample> blueNoiseTexture [[texture(2)]],
    constant float& ditherStrength [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    // Read 16-bit float color (gamma-encoded [0,1])
    half4 color = input.read(gid);
    
    // Sample blue noise (tile seamlessly using repeat addressing)
    constexpr sampler s(address::repeat, filter::nearest);
    float2 noiseUV = float2(gid) / 64.0;  // 64x64 blue noise tile
    float noise = blueNoiseTexture.sample(s, noiseUV).r;
    
    // Remap noise from [0,1] to [-0.5, 0.5]
    noise = (noise - 0.5) * ditherStrength;
    
    // Add dither BEFORE quantization (in linear/gamma space)
    // One code value (1/255) worth of noise breaks banding
    half3 rgb = color.rgb;
    rgb += half(noise / 255.0);
    
    // Clamp to [0,1] after dithering
    rgb = clamp(rgb, 0.0h, 1.0h);
    
    // Swizzle RGBA -> BGRA and write
    half4 bgra = half4(rgb.z, rgb.y, rgb.x, color.w);
    
    output.write(bgra, gid);
}
