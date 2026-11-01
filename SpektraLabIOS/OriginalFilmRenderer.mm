// Thin Objective-C++ adapter to the ORIGINAL SpektraLab C ABI.
// Upstream: JamesQiu2005/SpektraLab (GPL-3.0-or-later).
// All film, print, grain, halation and Film Edge pixels come from upstream.
#import "OriginalFilmRenderer.h"
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#include "spektrafilm/spk_engine.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

static NSError *SPKIosError(NSString *message) {
    return [NSError errorWithDomain:@"io.github.godzillababy90.SpektraLab.Native"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Original engine failed"}];
}

static NSString *SPKEngineError(spk_engine *engine) {
    const char *description = spk_last_error(engine);
    return description && description[0] ? [NSString stringWithUTF8String:description] : @"Original engine returned an error";
}

@implementation OriginalFilmRenderer

+ (UIImage *)renderImage:(UIImage *)image
               filmStock:(NSString *)filmStock
              printStock:(NSString *)printStock
               enableEdge:(BOOL)enableEdge
            maxDimension:(NSInteger)maxDimension
                   error:(NSError * _Nullable __autoreleasing *)error {
    @autoreleasepool {
        if (!image || maxDimension < 1) {
            if (error) *error = SPKIosError(@"Invalid source image");
            return nil;
        }
        NSString *resourcesDir = [[NSBundle mainBundle] pathForResource:@"OriginalEngineResources" ofType:nil];
        if (!resourcesDir) {
            if (error) *error = SPKIosError(@"Bundled original engine resources are missing");
            return nil;
        }

        // Preview input is bounded for iPhone memory: rendering still occurs in
        // the ORIGINAL film + enlarger/paper + scanning C++/Metal pipeline.
        CGFloat longest = MAX(image.size.width, image.size.height);
        CGFloat scale = MIN(1.0, (CGFloat)maxDimension / MAX(1, longest));
        CGSize target = CGSizeMake(MAX(1, floor(image.size.width * scale)),
                                   MAX(1, floor(image.size.height * scale)));
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        format.opaque = YES;
        UIGraphicsImageRenderer *normalizer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
        UIImage *normalized = [normalizer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
            [[UIColor whiteColor] setFill];
            UIRectFill((CGRect){CGPointZero, target});
            [image drawInRect:(CGRect){CGPointZero, target}];
        }];
        CGImageRef inputCG = normalized.CGImage;
        if (!inputCG) {
            if (error) *error = SPKIosError(@"Could not decode the selected image");
            return nil;
        }

        const size_t width = CGImageGetWidth(inputCG);
        const size_t height = CGImageGetHeight(inputCG);
        if (width == 0 || height == 0 || width > UINT32_MAX || height > UINT32_MAX) {
            if (error) *error = SPKIosError(@"Unsupported photo dimensions");
            return nil;
        }
        std::vector<uint8_t> rgba(width * height * 4);
        CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef bitmap = CGBitmapContextCreate(rgba.data(), width, height, 8,
                                                    width * 4, srgb,
                                                    kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        if (!bitmap) {
            CGColorSpaceRelease(srgb);
            if (error) *error = SPKIosError(@"Could not allocate source pixels");
            return nil;
        }
        CGContextTranslateCTM(bitmap, 0, height);
        CGContextScaleCTM(bitmap, 1, -1);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), inputCG);
        CGContextRelease(bitmap);

        std::vector<float> input(width * height * 3);
        for (size_t i = 0, count = width * height; i < count; ++i) {
            input[3*i]     = float(rgba[4*i]) / 255.0f;
            input[3*i + 1] = float(rgba[4*i + 1]) / 255.0f;
            input[3*i + 2] = float(rgba[4*i + 2]) / 255.0f;
        }

        std::unique_ptr<spk_engine, decltype(&spk_engine_destroy)> engine(
            spk_engine_create(resourcesDir.fileSystemRepresentation, nullptr),
            &spk_engine_destroy);
        if (!engine) {
            if (error) *error = SPKIosError(SPKEngineError(nullptr));
            CGColorSpaceRelease(srgb);
            return nil;
        }

        NSDictionary *parameters = @{
            @"film_stock": filmStock.length ? filmStock : @"kodak_portra_400",
            @"print_stock": printStock.length ? printStock : @"kodak_portra_endura",
            @"input_color_space": @"sRGB",
            @"input_cctf_decoding": @YES,
            @"output_color_space": @"sRGB",
            @"output_cctf_encoding": @YES,
            @"preview_long_edge": @(maxDimension),
            @"product_defaults": @YES,
            @"overscan_active": @(enableEdge),
            @"overscan_format": @"135",
            @"overscan_mode": @"strip",
            @"overscan_holes": @"white"
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:error];
        if (!jsonData) {
            CGColorSpaceRelease(srgb);
            return nil;
        }
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        const spk_image source = { input.data(), static_cast<uint32_t>(width),
                                   static_cast<uint32_t>(height), 3 };
        char *openReply = nullptr;
        std::unique_ptr<spk_session, decltype(&spk_session_release)> session(
            spk_open(engine.get(), &source, json.UTF8String, &openReply),
            &spk_session_release);
        if (openReply) spk_string_free(openReply);
        if (!session) {
            if (error) *error = SPKIosError(SPKEngineError(engine.get()));
            CGColorSpaceRelease(srgb);
            return nil;
        }

        spk_result result = {};
        const spk_status status = spk_render(session.get(), "full", &result);
        if (status != SPK_OK || !result.rgba16 || !result.width || !result.height) {
            if (error) *error = SPKIosError(SPKEngineError(engine.get()));
            spk_result_free(&result);
            CGColorSpaceRelease(srgb);
            return nil;
        }

        const size_t w = result.width, h = result.height;
        std::vector<uint8_t> output(w * h * 4);
        for (size_t y = 0; y < h; ++y) {
            const uint16_t *row = result.rgba16 + y * result.row_stride_px * 4;
            for (size_t x = 0; x < w; ++x) {
                const size_t pixel = (y * w + x) * 4;
                output[pixel]     = uint8_t(row[x*4] >> 8);
                output[pixel + 1] = uint8_t(row[x*4 + 1] >> 8);
                output[pixel + 2] = uint8_t(row[x*4 + 2] >> 8);
                output[pixel + 3] = 255;
            }
        }
        spk_result_free(&result);

        CGContextRef outputCtx = CGBitmapContextCreate(output.data(), w, h, 8,
                         w * 4, srgb, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(srgb);
        if (!outputCtx) {
            if (error) *error = SPKIosError(@"Could not allocate output image");
            return nil;
        }
        CGImageRef resultCG = CGBitmapContextCreateImage(outputCtx);
        CGContextRelease(outputCtx);
        if (!resultCG) {
            if (error) *error = SPKIosError(@"Could not form rendered image");
            return nil;
        }
        UIImage *resultImage = [UIImage imageWithCGImage:resultCG scale:1 orientation:UIImageOrientationUp];
        CGImageRelease(resultCG);
        return resultImage;
    }
}
@end
