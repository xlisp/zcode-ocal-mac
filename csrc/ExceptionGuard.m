#import "ExceptionGuard.h"

BOOL ocal_try(void (^block)(void), NSString **outName, NSString **outReason) {
    @try {
        block();
        return YES;
    }
    @catch (NSException *exception) {
        if (outName) *outName = exception.name;
        if (outReason) *outReason = exception.reason;
        return NO;
    }
}
