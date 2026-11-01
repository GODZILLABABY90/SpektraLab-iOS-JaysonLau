#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Original SpektraLab C++20/Metal film-and-paper processing.
@interface OriginalFilmRenderer : NSObject
+ (nullable UIImage *)renderImage:(UIImage *)image
                        filmStock:(NSString *)filmStock
                       printStock:(NSString *)printStock
                        enableEdge:(BOOL)enableEdge
                       edgeFormat:(NSString *)edgeFormat
                     maxDimension:(NSInteger)maxDimension
                            error:(NSError * _Nullable __autoreleasing * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
