//
//  ZeroCopy.metal
//  MetaVisExport
//
//  Texture format conversion kernels for video export
//  Based on TextureConversion.metal from legacy docs
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
