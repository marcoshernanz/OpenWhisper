#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const OWObjCExceptionErrorDomain;

/// The `NSException.name` of the caught exception, e.g. `com.apple.coreaudio.avfaudio`.
FOUNDATION_EXPORT NSString * const OWObjCExceptionNameKey;

/// Swift cannot catch Objective-C exceptions, but AVAudioEngine raises them instead of returning
/// errors, for example when a tap's format no longer matches the input hardware.
@interface OWObjCExceptionCatcher : NSObject

/// Runs `block` and reports an Objective-C exception it raises as an `NSError`.
+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block
               error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(perform(_:));

@end

NS_ASSUME_NONNULL_END
