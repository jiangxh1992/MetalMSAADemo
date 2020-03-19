//
//  Renderer.m
//  MetalGameDemo
//
//  Created by Xinhou Jiang on 2020/2/9.
//  Copyright © 2020 Xinhou Jiang. All rights reserved.
//

#import <simd/simd.h>
#import "Renderer.h"
#import "ShaderTypes.h"

#define SampleCount 4

@implementation Renderer
{
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    id <MTLRenderPipelineState> _pipelineState;
    id <MTLRenderPipelineState> _myResolvePipelineState;
    id <MTLDepthStencilState> _depthState;
    
    id<MTLBuffer> vertexBuffer;
    id<MTLTexture> msaaRT;
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
    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.sampleCount = SampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSError *error = NULL;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    // MSAA Texture
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                     width: view.frame.size.width
                                    height:view.frame.size.height
                                 mipmapped:NO];
    if(SampleCount > 1)
        texDesc.textureType = MTLTextureType2DMultisample;
    else
        texDesc.textureType = MTLTextureType2D;
    texDesc.sampleCount = SampleCount;
    texDesc.usage |= MTLTextureUsageRenderTarget;
    texDesc.storageMode = MTLStorageModeMemoryless;
    texDesc.pixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
    texDesc.usage |= MTLTextureUsageShaderWrite;
    texDesc.storageMode = MTLStoreActionMultisampleResolve;
    msaaRT = [_device newTextureWithDescriptor:texDesc];
    msaaRT.label = @"msaaRT";
    
    // MSAA resolve
    {
        NSError *error;
        
        id <MTLFunction> customResolveKernel = [defaultLibrary newFunctionWithName:@"my_resolve"];
        
        MTLTileRenderPipelineDescriptor *myResolvePipelineDescriptor = [MTLTileRenderPipelineDescriptor new];
        myResolvePipelineDescriptor.label = @"My Resolve";
        myResolvePipelineDescriptor.rasterSampleCount = SampleCount;
        myResolvePipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        myResolvePipelineDescriptor.threadgroupSizeMatchesTileSize = YES;
        myResolvePipelineDescriptor.tileFunction = customResolveKernel;
        _myResolvePipelineState = [_device newRenderPipelineStateWithTileDescriptor:myResolvePipelineDescriptor
                                                                                   options:0 reflection:nil error:&error];
        
        NSAssert(_myResolvePipelineState, @"Failed to create pipeline state: %@", error);
    }
/*
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
*/
    _commandQueue = [_device newCommandQueue];
}

- (void)_loadAssets
{
    /// Load assets into metal objects
    static const Vertex vert[] = {
        {{0,1.0}},
        {{0.8,-1.0}},
        {{-0.6,-1.0}}
    };
    vertexBuffer = [_device newBufferWithBytes:vert length:sizeof(vert) options:MTLResourceStorageModeShared];
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";
    
    // Opaque Forward Pass
    MTLRenderPassDescriptor* renderPassDescriptor = [[MTLRenderPassDescriptor alloc] init];
    renderPassDescriptor.colorAttachments[0].texture = msaaRT;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionDontCare;
    renderPassDescriptor.tileWidth = 16;
    renderPassDescriptor.tileHeight = 16;
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        [renderEncoder pushDebugGroup:@"Draw"];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [renderEncoder popDebugGroup];
        
        // Resolve MSAA
        if (SampleCount > 1)
        {
            [renderEncoder pushDebugGroup:@"My MSAA Resolve"];
            [renderEncoder setRenderPipelineState:_myResolvePipelineState];
            [renderEncoder dispatchThreadsPerTile:MTLSizeMake(16, 16, 1)];
            [renderEncoder popDebugGroup];
        }
        [renderEncoder endEncoding];
    }
    
    // Copy to backbuffer
    //MTLRenderPassDescriptor* curRenderPassDescriptor = view.currentRenderPassDescriptor;
    // ...
    [commandBuffer presentDrawable:view.currentDrawable];

    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here
}

@end
