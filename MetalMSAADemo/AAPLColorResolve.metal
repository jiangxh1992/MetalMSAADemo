/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders to cull lights for each tile.
*/

#include <metal_stdlib>
using namespace metal;

// Include header shared between C code and .metal files.
//#import "ShaderTypes.h"
typedef struct
{
    half4 lighting [[color(0)]];
} ColorData;
kernel void my_resolve(imageblock<ColorData, imageblock_layout_implicit> imageBlock,
                       ushort2 tid [[thread_position_in_threadgroup]])
{
  ColorData result = {};
  for (ushort c = 0; c < imageBlock.get_num_colors(tid); ++c)
  {
      const ColorData ibData = imageBlock.read(tid, c, imageblock_data_rate::color);
      ushort colorMask = imageBlock.get_color_coverage_mask(tid, c);
      result.lighting += ibData.lighting * popcount(colorMask);
  }
  result.lighting /= 4;
    
  ushort output_sample_mask = 0xF;
  imageBlock.write(result, tid, output_sample_mask); // Write one value to all samples
}
