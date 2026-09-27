#import "OWObjCExceptionCatcher.h"

NSErrorDomain const OWObjCExceptionErrorDomain = @"dev.openwhisper.ObjCException";
NSString * const OWObjCExceptionNameKey = @"OWObjCExceptionName";

@implementation OWObjCExceptionCatcher

+ (BOOL)performBlock:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable __autoreleasing *)error
{
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:OWObjCExceptionErrorDomain
                                         code:0
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: exception.name,
                OWObjCExceptionNameKey: exception.name,
            }];
        }
        return NO;
    }
}

@end
