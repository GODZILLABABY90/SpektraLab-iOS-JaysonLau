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
#include <cstdlib>
#include <cstdint>
#include <memory>
#include <vector>

static NSError *SPKIosError(NSString *message) {
    return [NSError errorWithDomain:@"io.github.godzillababy90.SpektraLab.Native"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Original engine failed"}];
}

static NSString *SPKEngineError(spk_engine *engine) {
    if (!engine) return @"Original spectral engine could not be initialized";
    const char *description = spk_last_error(engine);
    return description && description[0] ? [NSString stringWithUTF8String:description] : @"Original engine returned an error";
}

@implementation OriginalFilmRenderer


+ (UIImage *)renderImageWithoutThrow:(UIImage *)image
                           filmStock:(NSString *)filmStock
                          printStock:(NSString *)printStock
                          enableEdge:(BOOL)enableEdge
                          edgeFormat:(NSString *)edgeFormat
                          exposureEV:(double)exposureEV
                         grainAmount:(double)grainAmount
                      halationAmount:(double)halationAmount
                            magenta:(double)magenta
                             yellow:(double)yellow
                       maxDimension:(NSInteger)maxDimension
                             options:(NSDictionary<NSString *, id> *)options
                       errorMessage:(NSMutableString *)errorMessage {
    NSError *nativeError = nil;
    UIImage *result = [self renderImage:image
                              filmStock:filmStock
                             printStock:printStock
                             enableEdge:enableEdge
                             edgeFormat:edgeFormat
                             exposureEV:exposureEV
                            grainAmount:grainAmount
                         halationAmount:halationAmount
                               magenta:magenta
                                yellow:yellow
                           maxDimension:maxDimension
                                options:options
                                  error:&nativeError];
    if (!result && errorMessage) {
        NSString *message = @"Original engine returned no image";
        if (nativeError && [nativeError isKindOfClass:[NSError class]]) {
            message = nativeError.localizedDescription ?: message;
        } else if (nativeError) {
            message = @"Native renderer returned an invalid error object";
        }
        [errorMessage setString:message];
    }
    return result;
}


+ (UIImage *)renderImage:(UIImage *)image
               filmStock:(NSString *)filmStock
              printStock:(NSString *)printStock
               enableEdge:(BOOL)enableEdge
                       edgeFormat:(NSString *)edgeFormat
                         exposureEV:(double)exposureEV
                        grainAmount:(double)grainAmount
                     halationAmount:(double)halationAmount
                           magenta:(double)magenta
                            yellow:(double)yellow
            maxDimension:(NSInteger)maxDimension
                 options:(NSDictionary<NSString *, id> *)options
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
        CGImageRef croppedInput = nullptr;
        // Original Film Edge expects the image to have the camera gate's exact
        // aspect ratio. Crop to that gate before opening the native session.
        // Previously arbitrary 4:3 photos were sent as 135 (3:2), causing
        // the upstream overscan layout to reject them or misallocate.
        if ([options[@"overscan_active"] boolValue]) {
            NSString *edgeFormat = options[@"overscan_format"] ?: @"135";
            double gateLong = 36.0, gateShort = 24.0;
            if ([edgeFormat isEqualToString:@"135_half"]) { gateLong = 24; gateShort = 18; }
            else if ([edgeFormat isEqualToString:@"120_645"]) { gateLong = 56; gateShort = 41.5; }
            else if ([edgeFormat isEqualToString:@"120_6x6"]) { gateLong = 56; gateShort = 56; }
            else if ([edgeFormat isEqualToString:@"120_6x7"]) { gateLong = 69.5; gateShort = 56; }
            else if ([edgeFormat isEqualToString:@"120_6x8"]) { gateLong = 76; gateShort = 56; }
            else if ([edgeFormat isEqualToString:@"120_6x9"]) { gateLong = 84; gateShort = 56; }
            else if ([edgeFormat isEqualToString:@"135_xpan"]) { gateLong = 65; gateShort = 24; }
            else if ([edgeFormat isEqualToString:@"120_6x12"]) { gateLong = 112; gateShort = 56; }
            else if ([edgeFormat isEqualToString:@"120_6x17"]) { gateLong = 168; gateShort = 56; }
            const size_t sourceW = CGImageGetWidth(inputCG);
            const size_t sourceH = CGImageGetHeight(inputCG);
            const double aspect = sourceW >= sourceH ? gateLong / gateShort : gateShort / gateLong;
            size_t cropW = sourceW, cropH = sourceH;
            if (double(sourceW) / double(sourceH) > aspect) {
                cropW = std::max(size_t(1), size_t(std::floor(double(sourceH) * aspect)));
            } else {
                cropH = std::max(size_t(1), size_t(std::floor(double(sourceW) / aspect)));
            }
            const CGRect rect = CGRectMake((sourceW - cropW) / 2, (sourceH - cropH) / 2, cropW, cropH);
            croppedInput = CGImageCreateWithImageInRect(inputCG, rect);
            if (!croppedInput) {
                if (error) *error = SPKIosError(@"Could not crop photo to film gate");
                return nil;
            }
            inputCG = croppedInput;
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
                                                    CGBitmapInfo(kCGBitmapByteOrder32Big | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedLast)));
        if (!bitmap) {
            CGColorSpaceRelease(srgb);
            if (error) *error = SPKIosError(@"Could not allocate source pixels");
            return nil;
        }
        // UIKit already normalized EXIF orientation in normalized.CGImage.
        // The bitmap context and its CGImage both use CoreGraphics coordinates;
        // flipping the CTM here inverted the image supplied to the film engine.
        CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), inputCG);
        CGContextRelease(bitmap);
        if (croppedInput) CGImageRelease(croppedInput);

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

        NSMutableDictionary *parameters = [@{
            @"film_stock": filmStock.length ? filmStock : @"kodak_portra_400",
            @"print_stock": printStock.length ? printStock : @"kodak_supra_endura",
            @"auto_exposure": @YES,
            @"auto_exposure_method": @"balanced",
            @"film_format_mm": @36,
            @"filter_shift_scale": @40,
            @"glare_active": @YES,
            @"scan_film": @NO,
            @"input_color_space": @"sRGB",
            @"input_cctf_decoding": @YES,
            @"output_color_space": @"sRGB",
            @"output_cctf_encoding": @YES,
            @"preview_long_edge": @(maxDimension),
                        @"overscan_active": @(enableEdge),
            @"overscan_format": edgeFormat.length ? edgeFormat : @"135",
            @"overscan_mode": @"strip",
            @"overscan_holes": @"white",
            @"exposure_compensation_ev": @(exposureEV),
            @"grain_active": @(grainAmount > 0),
            @"grain_amount": @(grainAmount),
            @"halation_active": @(halationAmount > 0),
            @"halation_amount": @(halationAmount),
            @"m_filter_shift": @(magenta),
            @"y_filter_shift": @(yellow)
        } mutableCopy];
        if (options.count) [parameters addEntriesFromDictionary:options];
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

        NSLog(@"SpektraLab native: render started %zux%zu, film=%@, paper=%@", width, height, filmStock, printStock);
        spk_result result = {};
        const spk_status status = spk_render(session.get(), "full", &result);
        if (status != SPK_OK || !result.rgba16 || !result.width || !result.height) {
            if (error) *error = SPKIosError(SPKEngineError(engine.get()));
            spk_result_free(&result);
            CGColorSpaceRelease(srgb);
            return nil;
        }

        NSLog(@"SpektraLab native: render completed status=%d output=%ux%u stride=%u",
              (int)status, result.width, result.height, result.row_stride_px);
        const size_t w = result.width, h = result.height;
        // The native ABI returns a row stride in pixels, not bytes. Validate
        // it before reading the 16-bit RGBA buffer to avoid out-of-bounds access.
        if (result.row_stride_px < w || w > SIZE_MAX / 4 ||
            h > SIZE_MAX / (w * 4) || w > 8192 || h > 8192) {
            if (error) *error = SPKIosError(@"Original engine returned invalid output dimensions or stride");
            spk_result_free(&result);
            CGColorSpaceRelease(srgb);
            return nil;
        }
        // The 4096 px export path can be memory-bound on iPhone. Transfer
        // ownership of one output allocation to CoreGraphics instead of
        // copying an entire RGBA frame into a second CFData buffer.
        const size_t outputBytes = w * h * 4;
        uint8_t *output = static_cast<uint8_t *>(malloc(outputBytes));
        if (!output) {
            if (error) *error = SPKIosError(@"Not enough memory for rendered image");
            spk_result_free(&result);
            CGColorSpaceRelease(srgb);
            return nil;
        }
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

        // Own the pixel storage for the full lifetime of the returned CGImage.
        // A CGBitmapContext backed by a temporary std::vector can otherwise
        // leave CoreGraphics/UIImage referring to freed caller-owned memory.
        CFDataRef pixelData = CFDataCreateWithBytesNoCopy(
            kCFAllocatorDefault, output, static_cast<CFIndex>(outputBytes),
            kCFAllocatorMalloc);
        if (!pixelData) {
            free(output);
            CGColorSpaceRelease(srgb);
            if (error) *error = SPKIosError(@"Could not retain output pixels");
            return nil;
        }
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixelData);
        CFRelease(pixelData);
        if (!provider) {
            CGColorSpaceRelease(srgb);
            if (error) *error = SPKIosError(@"Could not create output pixel provider");
            return nil;
        }
        CGImageRef resultCG = CGImageCreate(w, h, 8, 32, w * 4, srgb,
                           CGBitmapInfo(kCGBitmapByteOrder32Big | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedLast)),
                           provider, nullptr, false, kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(srgb);
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
