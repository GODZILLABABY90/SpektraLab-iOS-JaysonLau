#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Original SpektraLab C++20/Metal film-and-paper processing.
@interface OriginalFilmRenderer : NSObject
+ (nullable UIImage *)renderImage:(UIImage *)image
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
                            error:(NSError * _Nullable __autoreleasing * _Nullable)error;

 // Explicit non-throwing Swift entry point. Never bridge native NSError** as Swift Error.
+ (nullable UIImage *)renderImageWithoutThrow:(UIImage *)image
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
                                errorMessage:(NSMutableString *)errorMessage;
@end

NS_ASSUME_NONNULL_END
