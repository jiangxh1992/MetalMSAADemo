//
//  Renderer.m
//  MetalGameDemo
//
//  Created by Xinhou Jiang on 2020/2/9.
//  Copyright © 2020 Xinhou Jiang. All rights reserved.
//

#import <simd/simd.h>
#import "Renderer.h"
// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "ShaderTypes.h"

@implementation Renderer
{
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    id <MTLRenderPipelineState> _pipelineState;
    id <MTLRenderPipelineState> _myResolvePipelineState;
    id <MTLDepthStencilState> _depthState;
    
    id<MTLBuffer> vertexBuffer;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        [self _loadMetalWithView:view];
        [self _loadAssets];
    }

    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *)view;
{
    /// Load Metal state objects and initalize renderer dependent view properties
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 4;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;

    NSError *error = NULL;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    
    // MSAA resolve
    {
        NSError *error;
        
        id <MTLFunction> customResolveKernel = [defaultLibrary newFunctionWithName:@"my_resolve"];
        
        MTLTileRenderPipelineDescriptor *myResolvePipelineDescriptor = [MTLTileRenderPipelineDescriptor new];
        myResolvePipelineDescriptor.label = @"My Resolve";
        myResolvePipelineDescriptor.rasterSampleCount = view.sampleCount;
        myResolvePipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
        myResolvePipelineDescriptor.threadgroupSizeMatchesTileSize = YES;
        myResolvePipelineDescriptor.tileFunction = customResolveKernel;
        _myResolvePipelineState = [_device newRenderPipelineStateWithTileDescriptor:myResolvePipelineDescriptor
                                                                                   options:0 reflection:nil error:&error];
        
        NSAssert(_myResolvePipelineState, @"Failed to create pipeline state: %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    _commandQueue = [_device newCommandQueue];
}

- (void)_loadAssets
{
    /// Load assets into metal objects
    static const Vertex vert[] = {
        {{0,1.0}},
        {{1.0,-1.0}},
        {{-1.0,-1.0}}
    };
    vertexBuffer = [_device newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    renderPassDescriptor.tileWidth = 16;
    renderPassDescriptor.tileHeight = 16;
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        [renderEncoder pushDebugGroup:@"Draw"];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];
        [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [renderEncoder popDebugGroup];
        
        // Resolve MSAA
        if (view.sampleCount > 1)
        {
            [renderEncoder pushDebugGroup:@"My MSAA Resolve"];
            [renderEncoder setRenderPipelineState:_myResolvePipelineState];
            [renderEncoder dispatchThreadsPerTile:MTLSizeMake(16, 16, 1)];
            [renderEncoder popDebugGroup];
        }

        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here
}

@end
