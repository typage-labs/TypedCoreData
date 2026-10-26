#import "CoreDataExceptionSupport.h"

NSException * _Nullable TCDCaptureException(void (NS_NOESCAPE ^body)(void)) {
    @try {
        body();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
